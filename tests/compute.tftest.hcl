# ABOUTME: Offline plan tests for the A1 sizing defaults and the optional
# ABOUTME: E2.1.Micro instance, including its Tailscale cloud-init.

mock_provider "oci" {}

override_data {
  target = data.oci_identity_availability_domains.ads
  values = {
    availability_domains = [{ name = "AD-1" }]
  }
}

override_data {
  target = data.oci_core_images.ubuntu
  values = {
    images = [{ id = "ocid1.image.oc1.example" }]
  }
}

override_data {
  target = data.oci_core_images.ubuntu_micro
  values = {
    images = [{ id = "ocid1.image.oc1.micro-example" }]
  }
}

variables {
  compartment_id = "ocid1.tenancy.oc1..example"
  region         = "us-chicago-1"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest hermes-test"
}

run "a1_defaults_fit_always_free" {
  command = plan

  assert {
    condition     = oci_core_instance.this.shape_config[0].ocpus == 2 && oci_core_instance.this.shape_config[0].memory_in_gbs == 12
    error_message = "The A1 defaults must stay within the Always Free 2 OCPU / 12 GB allowance."
  }
}

run "micro_disabled_by_default" {
  command = plan

  assert {
    condition     = length(oci_core_instance.micro) == 0 && length(data.oci_core_images.ubuntu_micro) == 0
    error_message = "No micro instance or x86 image lookup may exist unless micro_instance_enabled is true."
  }

  assert {
    condition     = output.micro_instance_id == null && output.micro_hostname == null
    error_message = "Micro outputs must be null while the instance is disabled."
  }
}

run "micro_enabled_without_tailscale_key" {
  command = plan

  variables {
    micro_instance_enabled = true
  }

  assert {
    condition     = oci_core_instance.micro[0].shape == "VM.Standard.E2.1.Micro"
    error_message = "The micro instance must use the Always Free AMD micro shape."
  }

  assert {
    condition     = oci_core_instance.micro[0].source_details[0].source_id == "ocid1.image.oc1.micro-example"
    error_message = "The micro instance must boot the x86 image, not the aarch64 one."
  }

  assert {
    condition     = oci_core_instance.micro[0].source_details[0].boot_volume_size_in_gbs == "50"
    error_message = "The micro boot volume must default to OCI's 50 GB minimum."
  }

  assert {
    condition     = oci_core_instance.micro[0].display_name == "ociarm-micro" && oci_core_instance.micro[0].create_vnic_details[0].hostname_label == "ociarm-micro"
    error_message = "The default micro hostname must derive from the sanitized name_prefix."
  }

  assert {
    condition     = oci_core_instance.micro[0].create_vnic_details[0].assign_public_ip
    error_message = "The micro instance needs a public IP for egress through the internet gateway."
  }

  assert {
    condition     = !contains(keys(oci_core_instance.micro[0].metadata), "user_data")
    error_message = "Without a Tailscale auth key the micro instance must carry no cloud-init."
  }

  assert {
    condition     = length([for rule in oci_core_default_security_list.this.ingress_security_rules : rule if rule.protocol == "6"]) == 0
    error_message = "Enabling the micro instance must not open any TCP ingress."
  }
}

run "micro_joins_tailnet_with_key" {
  command = plan

  variables {
    micro_instance_enabled = true
    micro_hostname         = "judoka-api"
    tailscale_auth_key     = "tskey-auth-example"
  }

  assert {
    condition     = strcontains(base64decode(oci_core_instance.micro[0].metadata["user_data"]), "--hostname='judoka-api'")
    error_message = "Cloud-init must join the tailnet under micro_hostname."
  }

  assert {
    condition     = startswith(base64decode(oci_core_instance.micro[0].metadata["user_data"]), "#cloud-config\n")
    error_message = "user_data must be a cloud-config document."
  }

  assert {
    condition     = !contains(keys(oci_core_instance.this.metadata), "user_data")
    error_message = "The Tailscale key must never reach the A1 instance, where user_data would force replacement."
  }
}

run "rejects_invalid_micro_hostname" {
  command = plan

  variables {
    micro_instance_enabled = true
    micro_hostname         = "Judoka_API"
  }

  expect_failures = [var.micro_hostname]
}

run "rejects_micro_boot_volume_below_oci_minimum" {
  command = plan

  variables {
    micro_instance_enabled        = true
    micro_boot_volume_size_in_gbs = 49
  }

  expect_failures = [var.micro_boot_volume_size_in_gbs]
}
