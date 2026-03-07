module "networking" {
  source      = "../../modules/networking"
  environment = var.environment
}

module "reviewer" {
  source              = "../../modules/webapp"
  app_name            = "city-permit-reviewer"
  environment         = var.environment
  vpc_id              = module.networking.vpc_id
  private_subnets     = module.networking.private_subnets
  db_endpoint         = module.database.db_endpoint
  db_password         = var.db_password
  db_name             = "reviewer_prod"
  domain_name         = var.domain_name
  github_repo         = var.github_repo_reviewer
  github_access_token = var.github_access_token
  platform            = "WEB" # SSR was problematic, switching to static
  app_base_path       = "/explore"
  cors_origins        = ["https://permit-pulse.ca", "https://www.permit-pulse.ca", "https://toronto.permit-pulse.ca"]
}

module "check" {
  source              = "../../modules/webapp"
  app_name            = "city-permit-check"
  environment         = var.environment
  vpc_id              = module.networking.vpc_id
  private_subnets     = module.networking.private_subnets
  db_endpoint         = module.database.db_endpoint
  db_password         = var.db_password
  db_name             = "check_prod"
  domain_name         = var.domain_name
  github_repo         = var.github_repo_check
  github_access_token = var.github_access_token
  platform            = "WEB"
  gemini_api_key      = var.gemini_api_key
  use_function_url    = true
  app_base_path       = "/track"
  cors_origins        = ["https://permit-pulse.ca", "https://www.permit-pulse.ca", "https://toronto.permit-pulse.ca"]
}



module "bootstrap_lambda" {
  source          = "../../modules/bootstrap_lambda"
  environment     = var.environment
  vpc_id          = module.networking.vpc_id
  private_subnets = module.networking.private_subnets
  db_endpoint     = module.database.db_endpoint
  db_password     = var.db_password
}

module "database" {
  source          = "../../modules/database"
  vpc_id          = module.networking.vpc_id
  private_subnets = module.networking.private_subnets
  db_password     = var.db_password
  environment     = var.environment
  lambda_sg_ids   = [module.reviewer.lambda_sg_id, module.check.lambda_sg_id]
  bootstrap_sg_id = module.bootstrap_lambda.security_group_id
}

module "monitoring" {
  source      = "../../modules/monitoring"
  environment = var.environment
  app_names   = ["city-permit-reviewer", "city-permit-check"]

  providers = {
    aws.us_east_1 = aws.us_east_1
  }
}

# SSM Parameters for secrets (saves cost over Secrets Manager)
resource "aws_ssm_parameter" "gemini_key" {
  name  = "/city-permit/${var.environment}/gemini-api-key"
  type  = "SecureString"
  value = var.gemini_api_key
}

resource "aws_ssm_parameter" "stripe_key" {
  name  = "/city-permit/${var.environment}/stripe-secret-key"
  type  = "SecureString"
  value = var.stripe_secret_key
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/city-permit/${var.environment}/jwt-secret-key"
  type  = "SecureString"
  value = var.secret_key
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/city-permit/${var.environment}/db-password"
  type  = "SecureString"
  value = var.db_password
}
# Triggering deployment after secret update
# Job-level env vars enabled
# Cloudflare IP restriction fix pending
# Cloudflare IP restriction removed - Final deployment trigger
