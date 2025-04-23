###############################################################################
# Providers & locals
###############################################################################

provider "aws" {
  region = var.aws_region
}

provider "random" {}

locals {
  name_prefix = "${var.project_name}-aws"
}

###############################################################################
# Default VPC & its subnets
###############################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

###############################################################################
# IAM role for EC2 with S3 read/write
###############################################################################

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${local.name_prefix}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_trust.json
}


resource "random_pet" "bucket_suffix" { length = 2 }

resource "aws_s3_bucket" "app_data" {
  bucket        = "${local.name_prefix}-${random_pet.bucket_suffix.id}"
  force_destroy = true
}

data "aws_iam_policy_document" "s3_rw" {
  statement {
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.app_data.arn,
      "${aws_s3_bucket.app_data.arn}/*"
    ]
  }
}

resource "aws_iam_role_policy" "s3_rw" {
  name   = "${local.name_prefix}-s3-rw"
  role   = aws_iam_role.ec2_role.id
  policy = data.aws_iam_policy_document.s3_rw.json
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${local.name_prefix}-profile"
  role = aws_iam_role.ec2_role.name
}

###############################################################################
# Security groups
###############################################################################

resource "aws_security_group" "ec2_sg" {
  name   = "${local.name_prefix}-ec2-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
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
}

resource "aws_security_group" "rds_sg" {
  name   = "${local.name_prefix}-rds-sg"
  vpc_id = data.aws_vpc.default.id

  ingress {
    description     = "DB from EC2"
    from_port       = var.db_engine == "mysql" ? 3306 : 5432
    to_port         = var.db_engine == "mysql" ? 3306 : 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

###############################################################################
# EC2 instance (+ static Elastic IP)
###############################################################################

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-minimal-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
  }

  tags = { Name = "${local.name_prefix}-ec2" }
}

resource "aws_eip" "app" {
  instance = aws_instance.app.id
  domain   = "vpc"
}

###############################################################################
# Additional 20 GiB gp3 data volume
###############################################################################

resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.app.availability_zone
  size              = 20
  type              = "gp3"
  encrypted         = true
  tags              = { Name = "${local.name_prefix}-data-vol" }
}

resource "aws_volume_attachment" "data" {
  device_name = "/dev/xvdf"
  volume_id   = aws_ebs_volume.data.id
  instance_id = aws_instance.app.id
}

###############################################################################
# RDS (db.t3.micro)
###############################################################################

resource "aws_db_subnet_group" "default" {
  name       = "${local.name_prefix}-db-subnets"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_db_instance" "db" {
  identifier             = "${local.name_prefix}-db"
  engine                 = var.db_engine
  engine_version         = var.db_engine == "mysql" ? "8.0" : "15.3"
  instance_class         = "db.t3.micro"
  username               = "admin"
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  allocated_storage      = 20
  max_allocated_storage  = 100
  skip_final_snapshot    = true
}
