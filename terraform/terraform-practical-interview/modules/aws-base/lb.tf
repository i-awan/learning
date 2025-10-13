locals {
  lb_resource_trunc = substr(var.scale_deployment_id, 0, 12)
}

resource "aws_security_group" "workspace_lb_sg" {
  name        = "scale-egp-lb-${local.lb_resource_trunc}"
  description = "Security group for workspace lb"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "workspace_lb" {
  name               = "scale-sgp-${local.lb_resource_trunc}"
  subnets            = module.vpc.public_subnets
  load_balancer_type = "application"
  security_groups    = [aws_security_group.workspace_lb_sg.id]
}

resource "aws_lb_target_group" "workspace_lb_ingress" {
  name     = "scale-sgp-${local.lb_resource_trunc}-ingress"
  port     = 30443
  protocol = "HTTPS"
  vpc_id   = local.vpc_id
  health_check {
    path     = "/"
    protocol = "HTTPS"
    matcher  = "200,404,400"
  }
}

resource "aws_autoscaling_attachment" "workspace_lb_ingress" {
  count                  = length(local.private_subnet_ids)
  autoscaling_group_name = module.eks_critical_services_nodegroup[count.index].node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.workspace_lb_ingress[0].arn
}

// The aws_lb_listener and certificates are not relevant for this task.