output "region" {
  value = var.region
}

output "state_bucket" {
  description = "Terraform state bucket. Goes in backend.hcl for every layer (gitignored: it contains the account ID)."
  value       = aws_s3_bucket.tfstate.bucket
}

output "artifact_bucket" {
  description = "Release artifacts, under releases/<commit>/."
  value       = aws_s3_bucket.artifacts.bucket
}

output "ci_role_arns" {
  description = "Set as GitHub Actions secrets AWS_PUSH_ROLE_ARN and AWS_PLAN_ROLE_ARN."
  value = {
    push = aws_iam_role.ci_push.arn
    plan = aws_iam_role.ci_plan.arn
  }
}

output "alerts_topic_arn" {
  description = "SNS topic for CloudWatch alarm notifications (used by the platform layer)."
  value       = aws_sns_topic.alerts.arn
}
