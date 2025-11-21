# Apache Spark Cluster with Terraform & Ansible

Deploy a complete Apache Spark cluster on Google Cloud

## Overview
- Student Name: Le Minh Hoang
- Student ID: 2440051

# Architecture Diagram
![Architecture Diagram](./arch.svg)

## What It Does

Automatically creates and configures:
- 1 Runner node (Code-Server + Ansible)
- 1 Master node (Spark master)
- n Worker nodes (auto-scaling/discovery)

## Quick Start

```bash
# 1. Clone
git clone https://github.com/hzhoanglee/cloud-devops-2025-course
cd cloud-devops-2025-course/terraform

# 2. Deploy
terraform init
terraform apply -auto-approve

# 3. Access Code-Server
# Open: http://:8888
# Password: DuEmDaCoGangChoTinhYeuNguQuen

# 4. Configure Master
ansible-playbook ./common.yaml -i inventory.ini --limit spark_master --ssh-common-args='-o StrictHostKeyChecking=no'
ansible-playbook ./master.yaml -i inventory.ini --limit spark_master --ssh-common-args='-o StrictHostKeyChecking=no'

# 5. Test
cd /opt/cloud-devops-2025-course/java
spark-submit --class WordCount --master spark://10.0.1.20:7077 app.jar filesample.txt
```

## Access

- **Code-Server**: `http://<PUBLIC_IP>:8888`
- **Spark UI**: `http://<PUBLIC_IP>:8080`

## Tech Stack

- Terraform (infrastructure)
- Ansible (configuration)
- Go (service discovery)
- Apache Spark 2.4.3

## Architecture

```
Internet → Load Balancer → VPC (10.0.1.0/24)
                           ├── Runner (10.0.1.10)
                           ├── Master (10.0.1.20)
                           └── Workers (10.0.1.3x - scalable)
```

## Features

- Automated deployment
- Dynamic/automatic horizontal scaling
- Secure VPC + NAT
- SSH keys auto-distributed
- Web-based IDE

## Cleanup

```bash
terraform destroy -auto-approve
```
---

**Cloud and Big Data - USTH 2025**