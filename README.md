# AWS Terraform Proof of Concept

## Solution Overview

This repository contains a proof-of-concept AWS environment built with Terraform as part of my technical interview challenge. The solution will demonstrate infrastructure as code best practices, network segmentation, and security controls for hosting a basic web server.

I will be using the Coalfire's modules for this project as they are recommended.

Overall, the project seems fairly straight forward. I will create and deploy the infrastructure as part of part I of the challenge and then proceed to part II and analyze the infrastructure, provide some improvement recommendations/plans and finally add some runbook-style notes for additional future deployments.

### Technical requirements

#### Network

• 1 VPC – 10.1.0.0/16
• 3 subnets, spread evenly across two availability zones.

- Application, Management, Backend. All /24
- Management should be accessible from the internet
- All other subnets should NOT be accessible from internet

#### Compute

• ec2 in an ASG running Linux in the application subnet

- SG allows SSH from management ec2, allows web traffic from the Application Load Balancer. No external traffic
- Script the installation of Apache
- 2 minimum, 6 maximum hosts
- t2.micro sized
  • 1 ec2 running Linux in the Management subnet
- SG allows SSH from a single specific IP or network space only
- Can SSH from this instance to the ASG
- t2.micro sized

#### Supporting Infrastructure

• One ALB that sends web traffic to the ec2's in the ASG.

### Project Structure

```
cf-poc-demo/
├── network.tf                 # VPC, subnets, and networking infrastructure
├── security.tf                # Security groups and WAF configuration
├── compute.tf                 # EC2 instances, ASG, and load balancer
├── monitoring.tf              # CloudWatch alarms and SNS notifications
├── variables.tf               # Project input variables and configuration
├── outputs.tf                 # Key infrastructure values for reference
├── providers.tf               # Lock provider versions for reproducible deployments
├── terraform.tfvars.example   # Example configuration file with all required variables
├── terraform.tfvars           # Your actual configuration (excluded from git)
├── user-data/
│   └── install-apache.sh      # EC2 bootstrap script for web server setup
├── .gitignore                 # Version control exclusions
├── README.md                  # Project documentation and usage
└── docs/
    ├── architecture.png       # Infrastructure design documentation
    ├── screenshots/           # Visual documentation and verification
    └── terraform-terminal-outputs/  # Complete terraform execution logs
```

## Deployment Instructions

### Prerequisites

- AWS CLI configured with credentials that have permission to create VPCs, EC2 instances, load balancers, and S3 buckets
- Terraform installed (I used version 1.12.2)
- An EC2 key pair already created in your AWS account. (Needed for SSH access)
- Your current public IP address to allow SSH access to the management server

**Note:** This project uses S3 for Terraform state storage. The backend configuration in `providers.tf` specifies the S3 bucket `cf-poc-terraform-state-b91fxp3k`. If you're deploying this yourself, you'll need to create your own S3 bucket and update the backend configuration accordingly.

### Step-by-Step Deployment

#### 1. Set Up Your Configuration

Clone this repository and copy the example configuration file to create your own:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Then edit `terraform.tfvars` with your actual values. The example file contains all the required variables with comments explaining what each one does. Make sure to update:

- `vpc_cidr`: Your desired VPC CIDR block (default: 10.1.0.0/16)
- `public_subnet_cidrs`: CIDR blocks for public subnets (management subnets)
- `private_subnet_cidrs`: CIDR blocks for private subnets (application and backend subnets)
- `my_ip`: Your actual public IP address (get it with `curl -s https://checkip.amazonaws.com`)
- `key_pair_name`: Your existing EC2 key pair name
- `notification_email`: Your email address for CloudWatch alerts (optional)
- `common_tags`: Update with your preferred tags

**Security Note**: The `terraform.tfvars` file contains sensitive network configuration and should never be committed to version control. It's already excluded in the `.gitignore` file.

#### 2. Initialize and Plan

Run these commands to get started:

```bash
terraform init
terraform plan -var-file=terraform.tfvars
```

The plan should show around 30-40 resources being created. I like to save the plan output so I can review it later if something goes wrong.

#### 3. Deploy Everything

Run the apply command and confirm when prompted:

```bash
terraform apply -var-file=terraform.tfvars
```

This usually takes about 5-10 minutes. You'll see the VPC and subnets get created first, then security groups, then the EC2 instances, and finally the load balancer.

#### 4. Get Your Access Information

Once deployment finishes, grab the important outputs:

```bash
terraform output
```

You'll need the management server IP for SSH access and the load balancer DNS name to test the web application.

### Testing Your Deployment

#### Connect to Management Server

