provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

data "aws_availability_zones" "available" {}
#IAM 

#S3_access

resource "aws_iam_instance_profile" "s3_access" {
    name = "s3_access"
    role = "${aws_iam_role.s3_access.name}"
}

resource "aws_iam_role_policy" "s3_access_policy" {
    name = "s3_access_policy"
    role = "${aws_iam_role.s3_access.id}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role" "s3_access" {
    name = "s3_access"
    assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
  {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
  },
      "Effect": "Allow",
      "Sid": ""
      }
    ]
}
EOF
}
#VPC

resource "aws_vpc" "vpc" {
  cidr_block = "10.1.0.0/16"
}

#internet gateway

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = "${aws_vpc.vpc.id}"
}

# Route tables

resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  route {
        cidr_block = "0.0.0.0/0"
	gateway_id = "${aws_internet_gateway.internet_gateway.id}"
	}
  tags = {
	Name = "public"
  }
}

resource "aws_default_route_table" "private" {
  default_route_table_id = "${aws_vpc.vpc.default_route_table_id}"
  tags = {
    Name = "private"
  }
}

resource "aws_subnet" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "${data.aws_availability_zones.available.names[2]}"

  tags = {
    Name = "public"
  }
}

resource "aws_subnet" "private1" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.2.0/24"
  map_public_ip_on_launch = false
  availability_zone = "${data.aws_availability_zones.available.names[0]}"

  tags = {
    Name = "private1"
  }
}


resource "aws_subnet" "private2" {
  vpc_id = "${aws_vpc.vpc.id}"
  cidr_block = "10.1.3.0/24"
  map_public_ip_on_launch = false
  availability_zone = "${data.aws_availability_zones.available.names[1]}"

  tags = {
    Name = "private2"
  }
}

#create S3 VPC endpoint
resource "aws_vpc_endpoint" "private-s3" {
    vpc_id = "${aws_vpc.vpc.id}"
    service_name = "com.amazonaws.${var.aws_region}.s3"
    route_table_ids = ["${aws_vpc.vpc.main_route_table_id}", "${aws_route_table.public.id}"]
    policy = <<POLICY
{
    "Statement": [
        {
            "Action": "*",
            "Effect": "Allow",
            "Resource": "*",
            "Principal": "*"
        }
    ]
}
POLICY
}
# Subnet Associations

resource "aws_route_table_association" "public_assoc" {
  subnet_id = "${aws_subnet.public.id}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "private1_assoc" {
  subnet_id = "${aws_subnet.private1.id}"
  route_table_id = "${aws_route_table.public.id}"
}


resource "aws_route_table_association" "private2_assoc" {
  subnet_id = "${aws_subnet.private2.id}"
  route_table_id = "${aws_route_table.public.id}"
}


#Security groups

resource "aws_security_group" "public" {
  name = "sg_public"
  description = "Used for public and private instances for load balancer access"
  vpc_id = "${aws_vpc.vpc.id}"

  #SSH 

  ingress {
    from_port 	= 22
    to_port 	= 22
    protocol 	= "tcp"
    cidr_blocks = ["${var.localip}"]
  }

  #HTTP 

  ingress {
    from_port 	= 80
    to_port 	= 80
    protocol 	= "tcp"
    cidr_blocks	= ["0.0.0.0/0"]
  }
  ingress {
    from_port 	= 80
    to_port 	= 8080
    protocol 	= "tcp"
    cidr_blocks	= ["0.0.0.0/0"]
  }
  ingress {
    from_port 	= 8080
    to_port 	= 8080
    protocol 	= "tcp"
    cidr_blocks	= ["0.0.0.0/0"]
  }

  #Outbound internet access

  egress {
    from_port	= 0
    to_port 	= 0
    protocol	= "-1"
    cidr_blocks	= ["0.0.0.0/0"]
  }
}

#Private Security Group

resource "aws_security_group" "private" {
  name        = "sg_private"
  description = "Used for private instances"
  vpc_id      = "${aws_vpc.vpc.id}"
  

# Access from other security groups

  ingress {
    from_port    = 0
    to_port      = 0
    protocol     = "-1"
    cidr_blocks  = ["10.1.0.0/16"]
  }

  egress {
    from_port    = 0
    to_port      = 0
    protocol     = "-1"
    cidr_blocks  = ["0.0.0.0/0"]
  }
}


#S3 code bucket

resource "aws_s3_bucket" "code" {
  bucket = "${var.domain_name}-code111523232323232"
  acl = "private"
  force_destroy = true
  tags = {
    Name = "code bucket"
  }
}



#key pair


