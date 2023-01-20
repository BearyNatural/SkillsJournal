# CloudFormation
 CloudFormation Finalised file:

TemplateBuildImg.png

![alt text](https://github.com/adam-p/markdown-here/raw/master/src/common/images/icon48.png "Logo Title Text 1")

# Create your own static S3 website infrastructure easily #

by Kaylene Howe

Follow these basic steps:

1. Ensure you have your domain setup in a public hosted zone in Route53 with your authoritative name servers updated through your domain name service provider. See below for example: ![alt text](https://github.com/adam-p/markdown-here/raw/master/src/common/images/icon48.png "Logo Title Text 1")
2. Click here to start the CloudFormation stack wizard – 2 pages open, close the 404 as this is the prelim page 😉 and the 2nd page is the stack template;
    1. ***Ensure the wizard opens in the correct region!*** **US-EAST-1** 
    2. Enter your details for the following parameters:
        1. S3BucketName - Must be globally unique and comply with other rules;
        2. DomainNameJoin *must be in this format:* subdomain.domain.tld;
        3. Route53HostedZoneID *this is the id of the hosted zone from step 1*;
        4. OACforCloudFront *this needs to be unique to your account*
    3. Create takes 5-15 mins approx. wait until this is done;
3. Upload your index file into your s3 bucket;
4. Click in CloudFormation page – Outputs – WebsiteURL *(open it in a new tab or window)* 

***Your website is now **live**!***
