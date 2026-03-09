output "lambda_function_name" {
  description = "The name of the ETL Lambda function"
  value       = aws_lambda_function.etl_lambda.function_name
}

output "lambda_arn" {
  description = "The ARN of the ETL Lambda function"
  value       = aws_lambda_function.etl_lambda.arn
}