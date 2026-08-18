#!/bin/bash
set -e

CLUSTER_NAME=${CLUSTER_NAME:-stackwright}
REGION=${REGION:-eu-west-1}
MAX_WAIT=2400  # 40 minutes max wait
INTERVAL=30

echo "======================================"
echo " StackWright ROSA Platform Deploy"
echo "======================================"


# -----------------------------------------------
# Set ROSA authentication
# -----------------------------------------------

echo "Export for current session"
export RHCS_TOKEN=$(rosa token --generate)

echo "Verify"
echo $RHCS_TOKEN | head -c 20

echo "Add permanently to shell"
echo "export RHCS_TOKEN=\"$(rosa token --generate)\"" >> ~/.zshrc
source ~/.zshrc


# -----------------------------------------------
# Initialise Terraform
# -----------------------------------------------
echo "Initialise Terraform"
terraform init

# -----------------------------------------------
# Pre-flight checks
# -----------------------------------------------
echo ""
echo ">>> Pre-flight checks..."
aws sts get-caller-identity > /dev/null && echo "✅ AWS credentials valid"
rosa whoami > /dev/null && echo "✅ ROSA authenticated"

# -----------------------------------------------
# Phase 1 — VPC
# -----------------------------------------------
echo ""
echo ">>> Phase 1: Deploying VPC..."
terraform apply -target=module.vpc --auto-approve
echo "✅ VPC complete"

# -----------------------------------------------
# Create account roles via ROSA CLI
# -----------------------------------------------
echo ""
echo ">>> Creating ROSA account roles..."

# Check if roles already exist
EXISTING=$(rosa list account-roles 2>/dev/null | grep "$CLUSTER_NAME" | wc -l)

if [ "$EXISTING" -ge 3 ]; then
  echo "✅ Account roles already exist — skipping"
else
  rosa create account-roles \
    --hosted-cp \
    --prefix $CLUSTER_NAME \
    --mode auto \
    --yes
  echo "✅ Account roles created"
fi

# Verify roles exist
rosa list account-roles | grep $CLUSTER_NAME

# -----------------------------------------------
# Phase 2 — IAM + OIDC + Operator Roles
# -----------------------------------------------
echo ""
echo ">>> Phase 2: Deploying IAM + OIDC..."
terraform apply -target=module.iam --auto-approve
echo "✅ IAM complete"

# -----------------------------------------------
# Create operator roles via ROSA CLI
# -----------------------------------------------
echo ""
echo ">>> Creating operator roles..."

# Open deploy.sh and manually replace the OIDC_ID line with:
OIDC_ID=$(terraform state show module.iam.rhcs_rosa_oidc_config.oidc | grep '    id ' | awk '{print $3}' | tr -d '"')
echo "  OIDC ID: $OIDC_ID"

INSTALLER_ARN=$(aws iam get-role \
  --role-name ${CLUSTER_NAME}-HCP-ROSA-Installer-Role \
  --query 'Role.Arn' \
  --output text)

echo "  Installer ARN: $INSTALLER_ARN"

# Check if operator roles already exist
EXISTING_OP=$(rosa list operator-roles 2>/dev/null | grep "$CLUSTER_NAME" | wc -l)

if [ "$EXISTING_OP" -ge 1 ]; then
  echo "✅ Operator roles already exist — skipping"
else
  rosa create operator-roles \
    --hosted-cp \
    --prefix $CLUSTER_NAME \
    --oidc-config-id $OIDC_ID \
    --installer-role-arn $INSTALLER_ARN \
    --mode auto \
    --yes
  echo "✅ Operator roles created"
fi

# -----------------------------------------------
# Phase 3 — ROSA Cluster
# -----------------------------------------------
echo ""
echo ">>> Phase 3: Deploying ROSA Cluster..."
terraform apply -target=module.rosa --auto-approve
echo "✅ ROSA cluster creation initiated"

# -----------------------------------------------
# Wait for cluster to be ready
# -----------------------------------------------
echo ""
echo ">>> Waiting for cluster to be ready..."
ELAPSED=0

