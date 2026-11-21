# Stand-in for the new system: API Gateway HTTP API in front of one Lambda function.

data "archive_file" "new" {
  type        = "zip"
  source_file = "${path.module}/lambda/handler.py"
  output_path = "${path.module}/.build/new.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "new" {
  name               = "${local.name}-new"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "new_logs" {
  role       = aws_iam_role.new.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Created here so destroy removes it; otherwise Lambda creates it and it outlives the spike.
resource "aws_cloudwatch_log_group" "new" {
  name              = "/aws/lambda/${local.name}-new"
  retention_in_days = 1
}

resource "aws_lambda_function" "new" {
  function_name    = "${local.name}-new"
  role             = aws_iam_role.new.arn
  runtime          = "python3.13"
  architectures    = ["arm64"]
  handler          = "handler.handler"
  filename         = data.archive_file.new.output_path
  source_code_hash = data.archive_file.new.output_base64sha256
  timeout          = 5

  depends_on = [aws_cloudwatch_log_group.new, aws_iam_role_policy_attachment.new_logs]
}

resource "aws_apigatewayv2_api" "new" {
  name          = "${local.name}-new"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "new" {
  api_id                 = aws_apigatewayv2_api.new.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.new.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "new" {
  api_id    = aws_apigatewayv2_api.new.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.new.id}"
}

resource "aws_apigatewayv2_stage" "new" {
  api_id      = aws_apigatewayv2_api.new.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.new.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.new.execution_arn}/*/*"
}
