terraform {
  required_version = ">= 1.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# VPC Network
resource "google_compute_network" "vpc" {
  name                    = "${var.prefix}-vpc"
  auto_create_subnetworks = false
}

# Subnet with predictable IP range
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.prefix}-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

# Cloud Router for NAT
resource "google_compute_router" "router" {
  name    = "${var.prefix}-router"
  region  = var.region
  network = google_compute_network.vpc.id
}

# Cloud NAT for outbound internet access
resource "google_compute_router_nat" "nat" {
  name                               = "${var.prefix}-nat"
  router                             = google_compute_router.router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"
}

# Firewall rules
resource "google_compute_firewall" "allow_internal" {
  name    = "${var.prefix}-allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.0.1.0/24"]
}

resource "google_compute_firewall" "allow_ssh_iap" {
  name    = "${var.prefix}-allow-ssh-iap"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  # Allow SSH from IAP (Identity-Aware Proxy) range
  source_ranges = ["35.235.240.0/20"]
}

resource "google_compute_firewall" "allow_runner_port" {
  name    = "${var.prefix}-allow-runner-8888"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8888"]
  }

  target_tags   = ["runner"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_master_port" {
  name    = "${var.prefix}-allow-master"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8080", "7077"]
  }

  target_tags   = ["master"]
  source_ranges = ["0.0.0.0/0"]
}

resource "google_compute_firewall" "allow_worker_port" {
  name    = "${var.prefix}-allow-worker"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["8081"]
  }

  target_tags   = ["worker"]
  source_ranges = ["0.0.0.0/0"]
}

# Static public IP for the VPC
resource "google_compute_address" "public_ip" {
  name   = "${var.prefix}-public-ip"
  region = var.region
}

# Runner instance (10.0.1.10)
resource "google_compute_instance" "runner" {
  name         = "${var.prefix}-runner"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["runner"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = "10.0.1.10"
  }

  metadata = {
    ssh-keys = "root:${file(var.ssh_public_key_path)}"
    private-key = file(var.ssh_private_key_path)
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    
    curl -H "Metadata-Flavor: Google" \
      "http://metadata.google.internal/computeMetadata/v1/instance/attributes/private-key" \
      -o /root/.ssh/spark_cluster_key
    chmod 600 /root/.ssh/spark_cluster_key
    
    apt-get update
    apt-get install -y ansible
    
    curl -o /tmp/runner-playbook.yaml https://raw.githubusercontent.com/hzhoanglee/cloud-devops-2025-course/refs/heads/main/terraform/runner-playbook.yaml
    curl -o /tmp/common.yaml https://raw.githubusercontent.com/hzhoanglee/cloud-devops-2025-course/refs/heads/main/ansible/common.yaml
    
    ansible-playbook /tmp/runner-playbook.yaml -i localhost, -c local
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }
}

# Master instance (10.0.1.20)
resource "google_compute_instance" "master" {
  name         = "${var.prefix}-master"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["master"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = "10.0.1.20"
  }

  metadata = {
    ssh-keys = "root:${file(var.ssh_public_key_path)}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    # Allow root SSH login
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }
}

# Slave instances (10.0.1.30, 10.0.1.31)
resource "google_compute_instance" "slave" {
  count        = 2
  name         = "${var.prefix}-slave-${count.index + 1}"
  machine_type = "e2-medium"
  zone         = var.zone
  tags         = ["slave"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 20
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    network_ip = "10.0.1.${30 + count.index}"
  }

  metadata = {
    ssh-keys = "root:${file(var.ssh_public_key_path)}"
  }

  metadata_startup_script = <<-EOF
    #!/bin/bash
    # Allow root SSH login
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    
    max_retries=30
    retry_delay=5
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
      if curl -X POST http://10.0.1.10:3636/worker; then
        break
      else
        retry_count=$((retry_count + 1))
        echo "Attempt $retry_count failed. Retrying in $retry_delay seconds..."
        sleep $retry_delay
      fi
    done
    
    if [ $retry_count -eq $max_retries ]; then
      echo "Failed to register worker after $max_retries attempts"
      exit 1
    fi
  EOF

  service_account {
    scopes = ["cloud-platform"]
  }
}

# Forwarding rule to route public IP to runner:8888
resource "google_compute_forwarding_rule" "runner_forwarding" {
  name                  = "${var.prefix}-runner-forwarding"
  region                = var.region
  ip_address            = google_compute_address.public_ip.address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "8888"
  target                = google_compute_target_instance.runner_target.self_link
}

resource "google_compute_target_instance" "runner_target" {
  name     = "${var.prefix}-runner-target"
  zone     = var.zone
  instance = google_compute_instance.runner.self_link
}

resource "google_compute_forwarding_rule" "master_forwarding" {
  name                  = "${var.prefix}-master-forwarding"
  region                = var.region
  ip_address            = google_compute_address.public_ip.address
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "8080"
  target                = google_compute_target_instance.master_target.self_link
}

resource "google_compute_target_instance" "master_target" {
  name     = "${var.prefix}-master-target"
  zone     = var.zone
  instance = google_compute_instance.master.self_link
}