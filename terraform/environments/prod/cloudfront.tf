resource "aws_cloudfront_distribution" "toronto" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "Subpath routing for Toronto Permit Pulse"
  aliases         = ["toronto.${var.domain_name}"]

  # Origin 1: Reviewer App
  origin {
    domain_name = module.reviewer.amplify_default_domain
    origin_id   = "ReviewerApp"
    origin_path = "/explore"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Origin 2: Check App
  origin {
    domain_name = module.check.amplify_default_domain
    origin_id   = "CheckApp"
    origin_path = "/track"

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

  # Route /explore* to Reviewer App
  ordered_cache_behavior {
    path_pattern     = "/explore*"
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

  # Route /track* to Check App
  ordered_cache_behavior {
    path_pattern     = "/track*"
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
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.toronto.domain_name
}
