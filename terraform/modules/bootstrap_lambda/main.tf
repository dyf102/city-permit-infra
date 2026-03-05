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

variable "environment" {
  type = string
}

resource "aws_iam_role" "bootstrap" {
  name = "db-bootstrap-role-${var.environment}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "basic" {
  role       = aws_iam_role.bootstrap.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# I'll create the index.py file separately
resource "local_file" "bootstrap_handler" {
  content  = <<-EOT
import pg8000.native
import os

def handler(event, context):
    host = os.environ['DB_HOST'].split(':')[0]
    password = os.environ['DB_PASSWORD']
    db_list = ['reviewer_prod', 'check_prod']
    
    try:
        # pg8000 uses a different syntax
        conn = pg8000.native.Connection(user='postgres', host=host, password=password, database='postgres')
        
        results = []
        for db in db_list:
            try:
                # Need to be careful with CREATE DATABASE in transactions
                # pg8000.native doesn't easily support autocommit off for specific commands
                # We'll use a new connection for each to be safe
                conn.run(f"CREATE DATABASE {db}")
                results.append(f"Created {db}")
            except Exception as e:
                results.append(f"Skipped {db}: {str(e)}")
            
            # Connect to each to enable extensions
            db_conn = pg8000.native.Connection(user='postgres', host=host, password=password, database=db)
            db_conn.run("CREATE EXTENSION IF NOT EXISTS postgis")
            db_conn.run("CREATE EXTENSION IF NOT EXISTS vector")
            db_conn.close()
            results.append(f"Enabled extensions in {db}")
            
        conn.close()
        return {"status": "success", "results": results}
    except Exception as e:
        return {"status": "error", "message": str(e)}
EOT
  filename = "${path.module}/index.py"
}

resource "null_resource" "build_bootstrap_zip" {
  provisioner "local-exec" {
    command = <<-EOT
      mkdir -p ${path.module}/package
      python3 -m pip install pg8000 -t ${path.module}/package
      cp ${path.module}/index.py ${path.module}/package/
      cd ${path.module}/package && zip -r ../bootstrap.zip .
    EOT
  }

  depends_on = [local_file.bootstrap_handler]

  # Re-run if handler changes
  triggers = {
    handler_hash = local_file.bootstrap_handler.content_sha256
  }
}

resource "aws_lambda_function" "bootstrap" {
  function_name = "db-bootstrap-${var.environment}"
  role          = aws_iam_role.bootstrap.arn
  handler       = "index.handler"
  runtime       = "python3.11"
  filename      = "${path.module}/bootstrap.zip"
  timeout       = 60

  vpc_config {
    subnet_ids         = var.private_subnets
    security_group_ids = [aws_security_group.bootstrap.id]
  }

  environment {
    variables = {
      DB_HOST     = var.db_endpoint
      DB_PASSWORD = var.db_password
    }
  }

  depends_on = [null_resource.build_bootstrap_zip]
}

resource "aws_security_group" "bootstrap" {
  name   = "db-bootstrap-sg-${var.environment}"
  vpc_id = var.vpc_id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

output "lambda_function_name" {
  value = aws_lambda_function.bootstrap.function_name
}

output "security_group_id" {
  value = aws_security_group.bootstrap.id
}
