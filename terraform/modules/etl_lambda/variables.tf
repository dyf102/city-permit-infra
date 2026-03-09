variable "environment" {
  description = "The deployment environment (e.g., prod, dev)"
  type        = string
}

variable "vpc_id" {
  description = "The VPC ID for the Lambda function"
  type        = string
}

variable "private_subnets" {
  description = "A list of private subnet IDs for the Lambda function"
  type        = list(string)
}

variable "db_endpoint" {
  description = "The database endpoint"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "The database password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "The database name"
  type        = string
}

variable "s3_bucket_name" {
  description = "The name of the S3 bucket for assets"
  type        = string
}
