################################################################################
# Stable Public Address and DNS
################################################################################

resource "aws_eip" "public_dashboard" {
  count = var.public_dashboard_enabled ? 1 : 0

  domain = "vpc"
  tags   = local.common_tags
}

resource "aws_route53_record" "public_dashboard" {
  count = var.public_dashboard_enabled ? 1 : 0

  zone_id = var.public_dashboard_route53_zone_id
  name    = local.public_dashboard_domain
  type    = "A"
  ttl     = 300
  records = [aws_eip.public_dashboard[0].public_ip]
}
