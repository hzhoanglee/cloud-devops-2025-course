output "public_ip" {
  description = "Public IP address for accessing service"
  value       = google_compute_address.public_ip.address
}

output "runner_private_ip" {
  description = "Private IP address of runner instance"
  value       = google_compute_instance.runner.network_interface[0].network_ip
}

output "master_private_ip" {
  description = "Private IP address of master instance"
  value       = google_compute_instance.master.network_interface[0].network_ip
}

output "slave_private_ips" {
  description = "Private IP addresses of slave instances"
  value       = google_compute_instance.slave[*].network_interface[0].network_ip
}

output "ssh_commands" {
  description = "SSH commands to connect to instances (via IAP)"
  value = {
    runner = "gcloud compute ssh root@${google_compute_instance.runner.name} --zone=${var.zone} --tunnel-through-iap"
    master = "gcloud compute ssh root@${google_compute_instance.master.name} --zone=${var.zone} --tunnel-through-iap"
    slave1 = "gcloud compute ssh root@${google_compute_instance.slave[0].name} --zone=${var.zone} --tunnel-through-iap"
  }
}

output "network_info" {
  description = "Network configuration summary"
  value = {
    vpc_name           = google_compute_network.vpc.name
    subnet_cidr        = google_compute_subnetwork.subnet.ip_cidr_range
    runner_access_url  = "http://${google_compute_address.public_ip.address}:8888"
    master_access_url  = "http://${google_compute_address.public_ip.address}:8080"
  }
}
