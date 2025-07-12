# AWS Terraform Proof of Concept

This repository contains a proof-of-concept AWS environment built with Terraform as part of my technical interview challenge. The solution will demonstrate infrastructure as code best practices, network segmentation, and security controls for hosting a basic web server.

I will be using the Coalfire's modules for this project as they are recommended.

# Reviewing the Requirements of the Project

Overall, the project seems fairly straight forward. I will create and deploy the infrastructure as part of part I of the challenge and then proceed to part II and analyze the infrastructure, provide some improvement recommendations/plans and finally add some runbook-style notes for additional future deployments.

## Technical requirements

### Network

• 1 VPC – 10.1.0.0/16
• 3 subnets, spread evenly across two availability zones.

- Application, Management, Backend. All /24
- Management should be accessible from the internet
- All other subnets should NOT be accessible from internet

### Compute

• ec2 in an ASG running Linux in the application subnet

- SG allows SSH from management ec2, allows web traffic from the Application Load Balancer. No external traffic
- Script the installation of Apache
- 2 minimum, 6 maximum hosts
- t2.micro sized
  • 1 ec2 running Linux in the Management subnet
- SG allows SSH from a single specific IP or network space only
- Can SSH from this instance to the ASG
- t2.micro sized

### Supporting Infrastructure

• One ALB that sends web traffic to the ec2's in the ASG.

# Initial Project Structure

```
cf-poc-demo/
├── main.tf                    # Primary infrastructure orchestration
├── variables.tf               # Project input variables and configuration
├── outputs.tf                 # Key infrastructure values for reference
├── providers.tf               # Lock provider versions for reproducible deployments
├── terraform.tfvars           # Environment-specific values (excluded from git)
├── user-data/
│   └── install-apache.sh      # EC2 bootstrap script for web server setup
├── .gitignore                 # Version control exclusions
├── README.md                  # Project documentation and usage
└── docs/
    ├── architecture.jpg       # Infrastructure design documentation
    └── deployment.md          # Step-by-step deployment guide
```

# Infrastructure Organization Approach

For this proof-of-concept, I'm putting all the infrastructure code in one file (main.tf) instead of splitting it across multiple files. Since this is a simple setup with just a VPC, some EC2 instances, and a load balancer, keeping everything in one place makes it easier to build quickly and review during the demo. I'm using Coalfire's modules for the basic stuff (VPC, security groups) and writing the load balancer and auto scaling parts myself, so having it all together shows clearly what's a module versus what's custom code. For a real production system, I'd definitely split this into separate files, but for a POC demonstration this approach keeps things simple and fast.

# ALB Security Group Decision

For the Application Load Balancer security group, I chose to create it directly as an AWS resource instead of using Coalfire's security group module. Since the ALB only needs three basic rules (HTTP inbound, HTTPS inbound, all outbound), using a module would add unnecessary complexity for such this POC configuration.

# KMS Key Management Decision

For EBS encryption, I chose to use AWS-managed keys (`ebs_kms_key_arn = null`) instead of creating customer-managed KMS keys. I see that the Coalfire EC2 module supports custom KMS keys but implementing customer-managed keys would add complexity and costs. The volumes are still encrypted at rest using AWS-managed encryption.

# Single Management Server vs Second Server

Since we are spreading 3 subnets across 2 azs, I decided to deploy a second management server in the second az for high availability

# Scripting the installation of Apache on the App Servers

I decided the easiest approach to satisfy this requirement was to create a user data script locally and reference it in the Auto Scaling Group launch template. Terraform will read the script file, base64 encode it, and embed it into the launch template's user data field. When new instances launch, the ASG will automatically execute this script during the EC2 instance initialization process, ensuring Apache is installed and configured on each server at boot time.

# Issues

## VPC Flow Logs

During the initial deployment, I realized that I selected "s3" as the vpc-flow-logs location and it appears that the Coalfire VPC module must have a naming convention for the s3 bucket location (bucket = "${var.name}-flowlogs"). This bucket already exists so I created simply switched to cloud-watch-logs for the POC.

## Subnet Reference Errors After VPC Tag Changes

I initially messed up the subnet tagging because I'm still learning how third-party modules handle naming conventions. When I changed the VPC tags, it broke all my subnet references since the Coalfire module generates dynamic subnet names that I was hardcoding. I fixed it by diving into the module's source code on GitHub to understand how it actually creates subnet names, then used `terraform state show` to see the real subnet IDs, and finally switched to using `values(module.vpc.public_subnets)[0]` instead of guessing the exact key names.

# Initial Deployment

## Missing NAT Gateway

Upon checking my VPC resource map, I notice there was not a NAT Gateway deployed. I shoud have seen this during my review of my "terraform plan" but unfortunately it got overlooked. Upon some careful review, I realized that I was missing a line (enable_nat_gateway = true # Allows private subnets to access the internet) in the VPC module. After I corrected the mistake, the NAT gateway was deployed and my health checks were now "healthy"

## Testing the Connections

I first connected to the Management Server via SSH from my local machine. The security group allows ssh only from my IP address and the associated key pair.

Once I establisehd the connection with the management server, I securely copied the keyfile from my local machine to the management server to then establish the ssh connection from the management server to the app server. All connections were established as expected without issues.

## Verifying the user-data script successfully ran and installed Apache

After establishing the connected to the App server, I ran "sudo systemctl status httpd" and verifed Apache was successfully installed and running on the machine. (See associated screenshots)
