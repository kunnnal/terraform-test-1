terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Change to your preferred region
}

# ==========================================
# DATA SOURCES
# ==========================================

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

# ==========================================
# SECURITY GROUP
# ==========================================

resource "aws_security_group" "nexus_sg" {
  name        = "nexus_server_sg"
  description = "Allow SSH, PostgreSQL, Kafka, Neo4j, HTTP, HTTPS"

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
}

# ==========================================
# SSH KEY PAIR
# ==========================================

resource "aws_key_pair" "nexus_key" {
  key_name   = "nexus-server-key"
  public_key = file(var.ssh_public_key_path)
}

# ==========================================
# EC2 INSTANCE & PROVISIONING
# ==========================================

resource "aws_instance" "nexus_server" {
  ami                    = var.os_choice == "ubuntu" ? data.aws_ami.ubuntu.id : data.aws_ami.amazon_linux.id
  instance_type          = "t3.medium"
  vpc_security_group_ids = [aws_security_group.nexus_sg.id]
  key_name               = aws_key_pair.nexus_key.key_name

  # Injecting variables into the bash template file
  user_data = templatefile("${path.module}/user-data.sh.tlp", {
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
}

# ==========================================
# OUTPUTS
# ==========================================

output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_instance.nexus_server.public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the EC2 instance"
  value       = aws_instance.nexus_server.private_ip
}

output "ssh_connection_command" {
  description = "Run this command to SSH into the instance"
  value       = "ssh -i ~/.ssh/id_ed25519 ubuntu@${aws_instance.nexus_server.public_ip}"
}

output "neo4j_http_url" {
  description = "Neo4j Browser (HTTP) — open in your browser to manage the graph database"
  value       = "http://${aws_instance.nexus_server.public_ip}:7474"
}

output "neo4j_bolt_url" {
  description = "Neo4j Bolt URL — use this in your application driver connection string"
  value       = "bolt://${aws_instance.nexus_server.public_ip}:7687"
}

output "kafka_mode_used" {
  description = "The Kafka coordination mode that was configured on this instance"
  value       = var.install_kafka ? var.kafka_mode : "kafka not installed"
}

output "kafka_bootstrap_servers" {
  description = "Kafka bootstrap server address to use in your app (NEXUS_KAFKA_BOOTSTRAP_SERVERS)"
  value       = var.install_kafka ? "${aws_instance.nexus_server.public_ip}:9092" : "kafka not installed"
}

output "kafka_topics_created" {
  description = "Kafka topics auto-created during provisioning"
  value       = var.install_kafka ? "ingestion.calendar, ingestion.email" : "N/A — kafka not installed"
}

output "process_manager_used" {
  description = "Process manager configured to run the 6 app processes"
  value       = var.process_manager
}

output "gateway_url" {
  description = "FastAPI gateway URL — use this to reach your app (via Nginx on port 80, or direct on 8000)"
  value       = var.enable_nginx ? "http://${aws_instance.nexus_server.public_ip}" : "http://${aws_instance.nexus_server.public_ip}:8000"
}

output "app_https_url" {
  description = "HTTPS URL for your app (only valid when domain_name is set and Certbot runs successfully)"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "No domain set — TLS not configured"
}

output "tls_status" {
  description = "TLS / Certbot configuration status"
  value       = var.domain_name != "" ? "Certbot will attempt cert for ${var.domain_name}" : "HTTP only — set domain_name variable to enable TLS"
}