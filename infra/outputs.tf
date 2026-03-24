output "s3_bucket_name" {
  description = "S3 bucket name for media storage"
  value       = aws_s3_bucket.media.id
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain name (use as CDN base URL)"
  value       = aws_cloudfront_distribution.media.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.media.id
}

output "lambda_presign_url" {
  description = "Lambda function URL for presigned upload requests"
  value       = aws_lambda_function_url.presign.function_url
}
