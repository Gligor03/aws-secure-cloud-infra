data "aws_ami" "amazon_linux_2" {
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"] # Amazon Linux 2023
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  owners = ["137112412989"] # Amazon
}

data "aws_caller_identity" "current" {}

########################
# Networking - VPC
########################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "demo-vpc"
    Env  = "dev"
  }
}

########################
# Public subnet
########################

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "demo-public-subnet"
    Env  = "dev"
  }
}

########################
# Private subnet
########################

resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  map_public_ip_on_launch = false

  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "demo-private-subnet"
    Env  = "dev"
  }
}

########################
# Internet Gateway
########################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "demo-igw"
    Env  = "dev"
  }
}

########################
# Route tables
########################

# Public route table: route 0.0.0.0/0 to Internet Gateway
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "demo-public-rt"
    Env  = "dev"
  }
}

# Private route table: no direct internet route (local only)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "demo-private-rt"
    Env  = "dev"
  }
}

########################
# Route table associations
########################

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

########################
# Security group for bastion
########################

resource "aws_security_group" "bastion_sg" {
  name        = "demo-bastion-sg"
  description = "Allow SSH from my IP only"
  vpc_id      = aws_vpc.main.id

  # Ingress: SSH from your IP (we'll insert the CIDR shortly)
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # Egress: allow all outbound (common pattern; we can tighten later)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "demo-bastion-sg"
    Env  = "dev"
  }
}

########################
# EC2 bastion/test instance
########################

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true
  key_name                    = var.key_name
iam_instance_profile = aws_iam_instance_profile.ec2_s3_instance_profile.name

  tags = {
    Name = "demo-bastion"
    Env  = "dev"
  }
}

########################
# S3 - secure bucket
########################

resource "aws_s3_bucket" "app_bucket" {
  bucket = "${var.project_name}-secure-bucket-${random_id.bucket_suffix.hex}"

  force_destroy = false

  tags = {
    Name = "${var.project_name}-app-bucket"
    Env  = "dev"
  }
}

# Random suffix to make bucket name globally unique
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "app_bucket_block" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption by default (SSE-S3)
resource "aws_s3_bucket_server_side_encryption_configuration" "app_bucket_sse" {
  bucket = aws_s3_bucket.app_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Optional: enable versioning
resource "aws_s3_bucket_versioning" "app_bucket_versioning" {
  bucket = aws_s3_bucket.app_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

########################
# CloudTrail - trail
########################

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_bucket.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]  # keep simple; logs management events anyway
    }
  }

  depends_on = [
    aws_s3_bucket_public_access_block.cloudtrail_block,
    aws_s3_bucket_server_side_encryption_configuration.cloudtrail_sse,
    aws_s3_bucket_policy.cloudtrail_bucket_policy
  ]
}

##############################
# CloudTrail - bucket policy
##############################

resource "aws_s3_bucket_policy" "cloudtrail_bucket_policy" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_bucket.arn
      }
    ]
  })
}

########################
# CloudTrail - log bucket
########################

resource "aws_s3_bucket" "cloudtrail_bucket" {
  bucket = "${var.project_name}-cloudtrail-logs-${random_id.cloudtrail_suffix.hex}"

  force_destroy = false

  tags = {
    Name = "${var.project_name}-cloudtrail-logs"
    Env  = "dev"
  }
}

resource "random_id" "cloudtrail_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_block" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_sse" {
  bucket = aws_s3_bucket.cloudtrail_bucket.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

########################
# IAM role for EC2 -> S3
########################

resource "aws_iam_role" "ec2_s3_role" {
  name = "${var.project_name}-ec2-s3-role"

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

  tags = {
    Name = "${var.project_name}-ec2-s3-role"
    Env  = "dev"
  }
}

# Least-privilege policy: allow EC2 role to access this specific bucket
resource "aws_iam_policy" "ec2_s3_policy" {
  name        = "${var.project_name}-ec2-s3-policy"
  description = "Least-privilege access for EC2 to S3 app bucket"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app_bucket.arn
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.app_bucket.arn}/*"
        ]
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "ec2_s3_attach" {
  role       = aws_iam_role.ec2_s3_role.name
  policy_arn = aws_iam_policy.ec2_s3_policy.arn
}

# Instance profile so EC2 can use the role
resource "aws_iam_instance_profile" "ec2_s3_instance_profile" {
  name = "${var.project_name}-ec2-s3-instance-profile"
  role = aws_iam_role.ec2_s3_role.name
}

########################
# CloudWatch - EC2 status check alarm
########################

resource "aws_cloudwatch_metric_alarm" "bastion_status_check_failed" {
  alarm_name          = "${var.project_name}-bastion-status-check-failed"
  alarm_description   = "Alert when bastion EC2 instance fails status checks"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1

  dimensions = {
    InstanceId = aws_instance.bastion.id
  }

  treat_missing_data = "notBreaching"

  # For now, no actions (no SNS). We'll just see alarm state changes in console.
  alarm_actions = []
  ok_actions    = []
}

########################
# CloudWatch - EC2 CPU high alarm
########################

resource "aws_cloudwatch_metric_alarm" "bastion_cpu_high" {
  alarm_name          = "${var.project_name}-bastion-cpu-high"
  alarm_description   = "Alert when bastion EC2 instance CPU is high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300            # 5 minutes
  statistic           = "Average"
  threshold           = 80             # 80% CPU
  unit                = "Percent"

  dimensions = {
    InstanceId = aws_instance.bastion.id
  }

  treat_missing_data = "notBreaching"

  alarm_actions = []
  ok_actions    = []
}

########################
# CloudWatch - EC2 NetworkOut high alarm
########################

resource "aws_cloudwatch_metric_alarm" "bastion_network_out_high" {
  alarm_name          = "${var.project_name}-bastion-network-out-high"
  alarm_description   = "Alert when bastion EC2 instance has high outbound network traffic"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "NetworkOut"
  namespace           = "AWS/EC2"
  period              = 300           # 5 minutes
  statistic           = "Sum"
  threshold           = 104857600     # 100 MB in 5 minutes
  unit                = "Bytes"

  dimensions = {
    InstanceId = aws_instance.bastion.id
  }

  treat_missing_data = "notBreaching"

  alarm_actions = []
  ok_actions    = []
}