locals {
  # Monorepo format for Next.js SSR (WEB_COMPUTE)
  build_spec_compute = <<-EOT
    version: 1
    applications:
      - frontend:
          phases:
            preBuild:
              commands:
                - npm install
            build:
              commands:
                - npm run build
          artifacts:
            baseDirectory: .next
            files:
              - '**/*'
          cache:
            paths:
              - node_modules/**/*
        appRoot: frontend
  EOT

  # Monorepo format for Static Export (WEB)
  build_spec_static = <<-EOT
    version: 1
    applications:
      - frontend:
          phases:
            preBuild:
              commands:
                - npm install
            build:
              commands:
                - npm run build
          artifacts:
            baseDirectory: out
            files:
              - '**/*'
          cache:
            paths:
              - node_modules/**/*
        appRoot: frontend
  EOT
}

# 1. ECR Repository
resource "aws_ecr_repository" "app" {
  name                 = "${var.app_name}-backend-${var.environment}"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# 2. S3 Bucket for assets
resource "aws_s3_bucket" "assets" {
  bucket = "${var.app_name}-assets-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    id     = "expire-old-temp-objects"
    status = "Enabled"

    filter {
      prefix = "temp/"
    }

    expiration {
      days = 30
    }
  }
}

data "aws_caller_identity" "current" {}

# 3. SQS Queue
resource "aws_sqs_queue" "app_queue" {
  name                       = "${var.app_name}-queue-${var.environment}"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
}

# 4. IAM Role for Lambda
resource "aws_iam_role" "lambda" {
  name = "${var.app_name}-lambda-role-${var.environment}"

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "ssm" {
  name = "${var.app_name}-ssm-policy-${var.environment}"
  role = aws_iam_role.lambda.id

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
          aws_s3_bucket.assets.arn,
          "${aws_s3_bucket.assets.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.app_queue.arn
      }
    ]
  })
}

# 5. Lambda Function
resource "aws_lambda_function" "app" {
  function_name = "${var.app_name}-api-${var.environment}"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:latest"

  timeout       = 28
  memory_size   = 512
  architectures = ["arm64"]

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(
      {
        ENVIRONMENT    = var.environment
        S3_BUCKET_NAME = aws_s3_bucket.assets.id
        DATABASE_URL   = "postgresql+asyncpg://postgres:${var.db_password}@${var.db_endpoint}/${var.db_name}"
        SQS_QUEUE_URL  = aws_sqs_queue.app_queue.url
      },
      var.gemini_api_key != "" ? { GOOGLE_API_KEY = var.gemini_api_key } : {}
    )
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_function" "worker" {
  function_name = "${var.app_name}-worker-${var.environment}"
  role          = aws_iam_role.lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.app.repository_url}:latest"

  timeout       = 300
  memory_size   = 512
  architectures = ["arm64"]

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = merge(
      {
        ENVIRONMENT    = var.environment
        S3_BUCKET_NAME = aws_s3_bucket.assets.id
        DATABASE_URL   = "postgresql+asyncpg://postgres:${var.db_password}@${var.db_endpoint}/${var.db_name}"
        SQS_QUEUE_URL  = aws_sqs_queue.app_queue.url
      },
      var.gemini_api_key != "" ? { GOOGLE_API_KEY = var.gemini_api_key } : {}
    )
  }

  lifecycle {
    ignore_changes = [image_uri]
  }
}

resource "aws_lambda_event_source_mapping" "worker_sqs" {
  event_source_arn = aws_sqs_queue.app_queue.arn
  function_name    = aws_lambda_function.worker.arn
  batch_size       = 1
}

# Security group for Lambda
resource "aws_security_group" "lambda" {
  name   = "${var.app_name}-lambda-sg-${var.environment}"
  vpc_id = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# 6. API Gateway
resource "aws_api_gateway_rest_api" "main" {
  name = "${var.app_name}-api-${var.environment}"
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.app.invoke_arn
}

resource "aws_api_gateway_deployment" "main" {
  depends_on  = [aws_api_gateway_integration.lambda]
  rest_api_id = aws_api_gateway_rest_api.main.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.environment
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.app.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_lambda_function_url" "app" {
  count              = var.use_function_url ? 1 : 0
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = true
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    max_age           = 86400
  }
}

resource "aws_lambda_permission" "function_url" {
  count                  = var.use_function_url ? 1 : 0
  statement_id           = "AllowFunctionUrlPublicAccess-${var.app_name}"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# 7. AWS Amplify
resource "aws_amplify_app" "app" {
  name         = "${var.app_name}-frontend"
  repository   = "https://github.com/${var.github_repo}"
  access_token = var.github_access_token

  platform = var.platform

  build_spec = var.platform == "WEB_COMPUTE" ? local.build_spec_compute : local.build_spec_static

  environment_variables = {
    NEXT_PUBLIC_API_URL       = var.use_function_url ? one(aws_lambda_function_url.app[*].function_url) : aws_api_gateway_stage.prod.invoke_url
    AMPLIFY_MONOREPO_APP_ROOT = "frontend"
    AMPLIFY_DIFF_DEPLOY       = "false"
  }
}

resource "aws_amplify_branch" "main" {

  app_id      = aws_amplify_app.app.id
  branch_name = "main"
  stage       = "PRODUCTION"
}

output "api_endpoint" {
  value = aws_api_gateway_stage.prod.invoke_url
}

output "api_function_url" {
  value = var.use_function_url ? one(aws_lambda_function_url.app[*].function_url) : ""
}

output "lambda_sg_id" {
  value = aws_security_group.lambda.id
}

output "amplify_app_id" {
  value = aws_amplify_app.app.id
}

output "amplify_default_domain" {
  value = "main.${aws_amplify_app.app.default_domain}"
}
