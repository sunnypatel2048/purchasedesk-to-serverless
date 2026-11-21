# Alarm notifications. Lives in the bootstrap layer because an email subscription must be confirmed by clicking a
# link: in the ephemeral platform layer it would need confirming again after every `make up`.
#
# Not KMS-encrypted: CloudWatch alarms cannot publish to a topic encrypted with the AWS-managed aws/sns key, and a
# customer-managed key costs about $1/month. Alarm messages contain nothing sensitive.
#
# No budget here: the AWS account's budget alerts already exist in another project's bootstrap layer and cover
# this project's spend too.
resource "aws_sns_topic" "alerts" {
  #checkov:skip=CKV_AWS_26:CloudWatch alarms cannot publish to an aws/sns-encrypted topic; alarm messages are not sensitive
  name = "${var.project}-alerts"
}

# AWS emails a confirmation link; the subscription stays "pending" until it is clicked.
resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alerts_email
}
