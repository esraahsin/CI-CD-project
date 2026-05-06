variable "aws_region" {
  type        = string
  description = "AWS region for all resources."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Project name used for tagging and resource names."
  default     = "ci-cd-project"
}

variable "environment" {
  type        = string
  description = "Environment label used for tagging and resource names."
  default     = "dev"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC."
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for public subnets."
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "CIDR blocks for private subnets."
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "availability_zones" {
  type        = list(string)
  description = "Availability zones to use. Leave empty to auto-select."
  default     = []
}

variable "ssh_cidr" {
  type        = string
  description = "CIDR allowed to SSH to instances."
  default     = "127.0.0.1/32"
}

variable "http_cidr" {
  type        = string
  description = "CIDR allowed to access HTTP services."
  default     = "0.0.0.0/0"
}

variable "backend_instance_type" {
  type        = string
  description = "EC2 instance type for the backend server."
  default     = "t3.micro"
}

variable "frontend_instance_type" {
  type        = string
  description = "EC2 instance type for the frontend server."
  default     = "t3.micro"
}

variable "key_pair_name" {
  type        = string
  description = "Existing EC2 key pair name for SSH access."
}

variable "app_repo_url" {
  type        = string
  description = "Git repository URL containing the backend and frontend apps."
  default     = "https://github.com/esraahsin/CI-CD-project.git"
}

variable "app_repo_branch" {
  type        = string
  description = "Git branch to deploy."
  default     = "main"
}

variable "backend_app_path" {
  type        = string
  description = "Path to the backend app relative to the repo root."
  default     = "back/backend"
}

variable "frontend_app_path" {
  type        = string
  description = "Path to the frontend app relative to the repo root."
  default     = "front/client"
}

variable "backend_port" {
  type        = number
  description = "Port the backend listens on."
  default     = 3000
}

variable "use_json_storage" {
  type        = bool
  description = "When true, the backend uses JSON storage and skips provisioning RDS."
  default     = true
}

variable "db_engine" {
  type        = string
  description = "Database engine for RDS."
  default     = "mysql"
}

variable "db_engine_version" {
  type        = string
  description = "Database engine version for RDS."
  default     = "8.0"
}

variable "db_instance_class" {
  type        = string
  description = "RDS instance class."
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  type        = number
  description = "Allocated storage for RDS (GB)."
  default     = 20
}

variable "db_name" {
  type        = string
  description = "Database name."
  default     = "appdb"
}

variable "db_username" {
  type        = string
  description = "Database username."
  default     = "appuser"
}

variable "db_password" {
  type        = string
  description = "Database password (used when provisioning RDS)."
  default     = ""
  sensitive   = true

  validation {
    condition     = var.use_json_storage || var.db_password_secret_arn != "" || length(var.db_password) > 0
    error_message = "db_password is required when use_json_storage is false, unless db_password_secret_arn is provided."
  }
}

variable "db_host" {
  type        = string
  description = "Database host when using an external database."
  default     = ""
}

variable "db_port" {
  type        = number
  description = "Database port."
  default     = 3306
}

variable "db_backup_retention_period" {
  type        = number
  description = "Number of days to retain RDS backups."
  default     = 7
}

variable "db_skip_final_snapshot" {
  type        = bool
  description = "Whether to skip the final snapshot on RDS deletion."
  default     = false
}

variable "db_deletion_protection" {
  type        = bool
  description = "Whether deletion protection is enabled for the RDS instance."
  default     = true
}

variable "db_final_snapshot_identifier" {
  type        = string
  description = "Final snapshot identifier used when skip_final_snapshot is false."
  default     = ""
}

variable "db_publicly_accessible" {
  type        = bool
  description = "Whether the RDS instance is publicly accessible."
  default     = false
}

variable "use_ssm_parameters" {
  type        = bool
  description = "When true, read backend environment values from SSM parameters."
  default     = false
}

variable "ssm_parameter_path" {
  type        = string
  description = "SSM parameter path containing backend env values."
  default     = "/ci-cd-project/backend"
}

variable "db_password_secret_arn" {
  type        = string
  description = "Secrets Manager secret ARN for DB password. Required when use_json_storage is false and use_ssm_parameters is false."
  default     = ""
  sensitive   = true
}

variable "frontend_api_url" {
  type        = string
  description = "Optional override for the frontend API base URL."
  default     = ""
}

variable "frontend_build_output_path" {
  type        = string
  description = "Build output path for the frontend app."
  default     = "dist/client"
}
