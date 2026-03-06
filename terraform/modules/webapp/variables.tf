variable "app_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "db_endpoint" {
  type = string
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "db_name" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_access_token" {
  type      = string
  sensitive = true
}

variable "platform" {
  type    = string
  default = "WEB"
}

variable "gemini_api_key" {
  type      = string
  sensitive = true
  default   = ""
}

variable "use_function_url" {
  type    = bool
  default = false
}

variable "recaptcha_site_key" {
  type    = string
  default = ""
}

variable "recaptcha_secret_key" {
  type      = string
  sensitive = true
  default   = ""
}
