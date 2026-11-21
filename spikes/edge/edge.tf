# The front door: one CloudFront distribution, two origins, and a function that picks one per request.

resource "aws_cloudfront_key_value_store" "weights" {
  name    = "${local.name}-weights"
  comment = "Per-route traffic weights for the 0.5 spike"
}

# Initial weight only. Scripts change it at runtime, so Terraform ignores later values.
resource "aws_cloudfrontkeyvaluestore_key" "ping_weight" {
  key_value_store_arn = aws_cloudfront_key_value_store.weights.arn
  key                 = "weight:GET:/api/ping"
  value               = "0"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_cloudfront_function" "router" {
  name    = "${local.name}-router"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = templatefile("${path.module}/function.js.tftpl", {
    kvs_id = element(split("/", aws_cloudfront_key_value_store.weights.arn), 1)
  })
  key_value_store_associations = [aws_cloudfront_key_value_store.weights.arn]
}

resource "aws_cloudfront_vpc_origin" "legacy" {
  vpc_origin_endpoint_config {
    name                   = "${local.name}-legacy"
    arn                    = aws_instance.legacy.arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only" # inside the VPC; production would put a certificate on IIS

    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }
}

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

# Forwarding the viewer's Host header to API Gateway makes it answer 403.
data "aws_cloudfront_origin_request_policy" "all_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = "${local.name} front door"
  price_class         = "PriceClass_100"
  wait_for_deployment = true # so apply times include the real deployment

  origin {
    origin_id   = "legacy"
    domain_name = aws_instance.legacy.private_dns

    vpc_origin_config {
      vpc_origin_id = aws_cloudfront_vpc_origin.legacy.id
    }
  }

  origin {
    origin_id   = "new"
    domain_name = replace(aws_apigatewayv2_api.new.api_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "legacy"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_except_host.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.router.arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = local.name }
}
