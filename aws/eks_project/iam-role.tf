# iam-role.tf (or main.tf)
provider "aws" {
  region = "eu-west-2"  # Change this to your desired region
}

resource "aws_iam_role" "example_role" {
  name               = var.role_name  # Use the role name from the variable
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"  # Specify which service will assume the role
        }
      }
    ]
  })
}

output "iam_role_name" {
  value = aws_iam_role.example_role.name
}

