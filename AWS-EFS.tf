provider "aws" {
    region = "ap-south-1"
    profile = "raktim"
}

data "aws_vpc" "default_vpc" {
    default = true
}

data "aws_subnet_ids" "default_subnet" {
  vpc_id = data.aws_vpc.default_vpc.id
}

// Creating RSA key

variable "EC2_Key" {default="httpdserverkey"}
resource "tls_private_key" "httpdkey" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

// Creating AWS key-pair

resource "aws_key_pair" "generated_key" {
  key_name   = var.EC2_Key
  public_key = tls_private_key.httpdkey.public_key_openssh
}

// Creating security group for Instance

resource "aws_security_group" "httpd_security" {

depends_on = [
    aws_key_pair.generated_key,
  ]

  name         = "httpd-security"
  description  = "allow ssh and httpd"
  vpc_id       = data.aws_vpc.default_vpc.id
 
  ingress {
    description = "SSH Port"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTPD Port"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  } 

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "httpdsecurity"
  }
}

// Creating Security group for EFS

resource "aws_security_group" "efs_sg" {
  depends_on = [
    aws_security_group.httpd_security,
  ]
  name        = "httpd-efs-sg"
  description = "Security group for efs storage"
  vpc_id      = data.aws_vpc.default_vpc.id
 

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.httpd_security.id]
  }
}

// Creating EFS cluster
	
resource "aws_efs_file_system" "httpd_efs" {
  depends_on = [
    aws_security_group.efs_sg
  ]
  creation_token = "efs"
  tags = {
    Name = "httpdstorage"
  }
}

resource "aws_efs_mount_target" "efs_mount" {
  depends_on = [
    aws_efs_file_system.httpd_efs
  ]
  for_each        = data.aws_subnet_ids.default_subnet.ids
  file_system_id  = aws_efs_file_system.httpd_efs.id
  subnet_id       = each.value
  security_groups = ["${aws_security_group.efs_sg.id}"]
}

// Creating S3 bucket.

resource "aws_s3_bucket" "httpds3" {
bucket = "raktim-httpd-files"
acl    = "public-read"
}

//Putting Objects in S3 Bucket

resource "aws_s3_bucket_object" "s3_object" {
  bucket = aws_s3_bucket.httpds3.bucket
  key    = "Raktim.JPG"
  source = "C:/Users/rakti/OneDrive/Desktop/Raktim.JPG"
  acl    = "public-read"
}

// Creating Cloud Front Distribution.

locals {
s3_origin_id = aws_s3_bucket.httpds3.id
}

resource "aws_cloudfront_distribution" "CloudFrontAccess" {

depends_on = [
    aws_s3_bucket_object.s3_object,
  ]

origin {
domain_name = aws_s3_bucket.httpds3.bucket_regional_domain_name
origin_id   = local.s3_origin_id
}

enabled             = true
is_ipv6_enabled     = true
comment             = "s3bucket-access"

default_cache_behavior {
allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
viewer_protocol_policy = "allow-all"
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
}
# Cache behavior with precedence 0
ordered_cache_behavior {
path_pattern     = "/content/immutable/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD", "OPTIONS"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
headers      = ["Origin"]
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 86400
max_ttl                = 31536000
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
# Cache behavior with precedence 1
ordered_cache_behavior {
path_pattern     = "/content/*"
allowed_methods  = ["GET", "HEAD", "OPTIONS"]
cached_methods   = ["GET", "HEAD"]
target_origin_id = local.s3_origin_id
forwarded_values {
query_string = false
cookies {
forward = "none"
}
}
min_ttl                = 0
default_ttl            = 3600
max_ttl                = 86400
compress               = true
viewer_protocol_policy = "redirect-to-https"
}
price_class = "PriceClass_200"
restrictions {
geo_restriction {
restriction_type = "blacklist"
locations        = ["CA"]
}
}
tags = {
Environment = "production"
}
viewer_certificate {
cloudfront_default_certificate = true
}
retain_on_delete = true
}

// creating the 1st EC2 Instance
	
resource "aws_instance" "HttpdInstance_1" {

depends_on = [
    aws_efs_file_system.httpd_efs,
    aws_efs_mount_target.efs_mount,
    aws_cloudfront_distribution.CloudFrontAccess,
  ]

  ami           = "ami-0e306788ff2473ccb"
  instance_type = "t2.micro"
  key_name      = var.EC2_Key
  security_groups = [ "${aws_security_group.httpd_security.name}" ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.httpdkey.private_key_pem
    host     = aws_instance.HttpdInstance_1.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd git -y",
      "sudo systemctl restart httpd",
      "sudo yum install -y amazon-efs-utils",
      "sudo mount -t efs -o tls ${aws_efs_file_system.httpd_efs.id}:/ /var/www/html",
      "sudo git clone https://github.com/raktim00/DevOpsHW.git /var/www/html",
      "echo '<img src='https://${aws_cloudfront_distribution.CloudFrontAccess.domain_name}/Raktim.JPG' width='300' height='330'>' | sudo tee -a /var/www/html/Raktim.html",
    ]
  }

  tags = {
    Name = "HttpdServer1"
  }
}

// creating the 2nd EC2 Instance
	
resource "aws_instance" "HttpdInstance_2" {

depends_on = [
    aws_instance.HttpdInstance_1,
  ]

  ami           = "ami-0e306788ff2473ccb"
  instance_type = "t2.micro"
  key_name      = var.EC2_Key
  security_groups = [ "${aws_security_group.httpd_security.name}" ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.httpdkey.private_key_pem
    host     = aws_instance.HttpdInstance_2.public_ip
  }
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd -y",
      "sudo systemctl restart httpd",
      "sudo yum install -y amazon-efs-utils",
      "sudo mount -t efs -o tls ${aws_efs_file_system.httpd_efs.id}:/ /var/www/html",
     ]
  }

  tags = {
    Name = "HttpdServer2"
  }
}

// Finally opening the browser to that particular html sites to see how It's working.

resource "null_resource" "ChromeOpen"  {
depends_on = [
    aws_instance.HttpdInstance_2,
  ]

	provisioner "local-exec" {
	    command = "chrome  ${aws_instance.HttpdInstance_1.public_ip}/Raktim.html ${aws_instance.HttpdInstance_2.public_ip}/Raktim.html"
  	}
}
