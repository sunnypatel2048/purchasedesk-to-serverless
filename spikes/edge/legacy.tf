# Stand-in for the legacy server: a private instance with no public address, reachable only by CloudFront.

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "legacy" {
  name        = "${local.name}-legacy"
  description = "Legacy stand-in: HTTP from CloudFront origin-facing addresses only"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${local.name}-legacy" }
}

resource "aws_vpc_security_group_ingress_rule" "legacy_http_from_cloudfront" {
  security_group_id = aws_security_group.legacy.id
  description       = "HTTP from CloudFront"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing.id
}

resource "aws_instance" "legacy" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.legacy.id]
  associate_public_ip_address = false
  user_data_replace_on_change = true

  # No packages to install (there is no route out), so the server is the Python standard library.
  user_data = <<-EOF
    #!/bin/bash
    cat > /usr/local/bin/spike-legacy.py <<'PY'
    import json
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = json.dumps({"servedBy": "legacy", "path": self.path}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("X-Served-By", "legacy")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    ThreadingHTTPServer(("0.0.0.0", 80), Handler).serve_forever()
    PY
    nohup python3 /usr/local/bin/spike-legacy.py >/var/log/spike-legacy.log 2>&1 &
  EOF

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = { Name = "${local.name}-legacy" }
}
