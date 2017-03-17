variable "aws_conf" {
  type = "map"
  default = {}
}

variable "vpc_conf" {
  type = "map"
  default = {}
}

resource "random_shuffle" "vpn_az" {
  input = ["${split(",", var.vpc_conf["availability_zones"])}"]
  result_count = 1
  keepers = {
    vpc_id = "${var.vpc_conf["id"]}"
  }
}

data "aws_subnet" "vpn_az" {
  vpc_id = "${var.vpc_conf["id"]}"
  availability_zone = "${random_shuffle.vpn_az.result.0}"
  tags {
    Type = "public"
  }
}

data "aws_ami" "vpn-ami" {
  most_recent = true
  name_regex = "ubuntu-xenial-16.04-amd64-server"
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
  filter {
    name = "architecture"
    values = ["x86_64"]
  }
  filter {
    name = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_eip" "vpn" {
  vpc = true
}

resource "aws_ebs_volume" "vpn" {
  availability_zone = "${random_shuffle.vpn_az.result.0}"
  type = "gp2"
  size = 10
  encrypted = true
  kms_key_id = "${aws_kms_key.ebs.arn}"

  tags {
    Name = "${var.aws_conf["domain"]}-vpn"
    Stack = "${var.aws_conf["domain"]}"
    clusterid = "${var.aws_conf["domain"]}"
    host-type = "vpn"
    svc = "vpn"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes = ["*"]
  }
}

data "template_file" "vpn-cloudinit" {
  template = "${file("${path.module}/cloudinit.yml")}"

  vars {
    aws_region = "${var.vpc_conf["region"]}"
    dns_zone_id = "${var.vpc_conf["zone_id"]}"
    cluster_id = "${var.aws_conf["domain"]}"
    eip = "${aws_eip.vpn.id}"
  }
}

resource "aws_launch_configuration" "vpn" {
  name_prefix = "${var.aws_conf["domain"]}-vpn-"
  image_id = "${data.aws_ami.vpn-ami.id}"
  instance_type = "${var.aws_conf["instance_type"]}"
  key_name = "${var.aws_conf["key_name"]}"
  iam_instance_profile = "${aws_iam_instance_profile.node-profile.id}"
  security_groups = [
    "${var.vpc_conf["security_group"]}",
    "${aws_security_group.vpn.id}"
  ]
  root_block_device {
    volume_type = "gp2"
    volume_size = 20
    delete_on_termination = false
  }
  user_data = "${data.template_file.vpn-cloudinit.rendered}"
  associate_public_ip_address = true

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "vpn" {
  name = "${var.aws_conf["domain"]}-vpn"
  launch_configuration = "${aws_launch_configuration.vpn.name}"
  vpc_zone_identifier = ["${data.aws_subnet.vpn_az.id}"]
  min_size = 1
  max_size = 1
  desired_capacity = 1
  wait_for_capacity_timeout = 0

  tag {
    key = "Name"
    value = "${var.aws_conf["domain"]}-vpn"
    propagate_at_launch = true
  }
  tag {
    key = "Stack"
    value = "${var.aws_conf["domain"]}"
    propagate_at_launch = true
  }
  tag {
    key = "clusterid"
    value = "${var.aws_conf["domain"]}"
    propagate_at_launch = true
  }
  tag {
    key = "host-type"
    value = "vpn"
    propagate_at_launch = true
  }
  tag {
    key = "svc"
    value = "vpn"
    propagate_at_launch = true
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "vpn" {
  name = "${var.aws_conf["domain"]}-vpn"
  vpc_id = "${var.vpc_conf["id"]}"

  ingress {
    from_port = 0
    to_port = 0
    protocol = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    /*security_groups = ["${var.vpc_conf["security_group"]}"]*/
  }

  ingress {
    from_port = 22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "${var.aws_conf["domain"]}-vpn"
    Stack = "${var.aws_conf["domain"]}"
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "vpn" {
  zone_id = "${var.vpc_conf["zone_id"]}"
  name = "vpn.${var.aws_conf["domain"]}"
  ttl = 60
  type = "A"
  records = ["${aws_eip.vpn.public_ip}"]

  lifecycle {
    create_before_destroy = true
  }
}
