# ==========================================
# VARIABLES
# ==========================================

variable "app_user" {
  description = "Linux username created on the EC2 instance to run the app (e.g. 'appuser', 'deploy', 'nexus')"
  type        = string
  default     = "appuser"
}

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

variable "ssh_public_key_path" {
  description = "Path to your local public SSH key file (e.g. ~/.ssh/id_ed25519.pub)"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "neo4j_password" {
  description = "Initial password for the Neo4j default user ('neo4j')"
  type        = string
  default     = "neo4jpassword"
  sensitive   = true
}

# ------------------------------------------------------------------
# KAFKA CONTROLS
# ------------------------------------------------------------------

variable "install_kafka" {
  description = "Download and install Apache Kafka? Enter true to install, false to skip."
  type        = bool
  # No default — Terraform will ask you at apply time
}

variable "kafka_mode" {
  description = "Kafka mode to use: enter 'kraft' (modern, no Zookeeper) or 'zookeeper' (legacy). Only used when install_kafka = true."
  type        = string
  # No default — Terraform will ask you at apply time

  validation {
    condition     = contains(["kraft", "zookeeper"], var.kafka_mode)
    error_message = "kafka_mode must be either 'kraft' or 'zookeeper'."
  }
}

variable "process_manager" {
  description = "Process manager to run the 6 app processes: 'systemd' (recommended, built-in) or 'supervisord' (single config file)."
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
  description = "Set to true to install Nginx as a reverse proxy in front of the FastAPI gateway (port 80 → 8000). Recommended for production."
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Optional. Your domain name (e.g. api.example.com). If set, Certbot will automatically obtain a free Let's Encrypt TLS certificate. Leave empty to skip TLS (HTTP only)."
  type        = string
  default     = ""
}