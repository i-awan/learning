data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  prefix = "scale-egp-${var.scale_deployment_id}"
}
