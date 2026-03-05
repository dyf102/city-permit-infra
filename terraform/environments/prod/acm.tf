# SSL Certificate for CloudFront (Must be in us-east-1)
resource "aws_acm_certificate" "toronto" {
  provider          = aws.us_east_1
  domain_name       = "toronto.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

output "toronto_cert_validation_options" {
  value = aws_acm_certificate.toronto.domain_validation_options
}