while true; do
  STATE=$(rosa describe cluster -c $CLUSTER_NAME \
    --output json 2>/dev/null | \
    python3 -c "import sys,json; print(json.load(sys.stdin)['status']['state'])" \
    2>/dev/null || echo "unknown")

  echo "  Cluster state: $STATE (${ELAPSED}s elapsed)"

  if [ "$STATE" == "ready" ]; then
    echo "✅ Cluster is ready!"
    break
  fi

  if [ "$STATE" == "error" ]; then
    echo "❌ Cluster entered error state"
    rosa describe cluster -c $CLUSTER_NAME
    exit 1
  fi

  if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo "❌ Timeout after ${MAX_WAIT}s"
    exit 1
  fi

  sleep $INTERVAL
  ELAPSED=$((ELAPSED + INTERVAL))
done

# -----------------------------------------------
# Update kubeconfig — fully automated
# -----------------------------------------------
echo ""
echo ">>> Updating kubeconfig..."

# Get API URL
API_URL=$(rosa describe cluster -c $CLUSTER_NAME \
  --output json | \
  python3 -c "import sys,json; print(json.load(sys.stdin)['api']['url'])")

echo "  API URL: $API_URL"

# Delete existing admin user if exists — ensures clean password capture
echo "  Deleting existing admin user if exists..."
rosa delete admin --cluster=$CLUSTER_NAME --yes 2>/dev/null || true
sleep 5

# Create admin and capture password
ADMIN_OUTPUT=$(rosa create admin --cluster=$CLUSTER_NAME 2>&1)
echo "$ADMIN_OUTPUT"

# Extract password from output
ADMIN_PASS=$(echo "$ADMIN_OUTPUT" | \
  grep -o '[A-Za-z0-9]*-[A-Za-z0-9]*-[A-Za-z0-9]*-[A-Za-z0-9]*' | \
  tail -1)

echo "  Extracted password: $ADMIN_PASS"

# Wait for admin access to activate
echo "  Waiting 30s for admin access to activate..."
sleep 30

# Login automatically
oc login $API_URL \
  --username cluster-admin \
  --password $ADMIN_PASS \
  --insecure-skip-tls-verify=true

echo "✅ kubeconfig updated"


#  Verify nodes. Wait for admin permissions to propagate
echo ">>> Waiting for cluster-admin permissions..."
until oc get nodes 2>/dev/null; do
  echo "  Permissions not ready yet — waiting 15s..."
  sleep 15
done

echo "✅ Cluster access confirmed"


# -----------------------------------------------
# Phase 4 — OpenShift Config
# -----------------------------------------------
echo ""
echo ">>> Phase 4: Deploying OpenShift Config..."
terraform apply -target=module.openshift_config --auto-approve
echo "✅ OpenShift config complete"


# -----------------------------------------------
# Phase 5 — ArgoCD Operator via yaml
# -----------------------------------------------
echo ""
echo ">>> Phase 5: Installing ArgoCD Operator..."

# Apply Subscription
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo "✅ ArgoCD subscription created"

# -----------------------------------------------
# Wait for operator pod
# -----------------------------------------------
echo ""
echo ">>> Waiting for GitOps operator pod..."
until oc get pods -n openshift-operators 2>/dev/null | \
  grep -q "gitops-operator.*Running"; do
  echo "  Waiting for operator pod..."
  sleep 15
done
echo "✅ Operator pod running"

# -----------------------------------------------
# Wait for openshift-gitops namespace
# -----------------------------------------------
echo ""
echo ">>> Waiting for openshift-gitops namespace..."
until oc get namespace openshift-gitops 2>/dev/null; do
  echo "  Waiting for namespace..."
  sleep 15
done
echo "✅ openshift-gitops namespace ready"

# -----------------------------------------------
# Wait for ArgoCD CRDs
# -----------------------------------------------
echo ""
echo ">>> Waiting for ArgoCD CRDs..."
until oc get crd applications.argoproj.io 2>/dev/null; do
  echo "  Waiting for CRDs..."
  sleep 15
done
echo "✅ ArgoCD CRDs ready"

# Extra buffer for CRDs to fully register
echo ">>> Waiting 30s for CRDs to fully register..."
sleep 30

# -----------------------------------------------
# Phase 5 cont — Secret + Application CR via Terraform
# -----------------------------------------------
echo ""
echo ">>> Deploying ArgoCD secret and Application CR..."
terraform apply -target=module.argocd --auto-approve
echo "✅ ArgoCD configured"