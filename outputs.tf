# ABOUTME: Outputs for the OCI instance stack — IPs, OCIDs, and
# ABOUTME: resource identifiers for downstream use or SSH access.

output "instance_id" {
  description = "OCID of the compute instance"
  value       = oci_core_instance.this.id
}

output "instance_public_ip" {
  description = "Public IP of the instance (empty if assign_public_ip is false)"
  value       = oci_core_instance.this.public_ip
}

output "instance_private_ip" {
  description = "Private IP within the VCN"
  value       = oci_core_instance.this.private_ip
}

output "image_id" {
  description = "OCID of the auto-selected Ubuntu image"
  value       = local.image_id
}

output "vcn_id" {
  description = "OCID of the VCN"
  value       = oci_core_vcn.this.id
}

output "subnet_id" {
  description = "OCID of the subnet"
  value       = oci_core_subnet.this.id
}

output "bootstrap_ssh_access" {
  description = "Whether temporary public SSH access is open and its scoped IPv4 /32"
  sensitive   = false
  value = {
    enabled = var.bootstrap_ssh_cidr != null
    cidr    = var.bootstrap_ssh_cidr
  }
}

output "micro_instance_id" {
  description = "OCID of the micro instance (null when micro_instance_enabled is false)"
  value       = one(oci_core_instance.micro[*].id)
}

output "micro_instance_public_ip" {
  description = "Public IP of the micro instance (null when disabled)"
  value       = one(oci_core_instance.micro[*].public_ip)
}

output "micro_instance_private_ip" {
  description = "Private IP of the micro instance within the VCN (null when disabled)"
  value       = one(oci_core_instance.micro[*].private_ip)
}

output "micro_hostname" {
  description = "Hostname the micro instance uses in the VCN and the tailnet (null when disabled)"
  value       = var.micro_instance_enabled ? local.micro_hostname : null
}
