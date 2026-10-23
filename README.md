<!-- ABOUTME: README for the OCI Always Free ARM Terraform stack. -->
<!-- ABOUTME: Covers quick start, configuration, free-tier limits, and teardown. -->

# oci-alwaysfree-tf-stack

Terraform stack that provisions an Always Free ARM instance on Oracle Cloud, with VCN, subnet, and internet gateway. Auto-discovers the availability domain and latest Ubuntu 24.04 image so you don't need to look up region-specific OCIDs.

---

## What this builds

* 1 VCN
* 1 Public Subnet
* 1 Internet Gateway
* A managed default security list with public Tailscale UDP and optional scoped Bootstrap SSH
* 1 ARM Compute Instance (`VM.Standard.A1.Flex`, Ubuntu 24.04) with 2 OCPUs, 12GB Memory and a 50GB Boot Volume
* Optional: 1 AMD Compute Instance (`VM.Standard.E2.1.Micro`, Ubuntu 24.04 x86_64) in the same subnet, with a 50GB Boot Volume and an optional cloud-init that joins it to your tailnet

---

## Prerequisites

* An active OCI account ([sign up for Always Free](https://www.oracle.com/cloud/free/)).
* [Terraform](https://developer.hashicorp.com/terraform/install) installed.
* OCI CLI installed and configured with API keys — see Oracle's [Required Keys and OCIDs](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm) guide for the full walkthrough. Quick version:
  ```bash
  uv tool install oci-cli   # or: pipx install oci-cli
  oci setup config           # generates ~/.oci/config + API key pair
  # Then upload ~/.oci/oci_api_key_public.pem to:
  # OCI Console → Profile → My profile → API keys → Add API key
  ```
* An SSH key pair (`ssh-keygen -t ed25519` if you don't have one).

---

## Quick Start / How to Use

1. Copy the example variables file:
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` — only two values are required:
   ```bash
   # Find your compartment (tenancy) OCID:
   oci iam compartment list --query 'data[0]."compartment-id"' --raw-output

   # List available regions:
   oci iam region list --query 'data[*].name' --raw-output
   ```

3. Run the preflight check to catch config issues before they become cryptic Terraform errors:
   ```bash
   ./preflight.sh
   ```

4. Deploy:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

---

## File Structure

```
oci-alwaysfree-tf-stack/
├── main.tf                  # Provider, data sources, networking, compute
├── variables.tf             # Input variables (2 required, 13 with defaults)
├── outputs.tf               # IPs, OCIDs for downstream use
├── terraform.tfvars.example # Copy to terraform.tfvars and fill in
├── preflight.sh             # Pre-deploy validation (OCI auth, keys, config)
├── tests/
│   ├── compute.tftest.hcl    # terraform test for instance sizing and the micro instance
│   ├── networking.tftest.hcl # terraform test, offline with a mock provider
│   └── preflight.bats        # bats tests for preflight.sh
├── AGENTS.md                # Instructions for coding agents (CLAUDE.md imports it)
└── .gitignore               # Ignores tfstate, .terraform/, and tfvars
```

---

## Configuration

Only `compartment_id` and `region` are required. Everything else has sensible defaults.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `compartment_id` | `string` | *required* | OCID of the compartment (usually your tenancy OCID) |
| `region` | `string` | *required* | OCI region identifier (e.g., `us-chicago-1`) |
| `availability_domain_index` | `number` | `0` | Index into the AD list. Change if your preferred AD is full. |
| `ssh_public_key` | `string` | `null` | SSH public key string. If null, reads from `ssh_public_key_path`. |
| `ssh_public_key_path` | `string` | `~/.ssh/id_ed25519.pub` | Path to SSH public key file (used when `ssh_public_key` is null) |
| `name_prefix` | `string` | `"oci-arm"` | Prefix for resource display names and DNS labels |
| `ocpus` | `number` | `2` | ARM OCPUs (Always Free max: 2 total across A1 instances) |
| `memory_in_gbs` | `number` | `12` | Memory in GB (Always Free max: 12 total across A1 instances) |
| `boot_volume_size_in_gbs` | `number` | `50` | Boot volume in GB (Always Free max: 200 total) |
| `assign_public_ip` | `bool` | `true` | Keep a public IP for outbound Internet access through the Internet Gateway |
| `bootstrap_ssh_cidr` | `string` | `null` | Temporary workstation IPv4 `/32` allowed to reach public SSH; null allows no public SSH |
| `micro_instance_enabled` | `bool` | `false` | Also create one `VM.Standard.E2.1.Micro` in the same subnet |
| `micro_hostname` | `string` | `null` | Display name, VCN hostname and Tailscale hostname of the micro instance; null uses `<sanitized name_prefix>-micro` |
| `micro_boot_volume_size_in_gbs` | `number` | `50` | Micro boot volume in GB (shares the 200 GB total) |
| `tailscale_auth_key` | `string` (sensitive) | `null` | One-off Tailscale auth key; when set, cloud-init joins the micro instance to the tailnet |

---

## Accessing the Instance

**SSH in** once the instance is running:
   ```bash
   terraform apply -var='bootstrap_ssh_cidr=198.51.100.42/32'
   ssh -i ~/.ssh/your-key ubuntu@$(terraform output -raw instance_public_ip)
   ```

Use only the workstation's current public IPv4 address with `/32`. After a
tested Tailscale handoff, close public SSH while retaining the public IP for
outbound traffic:

```bash
# Remove bootstrap_ssh_cidr from terraform.tfvars, or set it to null there.
terraform apply
terraform output -json bootstrap_ssh_access
```

---

## Always Free Guardrails

The defaults stay within free-tier limits. If you change them, make sure the totals across all your instances stay under these caps:

| Resource | This stack uses | Always Free limit |
|----------|----------------|-------------------|
| ARM OCPUs | 2 | 2 total (1,500 OCPU hours/month) |
| ARM memory | 12 GB | 12 GB total (9,000 GB hours/month) |
| Boot volume | 50 GB (100 GB with the micro instance) | 200 GB total |
| Instances | 1 ARM (+ 1 AMD micro, optional) | Up to 2 ARM + 2 AMD micro |
| VCN | 1 | Included |

**Cost Disclaimer: While this targets the Always Free tier, you are ultimately responsible for checking your OCI billing dashboard to ensure you haven't exceeded limits or selected the wrong region/shapes.**

---

## Tearing Down

```bash
terraform destroy
```

Removes the instance, VCN, subnet, and gateway. Terraform state tracks what was created, so the destroy is clean and complete.

---

## Troubleshooting

- **Intermittent 401-NotAuthenticated from Terraform**: Check that your PEM key file (`~/.oci/oci_api_key.pem`) ends cleanly with `-----END PRIVATE KEY-----` and nothing after it. The OCI CLI's Python SDK tolerates trailing junk, but the Terraform provider's Go SDK does not — it causes random auth failures where some API calls succeed and others don't. The `preflight.sh` script checks for this automatically.

- **"Python X.Y not found" from OCI CLI**: Install with `uv tool install oci-cli` or `pipx install oci-cli` to use an isolated Python environment instead of depending on the system Python.

## Notes

- **OCI authentication**: The provider uses `~/.oci/config` by default. See the [OCI Terraform provider docs](https://registry.terraform.io/providers/oracle/oci/latest/docs) for alternatives (env vars, instance principal, etc.).

- **Public IP lifecycle**: Keep `assign_public_ip = true` in this Internet Gateway topology so the instance retains outbound Internet access. Set `bootstrap_ssh_cidr = null` after Tailscale handoff to remove public SSH ingress.

- **Finding your OCIDs**:
  ```bash
  # Compartment (tenancy OCID)
  oci iam compartment list --query 'data[0]."compartment-id"' --raw-output

  # Available regions
  oci iam region list --query 'data[*].name' --raw-output
  ```
