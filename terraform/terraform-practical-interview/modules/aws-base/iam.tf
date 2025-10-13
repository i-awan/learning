module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.16.0"

  role_name = "${local.prefix}-ebs-csi"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  attach_ebs_csi_policy = true
}

module "node_termination_handler_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.16.0"

  role_name = "${local.prefix}-node-termination-handler"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node-termination-handler"]
    }
  }

  attach_node_termination_handler_policy = true
}

module "fluent_bit_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.16.0"

  role_name = "${local.prefix}-fluent-bit"

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-for-fluent-bit"]
    }
  }
}

data "aws_iam_policy_document" "fluent_bit_cloudwatch" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
      "logs:PutRetentionPolicy",
      "logs:GetLogEvents",
      "logs:CreateLogGroup",
    ]
    resources = [
      "arn:aws:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/eks/${local.prefix}/workload/*"
    ]
  }
}

resource "aws_iam_role_policy" "fluent_bit_cloudwatch" {
  role   = module.fluent_bit_irsa.iam_role_name
  policy = data.aws_iam_policy_document.fluent_bit_cloudwatch.json
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "19.21.0"

  irsa_name            = "${local.prefix}-karpenter"
  irsa_use_name_prefix = false

  cluster_name = module.eks.cluster_name
  irsa_tag_key = "karpenter.sh/managed-by"

  irsa_oidc_provider_arn = module.eks.oidc_provider_arn

  create_iam_role          = false
  iam_role_arn             = aws_iam_role.eks_node.arn
  iam_role_use_name_prefix = false
}


