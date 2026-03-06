# 1. Automate SSL Validation for CloudFront
resource "cloudflare_record" "acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.toronto.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = var.cloudflare_zone_id
  name    = each.value.name
  value   = each.value.record
  type    = each.value.type
  proxied = false
}

# 2. Final Routing to CloudFront (Subpath router)
resource "cloudflare_record" "toronto_app" {
  zone_id = var.cloudflare_zone_id
  name    = "toronto"
  value   = aws_cloudfront_distribution.toronto.domain_name
  type    = "CNAME"
  proxied = true
}
