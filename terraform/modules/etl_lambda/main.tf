resource "aws_iam_role" "etl_lambda_role" {
  name = "etl-lambda-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "etl_lambda_basic_execution" {
  role       = aws_iam_role.etl_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "etl_lambda_vpc_access" {
  role       = aws_iam_role.etl_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "etl_lambda_permissions" {
  name = "etl-lambda-permissions-${var.environment}"
  role = aws_iam_role.etl_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParameterHistory"
        ]
        Resource = "arn:aws:ssm:*:*:parameter/city-permit/${var.environment}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_name}",
          "arn:aws:s3:::${var.s3_bucket_name}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "rds-db:connect"
        ]
        Resource = [
          "arn:aws:rds-db:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:dbuser:${var.db_endpoint}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_security_group" "etl_lambda_sg" {
  name   = "etl-lambda-sg-${var.environment}"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_lambda_function" "etl_lambda" {
  function_name = "etl-worker-${var.environment}"
  role          = aws_iam_role.etl_lambda_role.arn
  package_type  = "Image"
  image_uri     = "${var.ecr_repo_url}:latest" # Assumes 'latest' tag for simplicity
  timeout       = 600
  memory_size   = 2048
  architectures = ["arm64"]
  ephemeral_storage {
    size = 1024
  }

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.etl_lambda_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT = var.environment
      DB_ENDPOINT = var.db_endpoint
      DB_PASSWORD = var.db_password
      DB_NAME     = var.db_name
      S3_BUCKET   = var.s3_bucket_name
      # Add other environment variables as needed by your ETL process
    }
  }
}

# EventBridge rules for nightly jobs
# Zoning
resource "aws_cloudwatch_event_rule" "zoning_nightly" {
  name                = "etl-zoning-nightly-${var.environment}"
  description         = "Triggers ETL Lambda for zoning data nightly"
  schedule_expression = "cron(0 6 * * ? *)" # 6 AM UTC daily
}

resource "aws_cloudwatch_event_target" "zoning_target" {
  rule      = aws_cloudwatch_event_rule.zoning_nightly.name
  arn       = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "zoning" })
  target_id = "etl-zoning"
}

resource "aws_lambda_permission" "allow_cloudwatch_zoning" {
  statement_id  = "AllowExecutionFromCloudWatchZoning"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.zoning_nightly.arn
}

# Tier2
resource "aws_cloudwatch_event_rule" "tier2_nightly" {
  name                = "etl-tier2-nightly-${var.environment}"
  description         = "Triggers ETL Lambda for tier2 data nightly"
  schedule_expression = "cron(0 6 * * ? *)" # 6 AM UTC daily
}

resource "aws_cloudwatch_event_target" "tier2_target" {
  rule      = aws_cloudwatch_event_rule.tier2_nightly.name
  arn       = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "tier2" })
  target_id = "etl-tier2"
}

resource "aws_lambda_permission" "allow_cloudwatch_tier2" {
  statement_id  = "AllowExecutionFromCloudWatchTier2"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.tier2_nightly.arn
}

# Building Permits
resource "aws_cloudwatch_event_rule" "building_permits_nightly" {
  name                = "etl-building-permits-nightly-${var.environment}"
  description         = "Triggers ETL Lambda for building permits data nightly"
  schedule_expression = "cron(0 6 * * ? *)" # 6 AM UTC daily
}

resource "aws_cloudwatch_event_target" "building_permits_target" {
  rule      = aws_cloudwatch_event_rule.building_permits_nightly.name
  arn       = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "building_permits" })
  target_id = "etl-building-permits"
}

resource "aws_lambda_permission" "allow_cloudwatch_building_permits" {
  statement_id  = "AllowExecutionFromCloudWatchBuildingPermits"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.building_permits_nightly.arn
}

# DevApp
resource "aws_cloudwatch_event_rule" "devapp_nightly" {
  name                = "etl-devapp-nightly-${var.environment}"
  description         = "Triggers ETL Lambda for devapp data nightly"
  schedule_expression = "cron(0 6 * * ? *)" # 6 AM UTC daily
}

resource "aws_cloudwatch_event_target" "devapp_target" {
  rule      = aws_cloudwatch_event_rule.devapp_nightly.name
  arn       = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "devapp" })
  target_id = "etl-devapp"
}

resource "aws_lambda_permission" "allow_cloudwatch_devapp" {
  statement_id  = "AllowExecutionFromCloudWatchDevApp"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.devapp_nightly.arn
}

# Overlays
resource "aws_cloudwatch_event_rule" "overlays_nightly" {
  name                = "etl-overlays-nightly-${var.environment}"
  description         = "Triggers ETL Lambda for overlays data nightly"
  schedule_expression = "cron(0 6 * * ? *)" # 6 AM UTC daily
}

resource "aws_cloudwatch_event_target" "overlays_target" {
  rule      = aws_cloudwatch_event_rule.overlays_nightly.name
  arn       = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "overlays" })
  target_id = "etl-overlays"
}

resource "aws_lambda_permission" "allow_cloudwatch_overlays" {
  statement_id  = "AllowExecutionFromCloudWatchOverlays"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.overlays_nightly.arn
}

# AIC
resource "aws_cloudwatch_event_rule" "aic_nightly" {
  name                = "etl-aic-nightly-${var.environment}"
  description         = "Triggers ETL Lambda for AIC data nightly"
  schedule_expression = "cron(0 6 * * ? *)" # 6 AM UTC daily
}

resource "aws_cloudwatch_event_target" "aic_target" {
  rule      = aws_cloudwatch_event_rule.aic_nightly.name
  arn       = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "aic" })
  target_id = "etl-aic"
}

resource "aws_lambda_permission" "allow_cloudwatch_aic" {
  statement_id  = "AllowExecutionFromCloudWatchAIC"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.aic_nightly.arn
}