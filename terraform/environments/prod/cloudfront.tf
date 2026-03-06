resource "aws_cloudfront_distribution" "toronto" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Subpath routing for Toronto Permit Pulse"
  aliases         = ["toronto.${var.domain_name}"]

  # Origin 1: Reviewer App
  origin {
    # domain_name = module.reviewer.amplify_default_domain
    domain_name = "example.com"
    origin_id   = "ReviewerApp"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origin 2: Check App
  origin {
    # domain_name = module.check.amplify_default_domain
    domain_name = "example.org"
    origin_id   = "CheckApp"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ReviewerApp"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      # DO NOT forward Host header to Amplify
      headers = ["Origin", "Authorization", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Route /review* to Reviewer App
  ordered_cache_behavior {
    path_pattern     = "/review*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "ReviewerApp"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      # DO NOT forward Host header to Amplify
      headers = ["Origin", "Authorization", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  # Route /check* to Check App
  ordered_cache_behavior {
    path_pattern     = "/check*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "CheckApp"

    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
      # DO NOT forward Host header to Amplify
      headers = ["Origin", "Authorization", "Access-Control-Request-Headers", "Access-Control-Request-Method"]
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.toronto.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.toronto.domain_name
}