resource "aws_key_pair" "auth" {
  key_name  ="${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}


#dev server

resource "aws_instance" "dev" {
  instance_type = "${var.dev_instance_type}"
  ami = "${var.dev_ami}"
  tags = {
    Name = "dev"
  }

  key_name = "${aws_key_pair.auth.id}"
  vpc_security_group_ids = ["${aws_security_group.public.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.s3_access.id}"
  subnet_id = "${aws_subnet.public.id}"
}

resource "aws_instance" "dev1" {
  instance_type = "${var.dev_instance_type}"
  ami = "${var.dev_ami}"
  tags = {
    Name = "dev1"
  }

  key_name = "${aws_key_pair.auth.id}"
  vpc_security_group_ids = ["${aws_security_group.public.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.s3_access.id}"
  subnet_id = "${aws_subnet.public.id}"


  provisioner "local-exec" {
    command = <<EOD
cat <<EOF > aws_hosts
[dev]
${aws_instance.dev.public_ip}
${aws_instance.dev1.public_ip}
[dev:vars]
s3code=${aws_s3_bucket.code.bucket}
EOF
EOD
  }

  provisioner "local-exec" {
    command = "sleep 6m && ansible-playbook -i aws_hosts site.yml"
  }
}



#load balancer

resource "aws_elb" "prod" {
  name = "${var.domain_name}-prod-elb"
  subnets = ["${aws_subnet.private1.id}", "${aws_subnet.private2.id}"]
  security_groups = ["${aws_security_group.public.id}"]
  listener {
    instance_port = 8080
    instance_protocol = "http"
    lb_port = 80
    lb_protocol = "http"
  }

  health_check {
    healthy_threshold = "${var.elb_healthy_threshold}"
    unhealthy_threshold = "${var.elb_unhealthy_threshold}"
    timeout = "${var.elb_timeout}"
    target = "HTTP:80/"
    interval = "${var.elb_interval}"
  }
  instances = ["${aws_instance.dev.id}","${aws_instance.dev1.id}"]
  cross_zone_load_balancing = true
  idle_timeout = 400
  connection_draining = true
  connection_draining_timeout = 400

  tags = {
    Name = "${var.domain_name}-prod-elb"
  }
}




#AMI 

resource "random_id" "ami" {
  byte_length = 8
}

resource "aws_ami_from_instance" "golden" {
    name = "ami-${random_id.ami.b64}"
    source_instance_id = "${aws_instance.dev.id}"
    provisioner "local-exec" {
      command = <<EOT
cat <<EOF > userdata
#!/bin/bash
/usr/bin/aws s3 sync s3://${aws_s3_bucket.code.bucket} /var/www/html/
/bin/touch /var/spool/cron/root
sudo /bin/echo '*/5 * * * * aws s3 sync s3://${aws_s3_bucket.code.bucket} /var/www/html/' >> /var/spool/cron/root
EOF
EOT
  }
}


#launch configuration

resource "aws_launch_configuration" "lc" {
  name_prefix = "lc-"
  image_id = "${aws_ami_from_instance.golden.id}"
  instance_type = "${var.lc_instance_type}"
  security_groups = ["${aws_security_group.private.id}"]
  iam_instance_profile = "${aws_iam_instance_profile.s3_access.id}"
  key_name = "${aws_key_pair.auth.id}"
  user_data = "${file("userdata")}"
  lifecycle {
    create_before_destroy = true
  }
}

#ASG 

resource "random_id" "asg" {
 byte_length = 8
}


resource "aws_autoscaling_group" "asg" {
  availability_zones = ["${data.aws_availability_zones.available.names[0]}", "${data.aws_availability_zones.available.names[1]}"]
  name = "asg-${aws_launch_configuration.lc.id}" 
  max_size = "${var.asg_max}"
  min_size = "${var.asg_min}"
  health_check_grace_period = "${var.asg_grace}"
  health_check_type = "${var.asg_hct}"
  desired_capacity = "${var.asg_cap}"
  force_delete = true
  load_balancers = ["${aws_elb.prod.id}"]
 // vpc_zone_identifier = ["${aws_subnet.private1.id}", "${aws_subnet.private2.id}"]
  launch_configuration = "${aws_launch_configuration.lc.name}"
    
  tag {
    key = "Name"
    value = "asg-instance"
    propagate_at_launch = true
    }

  lifecycle {
    create_before_destroy = true
  }
}

#Route53

#primary zone

resource "aws_route53_zone" "primary" {
  name = "${var.domain_name}.com"
  delegation_set_id = "${var.delegation_set}"
}




#www 

resource "aws_route53_record" "www" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "www.${var.domain_name}.com"
  type = "A"

  alias {
    name = "${aws_elb.prod.dns_name}"
    zone_id = "${aws_elb.prod.zone_id}"
    evaluate_target_health = false
  }
}

#dev 

resource "aws_route53_record" "dev" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "dev.${var.domain_name}.com"
  type = "A"
  ttl = "300"
  records = ["${aws_instance.dev.public_ip}"]
}
resource "aws_route53_record" "dev1" {
  zone_id = "${aws_route53_zone.primary.zone_id}"
  name = "dev1.${var.domain_name}.com"
  type = "A"
  ttl = "300"
  records = ["${aws_instance.dev1.public_ip}"]
}




























