<!-- ABOUTME: Agent instructions for the OCI Always Free ARM Terraform stack. -->
<!-- ABOUTME: Commands, architecture, test layout, and repo conventions. -->

# AGENTS.md

Terraform stack (oracle/oci provider `~> 6.0`) that provisions one Always Free
`VM.Standard.A1.Flex` Ubuntu 24.04 instance, plus an optional
`VM.Standard.E2.1.Micro` (`micro_instance_enabled`), with its own VCN, public
subnet and internet gateway. Everything lives in the root module; there are no
child modules and no remote backend.

## Commands

```bash
terraform init                    # needed once before validate/test
terraform fmt -check -recursive
terraform validate
terraform test                    # all tests/*.tftest.hcl, offline (mock provider)
terraform test -filter=tests/networking.tftest.hcl
bats tests/preflight.bats         # preflight.sh tests
bats -f "PKCS8" tests/preflight.bats   # single bats test by name regex
./preflight.sh                    # user-facing prerequisite check; hits the live OCI API
```

`terraform plan`/`apply` need a real `terraform.tfvars` (gitignored, copied from
`terraform.tfvars.example`) and working `~/.oci/config` credentials.

## How the pieces fit

- **No hardcoded OCIDs.** `main.tf` discovers the availability domain
  (`availability_domain_index` picks one) and the newest Ubuntu 24.04 A1 image
  via data sources. Only `compartment_id` and `region` are required inputs.
- **Default resources are adopted, not created.** The VCN's default route table
  and default security list are taken over with `oci_core_default_*` resources
  (`manage_default_resource_id`). The subnet sets no `security_list_ids`, so it
  inherits that default security list. Firewall changes go in
  `oci_core_default_security_list.this`, not in a new security list.
- **Ingress model.** Public ingress is only Tailscale UDP 41641 plus the ICMP
  rules OCI ships by default. SSH (TCP 22) exists only while
  `bootstrap_ssh_cidr` is set, through a `dynamic` block; the intended workflow
  is to open it for one workstation `/32`, hand off to Tailscale, then set it
  back to null. The public IP stays assigned because it is the instance's only
  egress path through the internet gateway.
- **Validation lives in `variables.tf`.** `bootstrap_ssh_cidr` must be a single
  IPv4 `/32`; `boot_volume_size_in_gbs` must be at least 50 (OCI minimum);
  `name_prefix` is sanitized into DNS labels (`local.dns_prefix` plus `vcn` or
  `sub`) and must fit OCI's 15-character label limit.
- **Image drift.** Both image lookups return the newest build and a new
  `source_id` forces replacement, so each instance ignores changes to it.
  The micro instance also ignores `metadata`: its Tailscale key is one-off
  cloud-init and must not recreate it later.
- **Always Free caps** (A1: 2 OCPU and 12 GB RAM, from 1,500 OCPU hours and
  9,000 GB hours a month; 2 E2.1.Micro; 200 GB block storage; all totalled
  across the tenancy) are the reason for the defaults. Keep new defaults inside them.

## Tests

- `tests/networking.tftest.hcl` runs `command = plan` against
  `mock_provider "oci"` with `override_data` for the AD and image lookups, so it
  needs no credentials. It asserts the security-list rule set, the public IP,
  the boot volume size and the `bootstrap_ssh_access` output, and uses
  `expect_failures` for each rejected variable value. Changes to ingress rules
  or variable validation need matching runs here.
- `tests/preflight.bats` puts stub `terraform` and `oci` binaries on `PATH` and
  points `HOME`/`OCI_CLI_CONFIG_FILE` at a temp tree, then runs `preflight.sh`
  from a directory holding a fixture `terraform.tfvars`.
- `tests/compute.tftest.hcl` uses the same mock setup to assert the A1
  defaults, the micro instance's shape, image, hostname and cloud-init, and
  that the Tailscale key never reaches the A1 instance.

## Conventions

- Every file starts with two `ABOUTME:` comment lines describing it (`#` in
  HCL/shell, `<!-- -->` in Markdown). Keep them on new files.
- Resources are named `this`, except the optional micro instance (`micro`);
  display names are `${var.name_prefix}-<kind>`.
- `preflight.sh` reads `terraform.tfvars` with grep/awk, not Terraform, and must
  stay portable between GNU and BSD tools (see the `stat -c || stat -f`
  fallback). It reports through `ok`/`skip`/`die` and exits 1 on any failure.
- The README variable table mirrors `variables.tf`; update both together.
