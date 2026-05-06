locals {
  name_prefix        = "${var.project_name}-${var.environment}"
  subnet_count       = max(length(var.public_subnet_cidrs), length(var.private_subnet_cidrs))
  availability_zones = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, local.subnet_count)
  public_subnet_map  = { for idx, cidr in var.public_subnet_cidrs : idx => cidr }
  private_subnet_map = { for idx, cidr in var.private_subnet_cidrs : idx => cidr }
  enable_rds         = !var.use_json_storage
  db_host_value      = local.enable_rds ? aws_db_instance.main[0].address : var.db_host
  db_password_value  = var.db_password_secret_arn != "" ? data.aws_secretsmanager_secret_version.db_password[0].secret_string : var.db_password
  final_snapshot_identifier = var.db_final_snapshot_identifier != "" ? var.db_final_snapshot_identifier : "${local.name_prefix}-final"
  backend_api_url    = var.frontend_api_url != "" ? var.frontend_api_url : "http://${aws_instance.backend.public_dns}"
  ssm_parameter_arn  = "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter_path}*"
  tags = {
    Project     = var.project_name
    Environment = var.environment
  }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_secretsmanager_secret_version" "db_password" {
  count     = var.db_password_secret_arn != "" ? 1 : 0
  secret_id = var.db_password_secret_arn
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  for_each                = local.public_subnet_map
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = local.availability_zones[tonumber(each.key)]
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name = "${local.name_prefix}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each                = local.private_subnet_map
  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = local.availability_zones[tonumber(each.key)]
  map_public_ip_on_launch = false
  tags = merge(local.tags, {
    Name = "${local.name_prefix}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name_prefix}-nat-eip" })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id
  tags          = merge(local.tags, { Name = "${local.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-public-rt" })

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.tags, { Name = "${local.name_prefix}-private-rt" })

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "backend" {
  name        = "${local.name_prefix}-backend-sg"
  description = "Backend instance security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_cidr]
  }

  ingress {
    description = "App port"
    from_port   = var.backend_port
    to_port     = var.backend_port
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-backend-sg" })
}

resource "aws_security_group" "frontend" {
  name        = "${local.name_prefix}-frontend-sg"
  description = "Frontend instance security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.http_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-frontend-sg" })
}

resource "aws_security_group" "rds" {
  count       = local.enable_rds ? 1 : 0
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from backend"
    from_port       = var.db_port
    to_port         = var.db_port
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-rds-sg" })
}

resource "aws_db_subnet_group" "main" {
  count      = local.enable_rds ? 1 : 0
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = values(aws_subnet.private)[*].id
  tags       = merge(local.tags, { Name = "${local.name_prefix}-db-subnets" })
}

resource "aws_db_instance" "main" {
  count                     = local.enable_rds ? 1 : 0
  identifier                = "${local.name_prefix}-db"
  engine                    = var.db_engine
  engine_version            = var.db_engine_version
  instance_class            = var.db_instance_class
  allocated_storage         = var.db_allocated_storage
  db_name                   = var.db_name
  username                  = var.db_username
  password                  = local.db_password_value
  port                      = var.db_port
  db_subnet_group_name      = aws_db_subnet_group.main[0].name
  vpc_security_group_ids    = [aws_security_group.rds[0].id]
  skip_final_snapshot       = var.db_skip_final_snapshot
  final_snapshot_identifier = var.db_skip_final_snapshot ? null : local.final_snapshot_identifier
  deletion_protection       = var.db_deletion_protection
  publicly_accessible       = var.db_publicly_accessible
  backup_retention_period   = var.db_backup_retention_period
  apply_immediately         = true
  auto_minor_version_upgrade = true
  tags                      = merge(local.tags, { Name = "${local.name_prefix}-db" })
}

resource "aws_iam_role" "ec2" {
  name = "${local.name_prefix}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "ec2_access" {
  dynamic "statement" {
    for_each = var.use_ssm_parameters ? [1] : []
    content {
      actions = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      resources = [local.ssm_parameter_arn]
    }
  }

  dynamic "statement" {
    for_each = var.db_password_secret_arn != "" ? [1] : []
    content {
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [var.db_password_secret_arn]
    }
  }
}

resource "aws_iam_policy" "ec2_access" {
  name   = "${local.name_prefix}-ec2-access"
  policy = data.aws_iam_policy_document.ec2_access.json
  tags   = local.tags
}

resource "aws_iam_role_policy_attachment" "ec2_access" {
  role       = aws_iam_role.ec2.name
  policy_arn = aws_iam_policy.ec2_access.arn
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
  tags = local.tags
}

resource "aws_instance" "backend" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.backend_instance_type
  subnet_id                   = values(aws_subnet.public)[0].id
  vpc_security_group_ids      = [aws_security_group.backend.id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data                   = templatefile("${path.module}/templates/backend-user-data.sh.tftpl", {
    aws_region           = var.aws_region
    repo_url             = var.app_repo_url
    repo_branch          = var.app_repo_branch
    backend_path         = var.backend_app_path
    backend_port         = var.backend_port
    use_json_storage     = var.use_json_storage
    use_ssm_parameters   = var.use_ssm_parameters
    ssm_parameter_path   = var.ssm_parameter_path
    db_host              = local.db_host_value
    db_user              = var.db_username
    db_name              = var.db_name
    db_password_secret_arn = var.db_password_secret_arn
  })
  user_data_replace_on_change = true
  lifecycle {
    precondition {
      condition     = var.use_json_storage || var.use_ssm_parameters || var.db_password_secret_arn != ""
      error_message = "Set use_ssm_parameters or db_password_secret_arn when use_json_storage is false to avoid plaintext DB passwords."
    }
  }
  tags                        = merge(local.tags, { Name = "${local.name_prefix}-backend" })
}

resource "aws_instance" "frontend" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.frontend_instance_type
  subnet_id                   = values(aws_subnet.public)[0].id
  vpc_security_group_ids      = [aws_security_group.frontend.id]
  key_name                    = var.key_pair_name
  iam_instance_profile        = aws_iam_instance_profile.ec2.name
  user_data                   = templatefile("${path.module}/templates/frontend-user-data.sh.tftpl", {
    aws_region     = var.aws_region
    repo_url       = var.app_repo_url
    repo_branch    = var.app_repo_branch
    frontend_path  = var.frontend_app_path
    backend_api_url          = local.backend_api_url
    frontend_build_output_path = var.frontend_build_output_path
  })
  user_data_replace_on_change = true
  tags                        = merge(local.tags, { Name = "${local.name_prefix}-frontend" })
}
