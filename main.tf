terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
provider "aws" {
  region = "eu-west-2"
}
resource "aws_s3_bucket" "reports" {
  bucket = "heavenli-cost-reports-2026"
}
resource "aws_sns_topic" "alerts" {
  name = "cost-report-alerts"
}
resource "aws_iam_role" "scanner_role" {
  name = "cost-optimiser-scanner-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ec2_readonly" {
  role       = aws_iam_role.scanner_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.scanner_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}
resource "aws_iam_role_policy" "write_reports" {
  name = "write-cost-reports"
  role = aws_iam_role.scanner_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:PutObject"
      Resource = "${aws_s3_bucket.reports.arn}/*"
    }]
  })
}
resource "aws_iam_role_policy" "publish_alerts" {
  name = "publish-cost-alerts"
  role = aws_iam_role.scanner_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = aws_sns_topic.alerts.arn
    }]
  })
}
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/src/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}
resource "aws_lambda_function" "scanner" {
  function_name = "cost-optimiser-scanner"
  role          = aws_iam_role.scanner_role.arn
  runtime       = "python3.13"
  handler       = "lambda_function.lambda_handler"
  timeout       = 30
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      REPORTS_BUCKET = aws_s3_bucket.reports.bucket
      SNS_TOPIC_ARN  = aws_sns_topic.alerts.arn
    }
  }
}
resource "aws_cloudwatch_event_rule" "daily" {
  name                = "daily-cost-scan"
  schedule_expression = "cron(0 8 * * ? *)"
}
resource "aws_cloudwatch_event_target" "run_scanner" {
  rule = aws_cloudwatch_event_rule.daily.name
  arn  = aws_lambda_function.scanner.arn
}
resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.scanner.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}