Use SSH to connect to your management server:

```bash
ssh -i your-key-file.pem ec2-user@<management-server-ip>
```

#### Access Application Servers

From the management server, you can SSH to the application servers in the private subnets. You'll need to copy your private key to the management server first:

```bash
scp -i your-key-file.pem your-key-file.pem ec2-user@<management-server-ip>:~/.ssh/
```

Then from the management server:

```bash
ssh -i ~/.ssh/your-key-file.pem ec2-user@<app-server-private-ip>
```

#### Test the Web Application

Open your browser and go to the load balancer DNS name. You should see a webpage showing instance information, which proves Apache is running and the load balancer is working.

### Cleanup

When you're done testing, destroy everything to avoid charges:

```bash
terraform destroy -var-file=terraform.tfvars
```

### Initial Deployment

#### Missing NAT Gateway

Upon checking my VPC resource map, I notice there was not a NAT Gateway deployed. I shoud have seen this during my review of my "terraform plan" but unfortunately it got overlooked. Upon some careful review, I realized that I was missing a line (enable_nat_gateway = true # Allows private subnets to access the internet) in the VPC module. After I corrected the mistake, the NAT gateway was deployed and my health checks were now "healthy"

#### Testing the Connections

I first connected to the Management Server via SSH from my local machine. The security group allows ssh only from my IP address and the associated key pair.

Once I establisehd the connection with the management server, I securely copied the keyfile from my local machine to the management server to then establish the ssh connection from the management server to the app server. All connections were established as expected without issues.

#### Verifying the user-data script successfully ran and installed Apache

After establishing the connected to the App server, I ran "sudo systemctl status httpd" and verifed Apache was successfully installed and running on the machine. (See associated screenshots)

### Issues

#### VPC Flow Logs

During the initial deployment, I realized that I selected "s3" as the vpc-flow-logs location and it appears that the Coalfire VPC module must have a naming convention for the s3 bucket location (bucket = "${var.name}-flowlogs"). This bucket already exists so I created simply switched to cloud-watch-logs for the POC.

#### Subnet Reference Errors After VPC Tag Changes

I initially messed up the subnet tagging because I'm still learning how third-party modules handle naming conventions. When I changed the VPC tags, it broke all my subnet references since the Coalfire module generates dynamic subnet names that I was hardcoding. I fixed it by diving into the module's source code on GitHub to understand how it actually creates subnet names, then used `terraform state show` to see the real subnet IDs, and finally switched to using `values(module.vpc.public_subnets)[0]` instead of guessing the exact key names.

## Design Decisions and Assumptions

### Infrastructure Organization Approach

I initially put all the infrastructure code in one file (main.tf) to build quickly, but then reorganized it into logical modules to align with best practices. The code is now split into four files: `network.tf` for VPC and networking, `security.tf` for security groups and WAF, `compute.tf` for EC2 instances and load balancing, and `monitoring.tf` for CloudWatch alarms. I'm using Coalfire's modules for the foundational infrastructure (VPC, security groups) and writing the application-specific parts myself.

**Validation of Reorganization:** After completing the refactor, I ran `terraform plan` to ensure the reorganization didn't introduce any unintended changes. The plan showed "No changes. Your infrastructure matches the configuration." which confirms that the modular structure produces exactly the same infrastructure as the original monolithic approach. The complete output is captured in `docs/terraform-terminal-outputs/terraform-plan-after-reorganization.txt` for reference.

### ALB Security Group Decision

For the Application Load Balancer security group, I chose to create it directly as an AWS resource instead of using Coalfire's security group module. Since the ALB only needs three basic rules (HTTP inbound, HTTPS inbound, all outbound), using a module would add unnecessary complexity for such this POC configuration.

### KMS Key Management Decision

For EBS encryption, I chose to use AWS-managed keys (`ebs_kms_key_arn = null`) instead of creating customer-managed KMS keys. I see that the Coalfire EC2 module supports custom KMS keys but implementing customer-managed keys would add complexity and costs. The volumes are still encrypted at rest using AWS-managed encryption.

### Single Management Server vs Second Server

Since we are spreading 3 subnets across 2 azs, I decided to deploy a second management server in the second az for high availability

### Scripting the installation of Apache on the App Servers

I decided the easiest approach to satisfy this requirement was to create a user data script locally and reference it in the Auto Scaling Group launch template. Terraform will read the script file, base64 encode it, and embed it into the launch template's user data field. When new instances launch, the ASG will automatically execute this script during the EC2 instance initialization process, ensuring Apache is installed and configured on each server at boot time.

### Network Security Configuration Decision

After careful review of my project, I decided that moving the VPC and subnet CIDR blocks to variables was the best security practice. I initially exposed them directly in the configuration files because I was moving too quickly for this POC, but then I thought better of it. Even though this is just a demonstration environment, hardcoding network topology in version control creates unnecessary security exposure. I moved all the CIDR blocks to `terraform.tfvars` (which is excluded from git) and used completely different arbitrary values in the example file. This way, anyone who forks or reviews this repository won't accidentally learn the actual network layout I used for testing.

I'm aware that the earlier git commits still retain the CIDR ranges in the repository history, which is a good reminder that git never truly "forgets" sensitive information once it's committed. In a real-world scenario where this happened with production networks, I would need to rotate those CIDR ranges and potentially even create a fresh repository to ensure the network topology remains secure.

### Backend Migration to S3

As the final step of this POC, I migrated the Terraform state from local storage to S3 to prepare for potential collaboration. I used the local backend initially since I was the only one working on the project. I created an S3 bucket with versioning enabled and server-side encryption for security. The migration was seamless - `terraform init -migrate-state` successfully moved the existing state to S3, and subsequent `terraform plan` confirmed no infrastructure changes were needed.

## References to Resources Used

For this project, I used Coalfire's public Terraform modules from their GitHub repositories, specifically their VPC and security group modules, which saved me from having to write a lot of code! The AWS documentation at https://docs.aws.amazon.com/ was essential for understanding the specific configuration options and best practices for services like Auto Scaling Groups and Application Load Balancers. I also used Lucid Chart to create the architecture diagram.

## Assumptions Made

I assumed that Coalfire's public Terraform modules would work reliably without needing extensive customization, which mostly turned out to be true but did cause some surprises with their naming conventions that I had to work through.

Since this is a POC, I assumed that cost optimization should take priority over maximum availability, which is why I chose a single NAT Gateway instead of deploying one per AZ.

I also assumed that creating the backend subnets as requested in the requirements was sufficient even though I didn't define a specific purpose for them or add any resources to use them.

## Infrastructure Analysis - My Own Deployment Review

### Issues From My Mistakes

**Overly permissive ALB security group:** I accidentally added both HTTP (80) and HTTPS (443) rules to my ALB security group, but I'm only actually using HTTP, which creates unnecessary attack surface.

**Flow logs going to CloudWatch:** I chose CloudWatch for my VPC flow logs, but S3 would be cheaper for storage and allow longer retention periods.

**Single NAT Gateway deployment:** I configured `single_nat_gateway = true` for cost savings, but this means all my private instances depend on one NAT Gateway in one AZ, creating a single point of failure.

### Gaps From Original Requirements

**Backend subnets with no purpose:** The requirements called for backend subnets, but I created them without defining what they're actually for or adding any security controls around them.

**No WAF protection:** My ALB is directly exposed to the internet without any Web Application Firewall protection against common web attacks.

**Manual SSH key management:** I'm manually copying SSH keys to management servers instead of using SSM Session Manager, which would be more secure and manageable.

**No health monitoring for management servers:** I only have health checks for my ASG instances through the ALB, but there's no way to detect if my management servers fail.

**Only using 2 AZs:** I spread resources across us-east-1a and us-east-1b, but I could use a third AZ for better fault tolerance.

**No database layer:** I built a stateless application which is good, but there's no data persistence strategy or database backend.

**Missing monitoring and alerting:** I don't have any CloudWatch alarms set up, so I'm only relying on ALB health checks for monitoring.

**No backup strategy:** I have no EBS snapshots configured and no AMI creation strategy for recovery scenarios.

**No disaster recovery planning:** There's no cross-region strategy or documented runbooks for handling outages.

**No security scanning:** I haven't implemented any vulnerability assessments or compliance checks on the deployed infrastructure.

## Improvement Plan with Priorities

Based on my infrastructure analysis, here's how I'd prioritize fixing the issues I found. I'm focusing on the most impactful changes first that don't require major architectural overhauls.

**High Priority (Fix First):**
Remove the unnecessary HTTPS rule from my ALB security group since I'm only using HTTP anyway. Add basic CloudWatch alarms for my ASG instances so I know when something breaks. Set up simple EBS snapshot scheduling so I have backups if instances fail. Add WAF protection to my ALB since it's directly exposed to the internet without any web attack protection.

**Medium Priority (Fix Next):**
Switch my VPC flow logs from CloudWatch to S3 and enable versioning and lifecycle policies to save on storage costs. Set up health monitoring for my management servers so I can detect when they fail. Define what my backend subnets are actually supposed to be used for and add appropriate security groups.

**Low Priority (Nice to Have):**
Add a second NAT Gateway for redundancy, though this increases costs. Spread resources across a third AZ for better fault tolerance. Look into using SSM Session Manager instead of manually copying SSH keys around.

**Future Considerations:**
For a real production deployment, I'd need to add a database layer for data persistence, implement proper disaster recovery planning, set up comprehensive security scanning, and consider reserved instances for cost savings. But for this POC, the high and medium priority items would make the biggest difference in reliability and security.

### Implemented Improvements

Added comprehensive WAF protection to my ALB with AWS managed rule sets for OWASP Top 10 protection, known bad inputs filtering, and rate limiting to prevent DDoS attacks. The WAF is scoped to US and Canada traffic and uses count actions for most rules so I can monitor without breaking legitimate traffic initially.

Set up complete health monitoring for my management servers with CloudWatch alarms that track instance status, system status, CPU utilization, and network connectivity. All alarms send notifications to my dev email via SNS so I'll know immediately when something goes wrong. The monitoring covers both management servers individually and sends recovery notifications when issues are resolved. This gives me proper visibility into the health of my critical infrastructure access points.

## Operational Runbooks

### RUNBOOK: Environment Deployment

**Purpose:** Deploy the complete POC infrastructure from scratch  
**Prerequisites:** AWS CLI configured, Terraform installed, EC2 key pair created  
**Estimated Time:** 15-20 minutes  
**Risk Level:** Low (new deployment)

#### Pre-Deployment Checklist

- [ ] AWS CLI configured with appropriate permissions
- [ ] Terraform >= 1.0 installed
- [ ] EC2 key pair exists in target region
- [ ] Current public IP address known

#### Step-by-Step Procedure

1. **Clone and Setup Repository**

   ```bash
   git clone <repository-url>
   cd cf-poc-demo
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Configure Variables**

   ```bash
   # Edit terraform.tfvars with required values
   vim terraform.tfvars
   ```

   **Required Updates:**

   - `vpc_cidr` - Your desired VPC CIDR
   - `public_subnet_cidrs` - Management subnet CIDRs
   - `private_subnet_cidrs` - Application/backend subnet CIDRs
   - `my_ip` - Your public IP in CIDR format (get with `curl -s https://checkip.amazonaws.com`)
   - `key_pair_name` - Your EC2 key pair name
   - `notification_email` - Email for alerts

3. **Initialize and Validate**

   ```bash
   terraform init
   terraform validate
   terraform plan -var-file=terraform.tfvars
   ```

   **Expected Output:** ~40 resources to be created

4. **Deploy Infrastructure**

   ```bash
   terraform apply -var-file=terraform.tfvars
   ```

   **Wait for:** "Apply complete!" message

5. **Verify Deployment**

   ```bash
   # Get outputs
   terraform output

   # Test ALB endpoint
   curl -I $(terraform output -raw load_balancer_url)

   # Expected: HTTP 200 response
   ```

6. **Post-Deployment Validation**
   - [ ] ALB returns HTTP 200
   - [ ] Management servers accessible via SSH
   - [ ] CloudWatch alarms created
   - [ ] WAF rules active

#### Rollback Procedure

```bash
terraform destroy -var-file=terraform.tfvars
```

---

### RUNBOOK: EC2 Instance Outage Response

**Purpose:** Respond to EC2 instance failures and restore service  
**Trigger:** CloudWatch alarms, monitoring alerts, or user reports  
**Estimated Time:** 5-15 minutes  
**Risk Level:** Medium (service impact)

#### Immediate Assessment (2 minutes)

1. **Identify Affected Instance Type**

   ```bash
   # Check ASG instances
   aws autoscaling describe-auto-scaling-groups \
     --auto-scaling-group-names app-servers-asg \
     --query 'AutoScalingGroups[0].Instances[*].[InstanceId,AvailabilityZone,HealthStatus]'

   # Check management servers
   aws ec2 describe-instances \
     --filters "Name=tag:Name,Values=management-server*" \
     --query 'Reservations[*].Instances[*].[InstanceId,State.Name,Placement.AvailabilityZone]'
   ```

2. **Check ALB Health**
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn $(terraform output -raw target_group_arn)
   ```

#### Application Server Outage

**If ASG instance is unhealthy:**

1. **Wait for Auto-Recovery (5 minutes)**

   - ASG should automatically replace unhealthy instances
   - Monitor target group health

2. **Force Instance Replacement (if needed)**

   ```bash
   # Terminate unhealthy instance
   aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

   # ASG will launch replacement automatically
   ```

3. **Verify Recovery**
   ```bash
   # Check new instance health
   aws elbv2 describe-target-health \
     --target-group-arn $(terraform output -raw target_group_arn)
   ```

#### Management Server Outage

**If management server is unresponsive:**

1. **Check Instance Status**

   ```bash
   aws ec2 describe-instance-status --instance-ids <INSTANCE_ID>
   ```

2. **Attempt Restart**

   ```bash
   aws ec2 reboot-instances --instance-ids <INSTANCE_ID>
   ```

3. **Replace if Restart Fails**

   ```bash
   # Terminate failed instance
   aws ec2 terminate-instances --instance-ids <INSTANCE_ID>

   # Deploy replacement
   terraform apply -var-file=terraform.tfvars -target=module.management_server
   ```

#### Escalation Criteria

- Multiple instances failing simultaneously
- ASG not replacing instances after 10 minutes
- Infrastructure-wide connectivity issues

---

### RUNBOOK: S3 Bucket Recovery

**Purpose:** Restore S3 buckets and data after accidental deletion  
**Trigger:** Terraform state bucket or VPC flow logs bucket deleted  
**Estimated Time:** 10-30 minutes  
**Risk Level:** High (potential data loss)

#### Immediate Response (5 minutes)

1. **Assess Scope of Deletion**

   ```bash
   # Check if Terraform state bucket exists
   aws s3 ls s3://cf-poc-terraform-state-b91fxp3k/

   # Check VPC flow logs bucket
   aws s3 ls | grep flowlogs
   ```

2. **Check for Versioned Backups**
   ```bash
   # If bucket still exists but objects deleted
   aws s3api list-object-versions --bucket cf-poc-terraform-state-b91fxp3k
   ```

#### Terraform State Bucket Recovery

**If state bucket is completely deleted:**

1. **Recreate State Bucket**

   ```bash
   # Create bucket
   aws s3 mb s3://cf-poc-terraform-state-b91fxp3k

   # Enable versioning
   aws s3api put-bucket-versioning \
     --bucket cf-poc-terraform-state-b91fxp3k \
     --versioning-configuration Status=Enabled

   # Enable encryption
   aws s3api put-bucket-encryption \
     --bucket cf-poc-terraform-state-b91fxp3k \
     --server-side-encryption-configuration \
     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   ```

2. **Import Existing Infrastructure**

   ```bash
   # Initialize with new backend
   terraform init

   # Import critical resources (example for VPC)
   terraform import module.vpc.aws_vpc.this <VPC_ID>

   # Continue importing other resources as needed
   ```

3. **Refresh State**
   ```bash
   terraform refresh -var-file=terraform.tfvars
   ```

#### VPC Flow Logs Bucket Recovery

**If flow logs bucket is deleted:**

1. **Allow Terraform to Recreate**

   ```bash
   terraform apply -var-file=terraform.tfvars
   ```

   **Note:** Historical flow log data will be lost

2. **Verify Flow Logging Resumed**
   ```bash
   aws logs describe-log-groups --log-group-name-prefix "/aws/vpcflow"
   ```

#### Data Recovery from Versioned Objects

**If objects exist but are deleted:**

1. **List Deleted Objects**

   ```bash
   aws s3api list-object-versions \
     --bucket cf-poc-terraform-state-b91fxp3k \
     --prefix terraform.tfstate
   ```

2. **Restore Latest Version**
   ```bash
   aws s3api restore-object \
     --bucket cf-poc-terraform-state-b91fxp3k \
     --key terraform.tfstate \
     --version-id <VERSION_ID>
   ```

#### Prevention Measures

- Enable MFA delete on critical buckets
- Implement bucket policies preventing deletion
- Regular state file backups to secondary location
- Cross-region replication for critical data

---

### RUNBOOK: Safe Infrastructure Refactoring

**Purpose:** Make code changes without impacting running infrastructure  
**Risk Level:** Medium (potential service disruption if done incorrectly)

#### Pre-Change Validation

```bash
# Capture current state
terraform plan -var-file=terraform.tfvars > pre-change-plan.txt

# Ensure no pending changes
grep "No changes" pre-change-plan.txt || exit 1
```

#### Post-Change Validation

```bash
# Validate configuration
terraform validate

# Check for infrastructure drift
terraform plan -var-file=terraform.tfvars > post-change-plan.txt

# Verify no changes detected
grep "No changes" post-change-plan.txt || echo "WARNING: Infrastructure changes detected"
```

#### Emergency Rollback

```bash
# Revert to last known good configuration
git revert <COMMIT_HASH>
terraform plan -var-file=terraform.tfvars
```
