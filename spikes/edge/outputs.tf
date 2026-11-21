output "domain" {
  description = "The front door"
  value       = aws_cloudfront_distribution.this.domain_name
}

output "kvs_arn" {
  description = "Where the scripts write weights"
  value       = aws_cloudfront_key_value_store.weights.arn
}
