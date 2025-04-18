# backend.tf (this is where the backend configuration goes)
terraform {
  backend "s3" {
    bucket         = "eks-state-bucket-ia"   # The bucket you created
    key            = "eks/terraform.tfstate"  # Path in the bucket to store state
    region         = "eu-west-2"  # Region where your S3 bucket is created
    #dynamodb_table = "terraform-lock"  # DynamoDB table for state locking
    encrypt        = true  # Enable encryption for state
  }
}
