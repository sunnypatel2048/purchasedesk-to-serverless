# Same state bucket as the bootstrap layer, its own key, so destroying the platform can never touch bootstrap state.
# Bucket and region come from the bootstrap layer's backend.hcl (gitignored: it holds the AWS account ID).
#   terraform init -backend-config=../bootstrap/backend.hcl
terraform {
  backend "s3" {
    key          = "platform/terraform.tfstate"
    encrypt      = true
    use_lockfile = true # native S3 locking; no DynamoDB table
  }
}
