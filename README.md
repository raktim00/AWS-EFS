# The Full procedure of doing this practical you can find in below link :

## “Unlimited Shared Storage between AWS EC2 Instances using AWS EFS.” by Raktim Midya - https://link.medium.com/9R9zXccfbab

## Problem Statement :
- 1. Create the key and Create Security group which allow the port 80.
- 2. Launch EC2 instance.
- 3. In this Ec2 instance use the existing key or provided key and security group which we have created in step 1.
- 4. Launch one Volume using the EFS service and attach it in your vpc, then mount that volume into “/var/www/html” folder.
- 5. Developer have uploaded the code into GitHub repo also the repo has some images.
- 6. Copy the GitHub repo code into “/var/www/html”.
- 7. Create S3 bucket, and copy/deploy the images from GitHub repo into the s3 bucket and change the permission to public readable.
- 8. Create a Cloudfront using s3 bucket(which contains images) and use the Cloudfront URL to update in code in “/var/www/html”.
