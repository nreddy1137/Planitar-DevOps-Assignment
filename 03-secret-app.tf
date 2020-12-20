provider "aws" {
  region = "us-east-1"
}


variable "bucket_name" {
    type        = string
    default     = "web-hosting-basic-auth"
    description = "The name of your s3 bucket"
}
variable "cloudfront_price_class" {
    type        = string
    default     = "PriceClass_All"
    description = "Cloudfront price classes: `PriceClass_All`, `PriceClass_200`, `PriceClass_100`"
}

variable "cloudfront_default_root_object" {
    type        = string
    default     = "index.html"
    description = "The default root object of the Cloudfront distribution"
}
variable "cloudfront_distribution" {
    type        = string
    default     = "web-hosting-basic-auth-dist"
    description = "The cloudfront distribtion"
}


resource "aws_s3_bucket" "web-hosting" {
  bucket = var.bucket_name 
  acl    = "private"
  
  website {
    index_document = "index.html"
    error_document = "index.html"
  }
  
  
  tags = {
    Name        = "My Web hosting bucket with Auth"
    Environment = "Dev"
  }
}

data "aws_iam_policy_document" "s3_bucket_policy" {
    statement {
        actions = [
            "s3:GetObject",
        ]

        resources = [
            "${aws_s3_bucket.web-hosting.arn}/*",
        ]

        principals {
            type        = "AWS"
            identifiers = [
                "${aws_cloudfront_origin_access_identity.default.iam_arn}",
            ]
        }
    }

    statement {
        actions = [
            "s3:ListBucket",
        ]

        resources = [
            "${aws_s3_bucket.web-hosting.arn}",
        ]

        principals {
            type        = "AWS"
            identifiers = [
                "${aws_cloudfront_origin_access_identity.default.iam_arn}",
            ]
        }
    }
}

resource "aws_s3_bucket_policy" "bucket_policy" {
  bucket = aws_s3_bucket.web-hosting.id
  policy = data.aws_iam_policy_document.s3_bucket_policy.json
}

resource "aws_s3_bucket_object" "upload_s3_index_html" {
  bucket = aws_s3_bucket.web-hosting.id
  key     = "index.html"
  content_type = "text/html"
	source = "${path.module}/index.html"

}
resource "aws_s3_bucket_object" "upload_s3_index_js" {
  bucket = aws_s3_bucket.web-hosting.id
  key     = "index.js"
content_type= "application/javascript"  
source = "${path.module}/index.js"

}
resource "aws_s3_bucket_object" "upload_s3_index_css" {
  bucket = aws_s3_bucket.web-hosting.id
  key     = "index.css"
  content_type = "text/css"
  source = "${path.module}/index.css"

}



#
# Lambda
#
# This function is created in us-east-1 as required by CloudFront.
resource "aws_lambda_function" "default" {
    description      = "Managed by Terraform"
    runtime          = "nodejs12.x"
    role             = aws_iam_role.lambda_role.arn
    filename         = "lambda_function_payload.zip"
    function_name    = "cloudfront_auth"
    handler          = "index.handler"
    publish          = true
    timeout          = 5
    source_code_hash = filebase64sha256("lambda_function_payload.zip")
}

data "aws_iam_policy_document" "lambda_log_access" {
    // Allow lambda access to logging
    statement {
        actions = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        ]

        resources = [
            "arn:aws:logs:*:*:*",
        ]

        effect = "Allow"
    }
}
data "aws_iam_policy_document" "lambda_assume_role" {
    // Trust relationships taken from blueprint
    // Allow lambda to assume this role.
    statement {
        actions = [
            "sts:AssumeRole",
        ]

        principals {
            type        = "Service"
            identifiers = [
                "edgelambda.amazonaws.com",
                "lambda.amazonaws.com",
            ]
        }

        effect = "Allow"
    }
}
resource "aws_iam_role" "lambda_role" {
    name               = "lambda_cloudfront_role"
    assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# Attach the logging access document to the above role.
resource "aws_iam_role_policy_attachment" "lambda_log_access" {
    role       = aws_iam_role.lambda_role.name
    policy_arn = aws_iam_policy.lambda_log_access.arn
}

# Create an IAM policy that will be attached to the role
resource "aws_iam_policy" "lambda_log_access" {
    name   = "cloudfront_auth_lambda_log_access"
    policy = data.aws_iam_policy_document.lambda_log_access.json
}



#
# Cloudfront
#
resource "aws_cloudfront_origin_access_identity" "default" {
    comment = var.bucket_name
}

resource "aws_cloudfront_distribution" "default" {
    origin {
        domain_name = aws_s3_bucket.web-hosting.bucket_regional_domain_name
        origin_id   = "S3-${var.bucket_name}"

        s3_origin_config {
            origin_access_identity = aws_cloudfront_origin_access_identity.default.cloudfront_access_identity_path
        }
    }


    comment             = "Managed by Terraform"
    default_root_object = var.cloudfront_default_root_object
    enabled             = true
    http_version        = "http2"
    is_ipv6_enabled     = true
    price_class         = var.cloudfront_price_class

    default_cache_behavior {
        target_origin_id = "S3-${var.bucket_name}"

        // Read only
        allowed_methods = [
            "GET",
            "HEAD",
        ]

        cached_methods = [
            "GET",
            "HEAD",
        ]

        forwarded_values {
            query_string = false
            headers = [
                "Access-Control-Request-Headers",
                "Access-Control-Request-Method",
                "Origin"
            ]

            cookies {
                forward = "none"
            }
        }

        lambda_function_association {
            event_type = "viewer-request"
            lambda_arn = aws_lambda_function.default.qualified_arn
        }
        viewer_protocol_policy = "allow-all"

    }
    restrictions {
        geo_restriction {
            restriction_type = "none"
            locations = []
        }
    }
    viewer_certificate {
    cloudfront_default_certificate = true
  }

}

output "s3_bucket" {
    description = "The name of the S3 Bucket"
    value = "${aws_s3_bucket.web-hosting.id}"
}

output "cloudfront_arn" {
    description = "ARN of the Cloudfront Distribution"
    value = "${aws_cloudfront_distribution.default.arn}"
}

output "cloudfront_id" {
    description = "ID of the Cloudfront Distribution"
    value = "${aws_cloudfront_distribution.default.id}"
}