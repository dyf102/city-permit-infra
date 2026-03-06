variable "aws_region" {
  type        = string
  description = "AWS region for all resources"
  default     = "ca-central-1"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "prod"
}

variable "db_password" {
  type        = string
  description = "Password for the shared RDS PostgreSQL instance"
  sensitive   = true
}

variable "domain_name" {
  type        = string
  description = "Base domain name (e.g., permitpulse.ca)"
  default     = "permitpulse.ca"
}

variable "github_repo_reviewer" {
  type        = string
  description = "GitHub repository for city-permit-reviewer"
}

variable "github_repo_check" {
  type        = string
  description = "GitHub repository for city-permit-check"
}

variable "github_access_token" {
  type        = string
  description = "GitHub PAT for Amplify"
  sensitive   = true
}

variable "gemini_api_key" {
  type        = string
  description = "Gemini API Key"
  sensitive   = true
}

variable "recaptcha_site_key" {
  type        = string
  description = "reCAPTCHA Site Key"
  default     = ""
}

variable "recaptcha_secret_key" {
  type        = string
  description = "reCAPTCHA Secret Key"
  sensitive   = true
  default     = ""
}

variable "stripe_secret_key" {
  type        = string
  description = "Stripe Secret Key"
  sensitive   = true
}

variable "secret_key" {
  type        = string
  description = "JWT Secret Key"
  sensitive   = true
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API Token"
  sensitive   = true
}

variable "cloudflare_zone_id" {
  type        = string
  description = "Cloudflare Zone ID for permitpulse.ca"
}
