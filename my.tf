// To Tell Terraform Which User To Use.
provider "aws" {
  region     = "ap-south-1"
  profile    = "girish"
}


//Use RSA Algorithm For Key
resource "tls_private_key" "task1_key" {
  algorithm = "RSA"
}


//Create a Key 
resource "aws_key_pair" "deployment_key" {
  key_name   = "task1_key"
  public_key = "${tls_private_key.task1_key.public_key_openssh}"


  depends_on = [
    tls_private_key.task1_key
  ]
}


//Saving The Key In Local System
resource "local_file" "key-file" {
  content  = "${tls_private_key.task1_key.private_key_pem}"
  filename = "task1_key.pem"


  depends_on = [
    tls_private_key.task1_key
  ]
}

// Creating New Security Group
resource "aws_security_group" "terra_sg" {
  name        = "terra_sg"
  description = "Allow HTTP SSH inbound traffic"
  vpc_id      = "vpc-05eaf56d"

  //Allowing HTTP Port
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  //Allowing SSH Port
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


  tags = {
    Name = "terra_sg"
  }
}

//Creating a S3 Bucket in AWS!
resource "aws_s3_bucket" "gc-tf-bucket-01" {
  bucket = "gc-tf-bucket-01" 
  acl    = "public-read"
  tags = {
    Name        = "gc-tf-bucket-01" 
  }
  versioning {
	enabled =true
  }
}

//Uplaoding an file to S3
resource "aws_s3_bucket_object" "s3object" {
  bucket = aws_s3_bucket.gc-tf-bucket-01.id
  key    = "lol.jpg"
  source = "C:/Users/giris/Desktop/aws/lol.jpg"
  acl    = "public-read"
}

//Creating Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "This is origin access identity"
}

//Creating Cloud Distribution and Connecting It To S3
resource "aws_cloudfront_distribution" "s3tocloud" {
    origin {
        domain_name = "gc-tf-bucket-01.s3.amazonaws.com"
        origin_id = "S3-gc-tf-bucket-01"


        s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }
       
    enabled = true
      is_ipv6_enabled     = true

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-gc-tf-bucket-01"


        # Forward all query strings, cookies and headers
        forwarded_values {
            query_string = false
        
            cookies {
               forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
        min_ttl = 0
        default_ttl = 10
        max_ttl = 30
    }
    # Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }


    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}


//Creting An EC2 Instance
resource "aws_instance" "os" {
  ami               = "ami-0447a12f28fddb066"
  instance_type     = "t2.micro"
  key_name          = "task1_key"
  security_groups   = [ "terra_sg" ]

  connection {
    type        = "ssh"
    user        = "ec2-user"
    private_key = tls_private_key.task1_key.private_key_pem
    host        = "${aws_instance.os.public_ip}"
  }
  
  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git  -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd"
    ]
  }

  tags = {
    Name = "terraform_os"
  }
}

//Creating an EBS Volume
resource "aws_ebs_volume" "ebs_vol" {
  availability_zone = aws_instance.os.availability_zone
  size              = 1

  tags = {
    Name = "mydrive"
  }
}

//Attaching an EBS Volume to EC2
resource "aws_volume_attachment" "EBS_attachment" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.ebs_vol.id
  instance_id = aws_instance.os.id
  force_detach = true
}

output "myos_ip" {
  value = aws_instance.os.public_ip
}

//Null Resource Which Run After Attaching EBS Volume
resource "null_resource" "null1"  {

  depends_on = [
    aws_volume_attachment.EBS_attachment,
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_key.private_key_pem
    host     = aws_instance.os.public_ip
  }

  //To Format volume,mount to /var/www/html/ and copy data from github
  provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdf",
      "sudo mount  /dev/xvdf  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/SHADOW-01/terra1.git /var/www/html/"
    ]
  }
}