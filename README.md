# IBM Cloud Client-to-Site VPN Server — Terraform

Terraform configuration to deploy a **Client-to-Site VPN Server** on IBM Cloud VPC with all required infrastructure components.

---

## Architecture Overview

```
                        ┌──────────────────────────────────────────────────┐
                        │              IBM Cloud (us-east)                 │
                        │                                                  │
  VPN Client            │  ┌─────────────────────────────────────────────┐ │
  (OpenVPN)  ──TCP443──►│  │          VPC: wdccom-vpc-common              │ │
                        │  │                                              │ │
                        │  │  ┌──────────────┐    ┌──────────────────┐   │ │
                        │  │  │ Subnet Zone-1│    │  Subnet Zone-2   │   │ │
                        │  │  │192.0.2.0/24  │    │ (HA mode only)   │   │ │
                        │  │  │  [VPN Node 1]│    │  [VPN Node 2]    │   │ │
                        │  │  └──────┬───────┘    └────────┬─────────┘   │ │
                        │  │         └──────────┬──────────┘             │ │
                        │  │               VPN Server                    │ │
                        │  │     (192.168.32.0/22 client pool)           │ │
                        │  └─────────────────────────────────────────────┘ │
                        │                                                  │
                        │  ┌────────────────────────────────────────────┐  │
                        │  │        IBM Secrets Manager                 │  │
                        │  │  - vpn-server-certificate (Imported)       │  │
                        │  │  - vpn-client-certificate (Private Cert)   │  │
                        │  └────────────────────────────────────────────┘  │
                        └──────────────────────────────────────────────────┘
```

---

## Requirements Implemented

| # | Requirement | Configuration |
|---|-------------|---------------|
| 1 | **Resource Group** | `ibm_resource_group.vpn_rg` |
| 2 | **VPC** | `ibm_is_vpc.vpn_vpc` |
| 3 | **Client IPv4 Pool** | `192.168.32.0/22` |
| 4 | **HA or Standalone Subnets** | Toggle with `subnet_mode` |
| 5 | **Secrets Manager** | `ibm_resource_instance.secrets_manager` |
| 6 | **Server + Client Certs** | Server = Imported; Client = Private Certificate (SM) |
| 7 | **UserID & Passcode + Certificate** | `username` (IBMid) + `certificate` auth |
| 8 | **Security Groups** | UDP/TCP 443 inbound, all outbound |
| 9 | **IBM Private DNS** | `161.26.0.7`, `161.26.0.8` |
| 10 | **Split Tunnel** | `enable_split_tunneling = true` |
| 11 | **Idle Timeout** | `client_idle_timeout = 7200` seconds |

---

## Prerequisites

- [ ] IBM Cloud account with active billing
- [ ] IBM Cloud API Key
- [ ] IAM roles: **VPC Infrastructure Services Editor** + **Secrets Manager Manager**
- [ ] Terraform `>= 1.3.0` installed
- [ ] IBM Cloud Terraform provider `>= 1.65.0`

---

## Project Structure

```
vpn-client-to-site/
├── versions.tf        # Terraform + provider version constraints
├── providers.tf       # IBM Cloud provider configuration
├── variables.tf       # All input variable definitions
├── main.tf            # All resource definitions
├── outputs.tf         # Output values
├── terraform.tfvars   # Variable values (DO NOT commit to git)
└── README.md          # This file
```

---

## Quick Start

### 1. Configure API Key

```bash
# Option A — Environment variable (recommended)
export IC_API_KEY="your-ibm-cloud-api-key"

# Option B — terraform.tfvars (never commit this file)
echo 'ibmcloud_api_key = "your-ibm-cloud-api-key"' >> terraform.tfvars
```

### 2. Initialize

```bash
terraform init
```

### 3. Plan

```bash
terraform plan -out=tfplan
```

### 4. Apply

```bash
terraform apply tfplan
```

Provisioning takes approximately **10–15 minutes** (Secrets Manager instance creation is the slowest step).

---

## Connecting with OpenVPN

### Method 1 — IBM Cloud Console (Recommended — fully auto-merged)

1. Go to **VPC Infrastructure → VPNs → Client-to-site servers → your server**
2. Click the **Clients** tab
3. Click **Download client profile**
   - Choose **"All client profiles"** → downloads a merged `.ovpn` with cert+key already embedded
   - Or select a specific certificate → downloads a merged `.ovpn` for that cert
