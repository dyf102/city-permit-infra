terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = ">= 5.0"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

variable "environment" {
  type = string
}

variable "app_names" {
  type    = list(string)
  default = ["reviewer", "check"]
}

resource "aws_sns_topic" "alerts" {
  provider = aws.us_east_1
  name     = "city-permit-alerts-${var.environment}"
}

resource "aws_cloudwatch_metric_alarm" "billing" {
  provider            = aws.us_east_1
  alarm_name          = "billing-alarm-${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = "21600" # 6 hours
  statistic           = "Maximum"
  threshold           = "10" # $10 threshold
  alarm_description   = "Billing alarm for ${var.environment}"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}

resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "CityPermit-Shared-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = [
            for app in var.app_names : ["AWS/Lambda", "Errors", "FunctionName", "${app}-api-${var.environment}"]
          ]
          period = 300
          stat   = "Sum"
          region = "ca-central-1"
          title  = "Lambda Errors"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          metrics = concat(
            [for app in var.app_names : ["AWS/ApiGateway", "4XXError", "ApiName", "${app}-api-${var.environment}"]],
            [for app in var.app_names : ["AWS/ApiGateway", "5XXError", "ApiName", "${app}-api-${var.environment}"]]
          )
          period = 300
          stat   = "Sum"
          region = "ca-central-1"
          title  = "API Gateway Errors"
        }
      }
    ]
  })
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
