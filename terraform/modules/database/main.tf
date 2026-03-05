variable "vpc_id" {
  type = string
}

variable "private_subnets" {
  type = list(string)
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "environment" {
  type = string
}

variable "lambda_sg_ids" {
  type        = list(string)
  description = "Security groups allowed to connect to RDS"
}

variable "bootstrap_sg_id" {
  type        = string
  description = "Security group for the bootstrap lambda"
  default     = ""
}

resource "aws_db_subnet_group" "main" {
  name       = "city-permit-db-subnet-${var.environment}"
  subnet_ids = var.private_subnets

  tags = {
    Name = "city-permit-db-subnet-${var.environment}"
  }
}

resource "aws_security_group" "db" {
  name        = "city-permit-db-sg-${var.environment}"
  description = "Allow inbound PostgreSQL from Lambda"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = concat(var.lambda_sg_ids, var.bootstrap_sg_id != "" ? [var.bootstrap_sg_id] : [])
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "city-permit-db-sg-${var.environment}"
  }
}

resource "aws_db_instance" "main" {
  identifier             = "city-permit-shared-db-${var.environment}"
  engine                 = "postgres"
  engine_version         = "16.6"
  instance_class         = "db.t4g.micro" # ARM64 free tier eligible
  allocated_storage      = 20
  storage_type           = "gp3"
  storage_encrypted      = true
  db_name                = "postgres"
  username               = "postgres"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 7
  skip_final_snapshot     = false
  publicly_accessible     = false
  multi_az                = false

  tags = {
    Name = "city-permit-shared-db-${var.environment}"
  }
}

output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

output "db_sg_id" {
  value = aws_security_group.db.id
}
