# Get latest Linux 2 ECS-optimized AMI by Amazon
data "aws_ami" "latest_ecs_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["amazon"]
}

resource "aws_security_group" "instance" {
  name        = "${var.name_prefix}_ecs_${var.instance_group}"
  description = "Used in ${var.name_prefix}"
  vpc_id      = var.vpc_id

  tags = {
    Environment   = var.name_prefix
    Cluster       = "${var.name_prefix}-ecs-cluster"
    InstanceGroup = var.instance_group
  }
}

# We separate the rules from the aws_security_group because then we can manipulate the 
# aws_security_group outside of this module
resource "aws_security_group_rule" "outbound_internet_access" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.instance.id
}

# Default disk size for Docker is 22 gig, see http://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs-optimized_AMI.html
resource "aws_launch_configuration" "launch" {
  name_prefix          = "${var.name_prefix}_ecs_${var.instance_group}_"
  image_id             = var.aws_ami != "" ? var.aws_ami : data.aws_ami.latest_ecs_ami.image_id
  instance_type        = var.instance_type
  security_groups      = ["${aws_security_group.instance.id}"]
  user_data            = local.user_data
  iam_instance_profile = aws_iam_instance_profile.ecs.id
  key_name             = var.key_name

  lifecycle {
    create_before_destroy = true
  }
}

# Instances are scaled across availability zones http://docs.aws.amazon.com/autoscaling/latest/userguide/auto-scaling-benefits.html 
resource "aws_autoscaling_group" "asg" {
  name                 = "${var.name_prefix}_ecs_${var.instance_group}"
  max_size             = var.max_size
  min_size             = var.min_size
  desired_capacity     = var.desired_capacity
  force_delete         = true
  launch_configuration = aws_launch_configuration.launch.id
  vpc_zone_identifier  = var.private_subnet_ids
  load_balancers       = var.load_balancers

  tag {
    key                 = "Name"
    value               = "${var.name_prefix}_ecs_${var.instance_group}"
    propagate_at_launch = "true"
  }

  tag {
    key                 = "Environment"
    value               = var.name_prefix
    propagate_at_launch = "true"
  }

  tag {
    key                 = "Cluster"
    value               = "${var.name_prefix}-ecs-cluster"
    propagate_at_launch = "true"
  }

  tag {
    key                 = "InstanceGroup"
    value               = var.instance_group
    propagate_at_launch = "true"
  }
}

# data "template_file" "user_data" {
#   template = "${file("${path.module}/templates/user_data.sh")}"

#   vars = {
#     ecs_config        = var.ecs_config
#     ecs_logging       = var.ecs_logging
#     cluster_name      = "${var.name_prefix}-ecs-cluster"
#     env_name          = var.name_prefix
#     custom_userdata   = var.custom_userdata
#     cloudwatch_prefix = var.cloudwatch_prefix
#   }
# }

locals {
  user_data = templatefile("${path.module}/templates/user_data.sh", {
    ecs_config        = var.ecs_config
    ecs_logging       = var.ecs_logging
    cluster_name      = "${var.name_prefix}-ecs-cluster"
    env_name          = var.name_prefix
    custom_userdata   = var.custom_userdata
    cloudwatch_prefix = var.cloudwatch_prefix
  })
}