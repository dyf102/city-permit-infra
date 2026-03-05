variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "environment" {
  type = string
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "city-permit-vpc-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "city-permit-igw-${var.environment}"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "city-permit-public-${count.index}-${var.environment}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "city-permit-private-${count.index}-${var.environment}"
  }
}

# Cost Saving: NAT Instance (t4g.nano) instead of NAT Gateway
resource "aws_instance" "nat" {
  ami                         = "ami-0721f6dd4e8f38143" # Amazon Linux 2 (ARM64) in ca-central-1
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public[0].id
  associate_public_ip_address = true
  source_dest_check           = false # Required for NAT
  vpc_security_group_ids      = [aws_security_group.nat.id]
  
  # Persistent NAT setup
  user_data = <<-EOT
    #!/bin/bash
    yum install -y iptables-services
    systemctl enable iptables
    systemctl start iptables
    
    echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/custom-ip-forward.conf
    sysctl -p /etc/sysctl.d/custom-ip-forward.conf
    
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    service iptables save
  EOT

  tags = {
    Name = "city-permit-nat-instance-${var.environment}"
  }
}

resource "aws_security_group" "nat" {
  name        = "city-permit-nat-sg-${var.environment}"
  description = "Security group for NAT instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "city-permit-nat-sg-${var.environment}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "city-permit-public-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_instance.nat.primary_network_interface_id
  }

  tags = {
    Name = "city-permit-private-rt-${var.environment}"
  }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# 🔒 Private Access to SSM (Prevents timeouts in private subnets)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.ca-central-1.ssm"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoints.id]

  tags = {
    Name = "city-permit-ssm-endpoint-${var.environment}"
  }
}

resource "aws_security_group" "vpc_endpoints" {
  name        = "city-permit-vpce-sg-${var.environment}"
  vpc_id      = aws_vpc.main.id
  description = "Allow inbound from VPC for endpoints"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = {
    Name = "city-permit-vpce-sg-${var.environment}"
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}
