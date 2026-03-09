# Dedicated IAM role for Terraform CI/CD (GitHub Actions)
# Scoped to the infra repo only — separate from the app deploy role.
#
# BOOTSTRAP: Apply this file manually once before the workflow can run:
#   cd terraform/environments/prod
#   terraform apply -var-file=terraform.tfvars -target=aws_iam_role.github_actions_terraform -target=aws_iam_role_policy.terraform_policy

resource "aws_iam_role" "github_actions_terraform" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:dyf102/city-permit-infra:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "terraform_policy" {
  name = "github-actions-terraform-policy"
  role = aws_iam_role.github_actions_terraform.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Terraform state access
      {
        Sid    = "TerraformStateS3"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          "arn:aws:s3:::city-permit-tfstate-110428898775",
          "arn:aws:s3:::city-permit-tfstate-110428898775/*"
        ]
      },
      {
        Sid    = "TerraformStateLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem"
        ]
        Resource = "arn:aws:dynamodb:ca-central-1:110428898775:table/city-permit-tf-locks"
      },
      # Managed infrastructure — all services Terraform controls
      {
        Sid      = "ManageNetworking"
        Effect   = "Allow"
        Action   = ["ec2:*"]
        Resource = "*"
      },
      {
        Sid      = "ManageDatabase"
        Effect   = "Allow"
        Action   = ["rds:*"]
        Resource = "*"
      },
      {
        Sid    = "ManageCompute"
        Effect = "Allow"
        Action = [
          "lambda:*",
          "ecr:*"
        ]
        Resource = "*"
      },
      {
        Sid      = "ManageAPIGateway"
        Effect   = "Allow"
        Action   = ["apigateway:*"]
        Resource = "*"
      },
      {
        Sid    = "ManageCDN"
        Effect = "Allow"
        Action = [
          "cloudfront:*",
          "acm:*"
        ]
        Resource = "*"
      },
      {
        Sid      = "ManageIAM"
        Effect   = "Allow"
        Action   = ["iam:*"]
        Resource = "*"
      },
      {
        Sid      = "ManageMessaging"
        Effect   = "Allow"
        Action   = ["sqs:*", "sns:*"]
        Resource = "*"
      },
      {
        Sid      = "ManageStorage"
        Effect   = "Allow"
        Action   = ["s3:*"]
        Resource = "*"
      },
      {
        Sid      = "ManageConfig"
        Effect   = "Allow"
        Action   = ["ssm:*"]
        Resource = "*"
      },
      {
        Sid    = "ManageMonitoring"
        Effect = "Allow"
        Action = [
          "cloudwatch:*",
          "logs:*",
          "events:*"
        ]
        Resource = "*"
      },
      {
        Sid      = "ManageAmplify"
        Effect   = "Allow"
        Action   = ["amplify:*"]
        Resource = "*"
      },
      {
        Sid      = "CallerIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

output "github_actions_terraform_role_arn" {
  value = aws_iam_role.github_actions_terraform.arn
}
