locals {
  kubernetes_version = var.eks_cluster_version

}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.1"

  cluster_name             = local.prefix
  cluster_version          = local.kubernetes_version
  iam_role_use_name_prefix = false

  cluster_endpoint_public_access       = true


  node_security_group_additional_rules = {
    http_access = {
      protocol                 = "tcp"
      from_port                = 30443
      to_port                  = 30443
      type                     = "ingress"
      source_security_group_id = aws_security_group.workspace_lb_sg[0].id
      cidr_blocks              = null
    }
  }

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent          = true
      configuration_values = jsonencode({})
    }
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.iam_role_arn
    }
  }

  vpc_id     = local.vpc_id
  subnet_ids = local.private_subnet_ids
}


data "aws_iam_policy_document" "node_assume_role_policy" {
  statement {
    sid     = "EKSNodeAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "${local.prefix}-node"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "eks_node" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
  ])

  policy_arn = each.value
  role       = aws_iam_role.eks_node.name
}

resource "aws_iam_role_policy" "eks_node_pullthrough" {
  role   = aws_iam_role.eks_node.name
  name   = "allow-ecr-pullthrough"
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [ "ecr:BatchImportUpstreamImage" ],
            "Resource": "*"
        }
    ]
}
EOF
}

module "eks_critical_services_nodegroup" {
  count   = length(local.private_subnet_ids)
  source  = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 19.0"

  name            = "${local.prefix}-critical-services-${count.index}"
  use_name_prefix = false
  cluster_name    = module.eks.cluster_name
  cluster_version = local.kubernetes_version

  create_iam_role = false
  iam_role_arn    = aws_iam_role.eks_node.arn
  subnet_ids      = [local.private_subnet_ids[count.index]]

  cluster_primary_security_group_id = module.eks.cluster_primary_security_group_id
  vpc_security_group_ids            = [module.eks.node_security_group_id]
  min_size                          = 1
  max_size                          = 1
  desired_size                      = 1

  instance_types = ["m6a.2xlarge"]

  labels = {
    node-purpose = "system"
  }

  taints = {
    CriticalAddonsOnly = {
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }
  }
}
