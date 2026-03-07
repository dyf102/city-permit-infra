# 1. Automate SSL Validation for CloudFront
resource "cloudflare_record" "acm_validation" {
  count = 1

  zone_id         = var.cloudflare_zone_id
  name            = replace(element(tolist(aws_acm_certificate.toronto.domain_validation_options), 0).resource_record_name, "/\\.$/", "")
  content         = element(tolist(aws_acm_certificate.toronto.domain_validation_options), 0).resource_record_value
  type            = element(tolist(aws_acm_certificate.toronto.domain_validation_options), 0).resource_record_type
  proxied         = false
  allow_overwrite = true
}

import {
  to = cloudflare_record.acm_validation[0]
  id = "0219c4ec09c49f40bcd19e518cd9e0ac/9273b338f9931db54d62ed2a06a7add5"
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

import {
  to = cloudflare_record.toronto_app
  id = "0219c4ec09c49f40bcd19e518cd9e0ac/e9dd24226d8cfdb646152605841f3750"
}
