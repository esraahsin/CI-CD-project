
resource "aws_lb" "backend" {
  name               = "${local.name_prefix}-alb"
  internal           = false          # public, accessible depuis internet
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = values(aws_subnet.public)[*].id   # les 2 subnets publics

  enable_deletion_protection = false  # sandbox : on veut pouvoir détruire facilement

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb" })
}

resource "aws_lb_target_group" "backend" {
  name        = "${local.name_prefix}-tg"
  port        = var.backend_port   # 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    enabled             = true
    path                = "/health"       # votre route GET /health → 200 OK
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2               # 2 checks OK = sain
    unhealthy_threshold = 3               # 3 checks KO = défaillant
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-tg" })
}
resource "aws_lb_listener" "backend_http" {
  load_balancer_arn = aws_lb.backend.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB security group - accepts HTTP from internet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-alb-sg" })
}





resource "aws_security_group_rule" "backend_from_alb" {
  type                     = "ingress"
  from_port                = var.backend_port   # 3000
  to_port                  = var.backend_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id   
  security_group_id        = aws_security_group.backend.id
  description              = "Allow traffic only from ALB"
}

resource "aws_launch_template" "backend" {
  name_prefix   = "${local.name_prefix}-backend-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.backend_instance_type   # t3.micro

  # Profil IAM pour lire SSM
  iam_instance_profile {
    name = data.aws_iam_instance_profile.lab.name
  }

  # Security Group du backend (trafic depuis ALB uniquement)
  network_interfaces {
    associate_public_ip_address = false   # PRIVÉ : pas d'IP publique
    security_groups             = [aws_security_group.backend.id]
  }

  # Clé SSH pour débogage si nécessaire
  key_name = var.key_pair_name

  # User Data : même script que l'instance backend existante
  user_data = base64encode(templatefile("${path.module}/templates/backend-user-data.sh.tftpl", {
    aws_region             = var.aws_region
    repo_url               = var.app_repo_url
    repo_branch            = var.app_repo_branch
    backend_path           = var.backend_app_path
    backend_port           = var.backend_port
    use_json_storage       = var.use_json_storage
    use_ssm_parameters     = var.use_ssm_parameters
    ssm_parameter_path     = var.ssm_parameter_path
    db_host                = local.db_host_value
    db_user                = var.db_username
    db_name                = var.db_name
    db_password_secret_arn = var.db_password_secret_arn
  }))

  # Remplacer le template si la config change
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(local.tags, { Name = "${local.name_prefix}-backend-lt" })

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = "${local.name_prefix}-backend-asg-instance" })
  }
}

resource "aws_autoscaling_group" "backend" {
  name                = "${local.name_prefix}-asg"
  min_size            = 2     # minimum 2 instances toujours en vie
  desired_capacity    = 2     # état souhaité : 2 instances
  max_size            = 4     # peut monter jusqu'à 4 en cas de forte charge

  # Distribuer les instances sur les 2 subnets privés (AZ-A et AZ-B)
  vpc_zone_identifier = values(aws_subnet.private)[*].id

  # Lier l'ASG au Target Group de l'ALB
  target_group_arns = [aws_lb_target_group.backend.arn]

  # Utiliser le Launch Template défini ci-dessus
  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }

  # Santé : utiliser le health check de l'ALB (plus intelligent que EC2 seul)
  # Si l'ALB détecte qu'une instance ne répond plus sur /health → ASG la remplace
  health_check_type         = "ELB"
  health_check_grace_period = 300   # 5 min pour laisser l'app démarrer avant les checks

  force_delete = true

  # Tags propagés aux instances EC2 créées par l'ASG
  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-backend-asg"
    propagate_at_launch = true
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }

  depends_on = [aws_lb_listener.backend_http]
}
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "${local.name_prefix}-scale-out"
  autoscaling_group_name = aws_autoscaling_group.backend.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 70.0   # Si CPU > 70% → scale out
  }
}
output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.backend.dns_name
}

output "alb_url" {
  description = "Full URL of the ALB"
  value       = "http://${aws_lb.backend.dns_name}"
}

output "asg_name" {
  description = "Name of the Auto Scaling Group"
  value       = aws_autoscaling_group.backend.name
}
