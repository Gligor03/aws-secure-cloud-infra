# Secure AWS VPC with Bastion, S3, and Monitoring

## Overview

This project provisions a secure AWS environment using Terraform that mirrors how a real organization would operate a small, production‑ready footprint. It defines a VPC with public and private subnets, a bastion EC2 instance, hardened S3 buckets, CloudTrail logging, and CloudWatch alarms entirely as code, so the whole stack can be recreated or torn down in minutes in any AWS account. From a business perspective, this gives teams a repeatable pattern for onboarding new environments (dev/test/prod) with consistent security controls and minimal manual effort. The use of small, Free‑Tier‑friendly resources and automated teardown via `terraform destroy` keeps experimentation and training inexpensive, while the architecture is intentionally structured so it can scale out to additional private application tiers without redesigning the core network and security model.

## Architecture

![Architecture diagram](diagram/AWS%20Arch.png)

## Infrastructure

- VPC with public and private subnets  
- Bastion EC2 instance in public subnet  
- Secure S3 application bucket  
- CloudTrail trail and dedicated logs bucket  
- CloudWatch alarms on bastion health, CPU, and network out  

## Security design

The environment follows a security‑by‑design approach that combines network segmentation, least‑privilege IAM, and comprehensive logging to reduce risk while enabling efficient operations. Technically, ingress is restricted to a single bastion EC2 instance in a public subnet, with a security group that only allows SSH from a fixed admin IP (/32); everything else is placed in, or designed to live in, private subnets with no public IPs. Application data resides in a private S3 bucket with Block Public Access enabled, default server‑side encryption (SSE‑S3), and versioning, and it is reachable only through an EC2 IAM role whose policy grants the minimal S3 actions (list/get/put) on that one bucket instead of broad wildcard permissions. This pattern is attractive in a business environment because it standardizes how admins access internal resources, makes S3 data exposure much less likely, and simplifies compliance conversations around “who can access what”.

CloudTrail records management‑plane API activity to a dedicated, encrypted S3 logs bucket, creating a tamper‑resistant audit trail that supports security investigations, change tracking, and regulatory requirements without extra tooling. CloudWatch alarms on EC2 status checks, CPU utilization, and outbound network traffic give early warning of host failure, performance bottlenecks, or unusual data transfer, which helps operations teams respond before issues impact users or costs spike. Overall, the design turns a simple bastion‑and‑bucket lab into a reusable blueprint: teams can clone the Terraform code to spin up identical, secured environments across multiple accounts and stages, gaining scalability, reproducibility, operational efficiency, and cost control from day one.

## Getting started

### Prerequisites

- An AWS account with permissions to create VPC, EC2, S3, IAM, CloudTrail, and CloudWatch resources  
- Terraform installed locally  
- AWS credentials configured locally (for example via `aws configure` or an assumed role)  

### Deployment

1. **Clone the repository**

   ```bash
   git clone https://github.com/Gligor03/aws-secure-cloud-infra.git
   cd aws-secure-cloud-infra
   ```

2. **Initialize Terraform**

   ```bash
   terraform init
   ```

3. **Review the plan**

   Replace `YOUR_IP` with your public IP address in CIDR format (for example `203.0.113.10/32`):

   ```bash
   terraform plan -var "my_ip_cidr=YOUR_IP/32"
   ```

4. **Apply the configuration**

   ```bash
   terraform apply -var "my_ip_cidr=YOUR_IP/32"
   ```

   This will create the VPC, bastion host, secure S3 buckets, IAM role, CloudTrail trail, and CloudWatch alarms.

5. **Destroy when finished**

   To avoid ongoing costs, destroy all resources when you are done:

   ```bash
   terraform destroy -var "my_ip_cidr=YOUR_IP/32"
   ```

   If S3 buckets contain objects and Terraform cannot delete them automatically, empty them from the AWS console and rerun `terraform destroy`.

## Future improvements

This project is intentionally small but designed to be extended towards a more production‑like environment. Some natural next steps include:

- Replace SSH bastion access with AWS Systems Manager Session Manager, removing the need for public SSH and simplifying key management.  
- Add a NAT gateway and private application tier (for example, EC2 Auto Scaling group or ECS services in the private subnet) so workloads can reach the Internet for updates without exposing themselves publicly.  
- Wire CloudWatch alarms to Amazon SNS or a chat integration (email, Slack, etc.) so operational and security alerts trigger notifications instead of just updating alarm state.  
- Enable VPC Flow Logs and centralize them (for example in CloudWatch Logs or S3) to gain visibility into network traffic patterns, blocked connections, and potential lateral movement.  
- Introduce per‑environment configuration using Terraform workspaces or separate variable files (dev/test/prod), keeping the same secure pattern while scaling across multiple stages and accounts.  
- Add guardrails such as SCPs or AWS Config rules to ensure new resources follow similar security standards (for example, disallowing public S3 buckets or unencrypted volumes).

## Terraform usage

```bash
terraform init
terraform plan -var "my_ip_cidr=YOUR_IP/32"
terraform apply -var "my_ip_cidr=YOUR_IP/32"
terraform destroy -var "my_ip_cidr=YOUR_IP/32"
```