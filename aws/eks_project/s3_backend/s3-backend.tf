# s3-backend.tf
resource "aws_s3_bucket" "tf_state" {
  bucket = "eks-state-bucket-ia" 
  acl    = "private"
}

#resource "aws_dynamodb_table" "tf_state_lock" {
#  name         = "terraform-lock"
#  hash_key     = "LockID"
#  read_capacity  = 5
#  write_capacity = 5
#  attribute {
#    name = "LockID"
#    type = "S"
#  }
#}
