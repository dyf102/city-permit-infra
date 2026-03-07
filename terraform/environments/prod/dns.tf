# 1. Automate SSL Validation for CloudFront
resource "cloudflare_record" "acm_validation" {
  count = 1

  zone_id         = var.cloudflare_zone_id
  name            = element(tolist(aws_acm_certificate.toronto.domain_validation_options), 0).resource_record_name
  content         = element(tolist(aws_acm_certificate.toronto.domain_validation_options), 0).resource_record_value
  type            = element(tolist(aws_acm_certificate.toronto.domain_validation_options), 0).resource_record_type
  proxied         = false
  allow_overwrite = true
}

# 2. Final Routing to CloudFront (Subpath router)
resource "cloudflare_record" "toronto_app" {
  zone_id         = var.cloudflare_zone_id
  name            = "toronto"
  content         = aws_cloudfront_distribution.toronto.domain_name
  type            = "CNAME"
  proxied         = true
  allow_overwrite = true
}
