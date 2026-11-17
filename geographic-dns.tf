resource "aws_route53_record" "east_geo" {
  zone_id        = var.hosted_zone_id
  name           = "dlc-linux-lb.dialloholmes.net"
  type           = "A"
  set_identifier = "us-east"

  geoproximity_routing_policy {
    aws_region = "us-east-1"
    bias       = 0
  }

  alias {
    name                   = aws_lb.east.dns_name
    zone_id                = aws_lb.east.zone_id
    evaluate_target_health = true
  }

  depends_on = [aws_route53_record.web]
}
