# Specify the provider and access details

provider "aws" {
  region = "${var.aws_region}"
}

## EC2

### Network

data "aws_availability_zones" "available" {}

resource "aws_vpc" "main_vpc" {
  cidr_block = "10.10.0.0/16"
}

resource "aws_subnet" "main_subnet" {
  count             = "${var.az_count}"
  cidr_block        = "${cidrsubnet(aws_vpc.main_vpc.cidr_block, 8, count.index)}"
  availability_zone = "${data.aws_availability_zones.available.names[count.index]}"
  vpc_id            = "${aws_vpc.main_vpc.id}"
}

resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.main_vpc.id}"
}

resource "aws_route_table" "rt" {
  vpc_id = "${aws_vpc.main_vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.igw.id}"
  }
}

resource "aws_route_table_association" "rt_assoc" {
  count          = "${var.az_count}"
  subnet_id      = "${element(aws_subnet.main_subnet.*.id, count.index)}"
  route_table_id = "${aws_route_table.rt.id}"
}

### Compute

resource "aws_instance" "waf_ec2" {
  ami           = "${var.ami_id}"
  instance_type = "${var.instance_type}"
  vpc_security_group_ids = ["${aws_security_group.ec2_sg.id}"]
  subnet_id = "${aws_subnet.main_subnet.1.id}"
  associate_public_ip_address = true 
  key_name = "${var.ssh_keyname}"

  tags {
    Name = "waf_ec2_target"
  }
}

### Security Groups

resource "aws_security_group" "lb_sg" {
  description = "controls access to the application ELB"
  vpc_id = "${aws_vpc.main_vpc.id}"
  name   = "lbsg"

  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"

    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_security_group" "ec2_sg" {
  description = "controls direct access to application instances"
  vpc_id      = "${aws_vpc.main_vpc.id}"
  name        = "instance_sg"

  ingress {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22

    cidr_blocks = [
      "${var.admin_cidr_ingress}",
    ]
  }

  ingress {
    protocol  = "tcp"
    from_port = 80
    to_port   = 80

    security_groups = [
      "${aws_security_group.lb_sg.id}",
    ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

## ALB
resource "aws_alb_target_group" "waf_alb_target" {
  name     = "regionalwafalb"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${aws_vpc.main_vpc.id}"
}

resource "aws_alb" "waf_alb" {
  name            = "wafalb"
  subnets         = ["${aws_subnet.main_subnet.*.id}"]
  security_groups = ["${aws_security_group.lb_sg.id}"]
}

resource "aws_alb_listener" "waf_alb_listener" {
  load_balancer_arn = "${aws_alb.waf_alb.id}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    target_group_arn = "${aws_alb_target_group.waf_alb_target.id}"
    type             = "forward"
  }
}

resource "aws_alb_target_group_attachment" "waf_attachment" {
  target_group_arn = "${aws_alb_target_group.waf_alb_target.arn}"
  target_id        = "${aws_instance.waf_ec2.id}"
  port             = 80
}



## WAF

resource "aws_wafregional_geo_match_set" "waf_neighbors" {
  name = "waf_geo_match_set"

  geo_match_constraint {
    type  = "Country"
    value = "CA"
  }

  geo_match_constraint {
    type  = "Country"
    value = "MX"
  }
}

resource "aws_wafregional_ipset" "waf_verizon" {
  name = "verizon_ipset"

  ip_set_descriptor {
    type = "IPV4"
    value = "71.179.0.0/16"
  }

  ip_set_descriptor {
    type  = "IPV4"
    value = "71.180.0.0/16"
  }
}


resource "aws_wafregional_rule" "waf_rule" {
  name = "wafrule"
  metric_name = "wafrulemetric"

  predicate {
    type    = "GeoMatch"
    data_id = "${aws_wafregional_geo_match_set.waf_neighbors.id}"
    negated = false
  }
}


resource "aws_wafregional_rule" "waf_rule_verizon" {
  name = "wafruleverizion"
  metric_name = "wafruleverizonmetric"

  predicate {
    type    = "IPMatch"
    data_id = "${aws_wafregional_ipset.waf_verizon.id}"
    negated = false
  }
}

resource "aws_wafregional_web_acl" "waf_acl" {
  name        = "waf_acl"
  metric_name = "wafaclmetric"

  default_action {
    type = "ALLOW"
  }

  rule {
    action {
       type = "COUNT"
    }

    priority = 1
    rule_id  = "${aws_wafregional_rule.waf_rule.id}"
    type     = "REGULAR"
  }


  rule {
    action {
       type = "COUNT"
    }

    priority = 2 
    rule_id  = "${aws_wafregional_rule.waf_rule_verizon.id}"
    type     = "REGULAR"
  }
}

resource "aws_wafregional_web_acl_association" "waf_association" {
  resource_arn = "${aws_alb.waf_alb.arn}"
  web_acl_id = "${aws_wafregional_web_acl.waf_acl.id}"
}

