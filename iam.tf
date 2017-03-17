resource "aws_iam_role" "node-role" {
  name = "${var.aws_conf["domain"]}-vpn-role"
  assume_role_policy = "${file("${path.module}/policies/default-role.json")}"
}

resource "aws_iam_role_policy" "node-default-policy" {
  name = "${var.aws_conf["domain"]}-vpn-default-policy"
  policy = "${file("${path.module}/policies/default-policy.json")}"
  role = "${aws_iam_role.node-role.id}"
}

resource "aws_iam_role_policy" "node-eip-policy" {
  name = "${var.aws_conf["domain"]}-vpn-eip-policy"
  policy = "${file("${path.module}/policies/ec2-eip-policy.json")}"
  role = "${aws_iam_role.node-role.id}"
}

data "template_file" "node-ebs-policy" {
  template = "${file("${path.module}/policies/ec2-ebs-policy.json")}"

  vars {
    region = "${var.vpc_conf["region"]}"
    account = "${var.aws_conf["account_id"]}"
    vpc = "${var.vpc_conf["id"]}"
  }
}

resource "aws_iam_role_policy" "node-ebs-policy" {
  name = "${var.aws_conf["domain"]}-vpn-ebs-policy"
  policy = "${data.template_file.node-ebs-policy.rendered}"
  role = "${aws_iam_role.node-role.id}"
}

resource "aws_iam_instance_profile" "node-profile" {
  name = "${var.aws_conf["domain"]}-vpn-profile"
  path = "/"
  roles = ["${aws_iam_role.node-role.name}"]

  lifecycle {
    create_before_destroy = true
  }
}

data "template_file" "route53_policy" {
  template = "${file("${path.module}/policies/route53-policy.json")}"

  vars {
    zone_id = "${var.vpc_conf["zone_id"]}"
  }
}

resource "aws_iam_role_policy" "route53" {
  name = "${var.aws_conf["domain"]}-vpn-route53-policy"
  policy = "${data.template_file.route53_policy.rendered}"
  role = "${aws_iam_role.node-role.name}"
}

resource "aws_kms_key" "ebs" {
  description = "${var.aws_conf["domain"]} VPN EBS Key"
}

data "template_file" "role-kms" {
  template = "${file("${path.module}/policies/role-kms-policy.json")}"

  vars {
    aws_region = "${var.aws_conf["region"]}"
    aws_account_id = "${var.aws_conf["account_id"]}"
    ebs_kms_arn = "${aws_kms_key.ebs.arn}"
  }
}

resource "aws_iam_role_policy" "role-kms-policy" {
  name = "${var.aws_conf["domain"]}-vpn-kms-policy"
  policy = "${data.template_file.role-kms.rendered}"
  role = "${aws_iam_role.node-role.id}"
}
