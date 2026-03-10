output "lambda_function_name" {
  description = "The name of the ETL Lambda function"
  value       = aws_lambda_function.etl_lambda.function_name
}

output "lambda_arn" {
  description = "The ARN of the ETL Lambda function"
  value       = aws_lambda_function.etl_lambda.arn
}

output "ecr_repo_url" {
  description = "The ECR repository URL for the ETL Lambda image"
  value       = aws_ecr_repository.etl.repository_url
}

output "security_group_id" {
  description = "Security group ID of the ETL Lambda"
  value       = aws_security_group.etl_lambda_sg.id
}