4. Import the `.ovpn` into your OpenVPN client — **no extra files needed**
5. When prompted:
   - **Username** → your IBMid email (e.g. `user@example.com`)
   - **Password** → one-time passcode from https://iam.cloud.ibm.com/identity/passcode

### Method 2 — Terraform-generated files (after `terraform apply`)

Three files are written automatically to the working directory:

| File | Description |
|------|-------------|
| `vpn-client.ovpn` | Complete profile with cert+key embedded inline |
| `client_public_key.crt` | Client cert — for use with IBM Console template profile |
| `client_private_key.key` | Client key — for use with IBM Console template profile |

```bash
# Import into OpenVPN CLI
sudo openvpn --config vpn-client.ovpn

# Or import into OpenVPN GUI / Tunnelblick / Viscosity
```

### Method 3 — IBM Console template + Terraform cert files

If you downloaded the IBM Console **template** `.ovpn` (not the merged one):

```
Place these three files in the same folder:
  📄 <vpn-server-name>.ovpn          ← IBM Console template
  📄 client_public_key.crt           ← from terraform output
  📄 client_private_key.key          ← from terraform output
```

OpenVPN Connect will find them automatically — no "Missing external certificate" prompt.

---

## Subnet Modes

### Standalone (Default)
```hcl
subnet_mode  = "standalone"
zones        = ["us-east-1"]
subnet_cidrs = ["192.0.2.0/24"]
```

### High Availability
```hcl
subnet_mode  = "ha"
zones        = ["us-east-1", "us-east-2"]
subnet_cidrs = ["192.0.2.0/24", "192.0.3.0/24"]
```

---

## Key Outputs

```bash
terraform output vpn_server_hostname       # Connect clients to this hostname
terraform output vpn_server_health         # Should be "ok" when stable
terraform output vpn_client_certificate_crn # CRN used by IBM Console Clients tab
terraform output client_ovpn_hint          # Quick-reference values for .ovpn

# Extract files manually if needed:
terraform output -raw client_certificate_pem  > client_public_key.crt
terraform output -raw client_private_key_pem  > client_private_key.key
terraform output -raw ca_chain_pem            > ca_chain.pem
terraform output -raw client_ovpn_profile     > vpn-client.ovpn
```

---

## Security Notes

1. **Never commit `terraform.tfvars`** — it contains your API key
2. **`vpn-client.ovpn`, `client_public_key.crt`, `client_private_key.key`** are in `.gitignore` — never commit them
3. The **Secrets Manager standard plan** is billed — delete with `terraform destroy` when not needed
4. Rotate certificates before `cert_validity_hours` expires (default 90 days)
5. Consider restricting the inbound security group rule from `0.0.0.0/0` to known egress IP ranges in production

---

## Destroy

```bash
terraform destroy
```

> **Note:** Secrets Manager instance deletion can take up to 30 minutes.

---

## Terraform Resources Created

| Resource | Type | Count |
|----------|------|-------|
| Resource Group | `ibm_resource_group` | 1 |
| VPC | `ibm_is_vpc` | 1 |
| VPC Address Prefixes | `ibm_is_vpc_address_prefix` | 1–2 |
| Subnets | `ibm_is_subnet` | 1 (standalone) / 2 (HA) |
| Secrets Manager | `ibm_resource_instance` | 1 |
| IAM Authorization Policy | `ibm_iam_authorization_policy` | 1 |
| TLS Keys (Root CA + Intermediate CA + Server) | `tls_private_key` | 3 |
| TLS Certificates | `tls_self_signed_cert` / `tls_locally_signed_cert` | 3 |
| SM Imported Certificates (Root CA, Intermediate CA, Server) | `ibm_sm_imported_certificate` | 3 |
| SM Private Cert Root CA Config | `ibm_sm_private_certificate_configuration_root_ca` | 1 |
| SM Private Cert Intermediate CA Config | `ibm_sm_private_certificate_configuration_intermediate_ca` | 1 |
| SM Private Cert Template | `ibm_sm_private_certificate_configuration_template` | 1 |
| SM Private Certificate (client) | `ibm_sm_private_certificate` | 1 |
| Security Group | `ibm_is_security_group` | 1 |
| Security Group Rules | `ibm_is_security_group_rule` | 4 |
| VPN Server | `ibm_is_vpn_server` | 1 |
| VPN Routes | `ibm_is_vpn_server_route` | 1–2 |
| Local files (ovpn, crt, key, ca_chain) | `local_sensitive_file` / `local_file` | 4 |

**Total: ~27 resources**
