output "ec2_public_ip" {
  description = "Elastic IP of the EC2 instance"
  value       = aws_eip.app.public_ip
}

output "rds_endpoint" {
  description = "Connection endpoint for the RDS database"
  value       = aws_db_instance.db.endpoint
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket with EC2 read/write access"
  value       = aws_s3_bucket.app_data.bucket
}
