terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ===========================================
# AMI Data Sources
# ===========================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# ===========================================
# SSH Key Pair (auto-generated, no local key needed)
# ===========================================

# Generate RSA key pair inside Terraform
resource "tls_private_key" "nexus_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Register the public key in AWS
resource "aws_key_pair" "nexus_key" {
  key_name   = "nexus-server-key"
  public_key = tls_private_key.nexus_key.public_key_openssh
}

# Save the private key to ~/.ssh/ (proper permissions, works with SSH directly)
resource "local_file" "nexus_pem" {
  filename        = "${pathexpand("~")}/.ssh/nexus-key.pem"
  content         = tls_private_key.nexus_key.private_key_pem
  file_permission = "0400"
}

# ===========================================
# VPC
# ===========================================

resource "aws_vpc" "nexus_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "nexus-vpc"
  }
}

# ===========================================
# Public Subnet
# ===========================================

resource "aws_subnet" "nexus_public_subnet" {
  vpc_id                  = aws_vpc.nexus_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "nexus-public-subnet"
  }
}

# ===========================================
# Internet Gateway
# ===========================================

resource "aws_internet_gateway" "nexus_igw" {
  vpc_id = aws_vpc.nexus_vpc.id

  tags = {
    Name = "nexus-igw"
  }
}

# ===========================================
# Route Table (all traffic goes to IGW)
# ===========================================

resource "aws_route_table" "nexus_rt" {
  vpc_id = aws_vpc.nexus_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.nexus_igw.id
  }

  tags = {
    Name = "nexus-public-rt"
  }
}

# Associate subnet with route table
resource "aws_route_table_association" "nexus_rta" {
  subnet_id      = aws_subnet.nexus_public_subnet.id
  route_table_id = aws_route_table.nexus_rt.id
}

# ===========================================
# Security Group (inside our VPC)
# ===========================================

resource "aws_security_group" "nexus_sg" {
  name        = "nexus_server_sg"
  description = "Allow SSH, PostgreSQL, Kafka, Neo4j, HTTP, HTTPS"
  vpc_id      = aws_vpc.nexus_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP Nginx proxy"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS TLS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "FastAPI direct dev access"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kafka"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Neo4j HTTP (Browser)"
    from_port   = 7474
    to_port     = 7474
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Neo4j Bolt (Driver)"
    from_port   = 7687
    to_port     = 7687
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nexus-sg"
  }
}

# ===========================================
# EC2 Instance
# ===========================================

resource "aws_instance" "nexus_server" {
  ami                         = var.os_choice == "ubuntu" ? data.aws_ami.ubuntu.id : data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.nexus_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.nexus_sg.id]
  key_name                    = aws_key_pair.nexus_key.key_name
  associate_public_ip_address = true

  # Injecting variables into the bash template file
  user_data = templatefile("${path.module}/user-data.sh.tlp", {
    app_user        = var.app_user
    os_choice       = var.os_choice
    java_version    = var.java_version
    db_name         = var.db_name
    db_user         = var.db_user
    db_password     = var.db_password
    neo4j_password  = var.neo4j_password
    install_kafka   = var.install_kafka
    kafka_mode      = var.kafka_mode
    process_manager = var.process_manager
    enable_nginx    = var.enable_nginx
    domain_name     = var.domain_name
  })

  tags = {
    Name = "Nexus-App-Server"
  }

  depends_on = [
    aws_internet_gateway.nexus_igw,
    local_file.nexus_pem
  ]
}

# ===========================================
# OUTPUTS
# ===========================================

# --- SSH ---
output "ssh_private_key_file" {
  description = "Auto-generated SSH private key location"
  value       = "~/.ssh/nexus-key.pem"
}

output "ssh_connection_command" {
  description = "Run this to SSH into the instance"
  value       = "ssh -i ~/.ssh/nexus-key.pem ${var.os_choice == "ubuntu" ? "ubuntu" : "ec2-user"}@${aws_instance.nexus_server.public_ip}"
}

# --- Network ---
output "vpc_id" {
  description = "ID of the custom VPC"
  value       = aws_vpc.nexus_vpc.id
}

output "subnet_id" {
  description = "ID of the public subnet"
  value       = aws_subnet.nexus_public_subnet.id
}

# --- Instance ---
output "instance_public_ip" {
  description = "Public IP of the EC2 instance"
  value       = aws_instance.nexus_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP of the EC2 instance (within VPC)"
  value       = aws_instance.nexus_server.private_ip
}

# --- Services ---
output "neo4j_http_url" {
  description = "Neo4j Browser URL"
  value       = "http://${aws_instance.nexus_server.public_ip}:7474"
}

output "neo4j_bolt_url" {
  description = "Neo4j Bolt connection URL"
  value       = "bolt://${aws_instance.nexus_server.public_ip}:7687"
}

output "kafka_mode_used" {
  description = "Kafka coordination mode configured"
  value       = var.install_kafka ? var.kafka_mode : "kafka not installed"
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap server address"
  value       = var.install_kafka ? "${aws_instance.nexus_server.public_ip}:9092" : "kafka not installed"
}

output "kafka_topics_created" {
  description = "Kafka topics auto-created during provisioning"
  value       = var.install_kafka ? "ingestion.calendar, ingestion.email" : "N/A - kafka not installed"
}

output "process_manager_used" {
  description = "Process manager configured for the 6 app processes"
  value       = var.process_manager
}

output "gateway_url" {
  description = "FastAPI gateway URL"
  value       = var.enable_nginx ? "http://${aws_instance.nexus_server.public_ip}" : "http://${aws_instance.nexus_server.public_ip}:8000"
}

output "app_https_url" {
  description = "HTTPS URL (only if domain_name is set)"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "No domain set - TLS not configured"
}

output "tls_status" {
  description = "TLS / Certbot status"
  value       = var.domain_name != "" ? "Certbot will attempt cert for ${var.domain_name}" : "HTTP only - set domain_name to enable TLS"
}