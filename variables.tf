# ==========================================
# VARIABLES
# ==========================================

# ------------------------------------------------------------------
# AWS
# ------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy in (e.g. us-east-1, ap-south-1)"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type (e.g. t3.medium, t3.large)"
  type        = string
  default     = "t3.medium"
}

# ------------------------------------------------------------------
# VPC NETWORK
# ------------------------------------------------------------------

variable "vpc_cidr" {
  description = "CIDR block for the custom VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

# ------------------------------------------------------------------
# APP USER
# ------------------------------------------------------------------

variable "app_user" {
  description = "Linux username created on the EC2 instance to run the app"
  type        = string
  default     = "appuser"
}

# ------------------------------------------------------------------
# OS & JAVA
# ------------------------------------------------------------------

variable "os_choice" {
  description = "Choose 'ubuntu' or 'amazon_linux'"
  type        = string
  default     = "ubuntu"

  validation {
    condition     = contains(["ubuntu", "amazon_linux"], var.os_choice)
    error_message = "os_choice must be either 'ubuntu' or 'amazon_linux'."
  }
}

variable "java_version" {
  description = "Choose '17' or '21'"
  type        = string
  default     = "21"

  validation {
    condition     = contains(["17", "21"], var.java_version)
    error_message = "java_version must be '17' or '21'."
  }
}

# ------------------------------------------------------------------
# POSTGRESQL
# ------------------------------------------------------------------

variable "db_name" {
  description = "The name of the PostgreSQL database"
  type        = string
  default     = "nexus_app"
}

variable "db_user" {
  description = "The PostgreSQL database user"
  type        = string
  default     = "nexus_user"
}

variable "db_password" {
  description = "The PostgreSQL database password"
  type        = string
  default     = "dbpassword"
  sensitive   = true
}

# ------------------------------------------------------------------
# NEO4J
# ------------------------------------------------------------------

variable "neo4j_password" {
  description = "Initial password for the Neo4j default user ('neo4j')"
  type        = string
  default     = "neo4jpassword"
  sensitive   = true
}

# ------------------------------------------------------------------
# KAFKA
# ------------------------------------------------------------------

variable "install_kafka" {
  description = "Download and install Apache Kafka? Enter true or false."
  type        = bool
  # No default - Terraform will ask at apply time
}

variable "kafka_mode" {
  description = "Kafka mode: enter 'kraft' (modern) or 'zookeeper' (legacy)"
  type        = string
  # No default - Terraform will ask at apply time

  validation {
    condition     = contains(["kraft", "zookeeper"], var.kafka_mode)
    error_message = "kafka_mode must be either 'kraft' or 'zookeeper'."
  }
}

# ------------------------------------------------------------------
# PROCESS MANAGER
# ------------------------------------------------------------------

variable "process_manager" {
  description = "Process manager: 'systemd' (recommended) or 'supervisord'"
  type        = string
  default     = "systemd"

  validation {
    condition     = contains(["systemd", "supervisord"], var.process_manager)
    error_message = "process_manager must be either 'systemd' or 'supervisord'."
  }
}

# ----------------------------------------------------------------
# REVERSE PROXY & TLS
# ----------------------------------------------------------------

variable "enable_nginx" {
  description = "Install Nginx as reverse proxy (port 80 to 8000)"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Enter your domain name for TLS (e.g. api.example.com). Leave empty and press Enter to skip TLS."
  type        = string
  # No default - Terraform will ask at apply time
}