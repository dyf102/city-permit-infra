output "vpc_id" {
  value = module.networking.vpc_id
}

output "db_endpoint" {
  value = module.database.db_endpoint
}

output "reviewer_api_endpoint" {
  value = module.reviewer.api_endpoint
}

output "check_api_endpoint" {
  value = module.check.api_endpoint
}

output "check_api_function_url" {
  value = module.check.api_function_url
}

output "reviewer_amplify_domain" {
  value = module.reviewer.amplify_default_domain
}

output "check_amplify_domain" {
  value = module.check.amplify_default_domain
}

output "bootstrap_lambda_name" {
  value = module.bootstrap_lambda.lambda_function_name
}

output "monitoring_dashboard_url" {
  value = "https://ca-central-1.console.aws.amazon.com/cloudwatch/home?region=ca-central-1#dashboards:name=CityPermit-Shared-prod"
}
