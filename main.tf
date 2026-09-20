###############################################################################
# IBM Cloud Client-to-Site VPN Server
# Requirements:
#   1.  Resource Group
#   2.  VPC
#   3.  Client IPv4 pool : 192.168.32.0/22
#   4.  HA or Standalone subnets (controlled by var.subnet_mode)
#   5.  IBM Secrets Manager
#   6.  Server + Client certificates (TLS-generated server cert, SM Private client cert)
#   7.  UserID & Passcode authentication (IBMid) + certificate authentication
#   8.  Security Groups
#   9.  Additional DNS: 161.26.0.7 + 161.26.0.8 (IBM Cloud private DNS)
#   10. Split Tunnel mode
#   11. Idle Timeout: 7200 seconds
###############################################################################

###############################################################################
# 1. RESOURCE GROUP
###############################################################################
resource "ibm_resource_group" "vpn_rg" {
  name = var.resource_group_name
  tags = var.tags
}

###############################################################################
# 2. VIRTUAL PRIVATE CLOUD (VPC)
###############################################################################
resource "ibm_is_vpc" "vpn_vpc" {
  name                      = var.vpc_name
  resource_group            = ibm_resource_group.vpn_rg.id
  address_prefix_management = "manual"
  tags                      = var.tags

  depends_on = [ibm_resource_group.vpn_rg]
}

# VPC Address Prefixes — one per zone used
resource "ibm_is_vpc_address_prefix" "vpn_prefix" {
  count = length(var.subnet_cidrs)

  name = "${var.vpc_name}-prefix"
  vpc  = ibm_is_vpc.vpn_vpc.id
  zone = var.zones[count.index]
  cidr = var.subnet_cidrs[count.index]
}

###############################################################################
# 4. SUBNETS — HA (2 subnets / 2 zones) or Standalone (1 subnet / 1 zone)
###############################################################################
locals {
  subnet_count = var.subnet_mode == "ha" ? 2 : 1
}

resource "ibm_is_subnet" "vpn_subnet" {
  count = local.subnet_count

  name            = "${var.vpc_name}-subnet"
  vpc             = ibm_is_vpc.vpn_vpc.id
  zone            = var.zones[count.index]
  ipv4_cidr_block = var.subnet_cidrs[count.index]
  resource_group  = ibm_resource_group.vpn_rg.id
  tags            = var.tags

  depends_on = [ibm_is_vpc_address_prefix.vpn_prefix]
}

###############################################################################
# 5. IBM SECRETS MANAGER INSTANCE
###############################################################################
resource "ibm_resource_instance" "secrets_manager" {
  name              = var.secrets_manager_name
  service           = "secrets-manager"
  plan              = var.secrets_manager_plan
  location          = var.region
  service_endpoints = "public-and-private"
  parameters = {
    "service-endpoints" = "public-and-private"
    "allowed_network"   = "public-and-private"
  }
  resource_group_id = ibm_resource_group.vpn_rg.id
  tags              = var.tags

  timeouts {
    create = "30m"
    delete = "30m"
  }
}

# Allow DNS propagation and Secrets Manager instance initialization
resource "time_sleep" "wait_for_secrets_manager" {
  depends_on      = [ibm_resource_instance.secrets_manager]
  create_duration = "300s"
}

###############################################################################
# IAM SERVICE-TO-SERVICE AUTHORIZATION
# Allow VPN for VPC (is) to read secrets from Secrets Manager
###############################################################################
resource "ibm_iam_authorization_policy" "vpn_to_sm" {
  source_service_name         = "is"
  source_resource_type        = "vpn-server"
  target_service_name         = "secrets-manager"
  target_resource_instance_id = ibm_resource_instance.secrets_manager.guid
  roles                       = ["SecretsReader"]

  description = "Allow VPN Server to read TLS certificates from Secrets Manager"
}

###############################################################################
# 6. PKI — Two-Tier Certificate Authority (tls provider + IBM Secrets Manager)
#
#  Server certificate: generated with the tls provider, stored as an
#    ibm_sm_imported_certificate so the VPN service can resolve its CRN.
#
#  Client certificate: issued as an ibm_sm_private_certificate by the
#    Secrets Manager Private Cert engine. This enables the IBM Cloud Console
#    (VPN Server > Clients tab) to auto-merge cert+key into a ready-to-use
#    .ovpn — no manual "Add Certificate" step required.
#
#  Provisioning order:
#    Step 1  tls_private_key / tls_self_signed_cert         — Root CA key + cert
#    Step 2  tls_private_key / tls_locally_signed_cert      — Intermediate CA key + cert
#    Step 3a tls_private_key / tls_locally_signed_cert      — VPN Server leaf cert
#    Step 4  ibm_sm_imported_certificate (x3)               — Root CA, Intermediate CA, Server cert
#    Step 5  ibm_sm_private_certificate_configuration_*     — Register PKI in SM engine
#    Step 3b ibm_sm_private_certificate                     — VPN Client cert (issued by SM)
###############################################################################

# ── STEP 1 — Root CA key & self-signed certificate ───────────────────────────
resource "tls_private_key" "root_ca_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "root_ca_cert" {
  private_key_pem   = tls_private_key.root_ca_key.private_key_pem
  is_ca_certificate = true

  subject {
    common_name  = "VPN Root CA - ${var.cert_common_name}"
    organization = var.cert_organization
  }

  validity_period_hours = var.cert_ca_validity_hours

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# ── STEP 2 — Intermediate CA key & certificate signed by Root CA ──────────────
resource "tls_private_key" "intermediate_ca_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "intermediate_ca_csr" {
  private_key_pem = tls_private_key.intermediate_ca_key.private_key_pem

  subject {
    common_name  = "VPN Intermediate CA - ${var.cert_common_name}"
    organization = var.cert_organization
  }
}

resource "tls_locally_signed_cert" "intermediate_ca_cert" {
  cert_request_pem   = tls_cert_request.intermediate_ca_csr.cert_request_pem
  ca_private_key_pem = tls_private_key.root_ca_key.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.root_ca_cert.cert_pem
  is_ca_certificate  = true

  validity_period_hours = var.cert_ca_validity_hours

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
  ]
}

# ── STEP 3a — VPN Server leaf certificate signed by Intermediate CA ───────────
resource "tls_private_key" "server_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "server_csr" {
  private_key_pem = tls_private_key.server_key.private_key_pem

  subject {
    common_name  = "vpn-server.${var.cert_common_name}"
    organization = var.cert_organization
  }
}

resource "tls_locally_signed_cert" "server_cert" {
  cert_request_pem   = tls_cert_request.server_csr.cert_request_pem
  ca_private_key_pem = tls_private_key.intermediate_ca_key.private_key_pem
  ca_cert_pem        = tls_locally_signed_cert.intermediate_ca_cert.cert_pem

  validity_period_hours = var.cert_validity_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# ── STEP 4 — Store CA + Server certificates in Secrets Manager as Imported Certs
# Root CA — stored so it is accessible by CRN for chain resolution
resource "ibm_sm_imported_certificate" "root_ca_cert" {
  instance_id     = ibm_resource_instance.secrets_manager.guid
  region          = var.region
  name            = "vpn-root-ca-cert"
  description     = "VPN Root CA certificate"
  labels          = ["vpn", "root-ca"]
  secret_group_id = "default"

  certificate = tls_self_signed_cert.root_ca_cert.cert_pem

  depends_on = [time_sleep.wait_for_secrets_manager]
}

# Intermediate CA — chain: Intermediate CA cert + Root CA cert
resource "ibm_sm_imported_certificate" "intermediate_ca_cert" {
  instance_id     = ibm_resource_instance.secrets_manager.guid
  region          = var.region
  name            = "vpn-intermediate-ca-cert"
  description     = "VPN Intermediate CA certificate"
  labels          = ["vpn", "intermediate-ca"]
  secret_group_id = "default"

  certificate  = tls_locally_signed_cert.intermediate_ca_cert.cert_pem
  intermediate = tls_self_signed_cert.root_ca_cert.cert_pem

  depends_on = [time_sleep.wait_for_secrets_manager]
}

# VPN Server certificate — chain: server leaf + Intermediate CA + Root CA
# certificate_crn on ibm_is_vpn_server points here.
resource "ibm_sm_imported_certificate" "vpn_server_cert" {
  instance_id     = ibm_resource_instance.secrets_manager.guid
  region          = var.region
  name            = "vpn-server-certificate"
  description     = "VPN Server TLS certificate — full chain bundled for IBM VPN Server"
  labels          = ["vpn", "server-cert"]
  secret_group_id = "default"

  certificate  = tls_locally_signed_cert.server_cert.cert_pem
  private_key  = tls_private_key.server_key.private_key_pem
  intermediate = "${tls_locally_signed_cert.intermediate_ca_cert.cert_pem}${tls_self_signed_cert.root_ca_cert.cert_pem}"

  depends_on = [time_sleep.wait_for_secrets_manager]
}

# ── STEP 5 — Register CAs in the SM Private Certificate engine ────────────────
# Root CA + Intermediate CA configurations make the PKI visible in:
#   Secrets Manager UI > Secret Engines > Private Certificates
# The template (registered below) is what ibm_sm_private_certificate uses to
# issue the client certificate in STEP 3b below.

resource "ibm_sm_private_certificate_configuration_root_ca" "root_ca" {
  instance_id = ibm_resource_instance.secrets_manager.guid
  region      = var.region
  name        = var.root_ca_name

  common_name  = "VPN Root CA - ${var.cert_common_name}"
  organization = [var.cert_organization]
  max_ttl      = "${var.cert_ca_validity_hours}h"

  depends_on = [time_sleep.wait_for_secrets_manager]
}

resource "ibm_sm_private_certificate_configuration_intermediate_ca" "intermediate_ca" {
  instance_id = ibm_resource_instance.secrets_manager.guid
  region      = var.region
  name        = var.intermediate_ca_name

  common_name    = "VPN Intermediate CA - ${var.cert_common_name}"
  organization   = [var.cert_organization]
  max_ttl        = "${var.cert_ca_validity_hours}h"
  signing_method = "internal"
  issuer         = ibm_sm_private_certificate_configuration_root_ca.root_ca.name

  depends_on = [ibm_sm_private_certificate_configuration_root_ca.root_ca]
}

# Certificate template — used by ibm_sm_private_certificate (STEP 3b) to issue
# the VPN client certificate. Also satisfies "Certificate template required"
# in the Secrets Manager UI > Secret Engines > Private Certificates page.
resource "ibm_sm_private_certificate_configuration_template" "vpn_cert_template" {
  instance_id = ibm_resource_instance.secrets_manager.guid
  region      = var.region
  name        = var.cert_template_name

  certificate_authority = ibm_sm_private_certificate_configuration_intermediate_ca.intermediate_ca.name
  max_ttl               = "${var.cert_validity_hours}h"
  allow_any_name        = true
  enforce_hostnames     = false
  server_flag           = true
  client_flag           = true
  key_type              = "rsa"
  key_bits              = 4096

  depends_on = [ibm_sm_private_certificate_configuration_intermediate_ca.intermediate_ca]
}

# ── STEP 3b — VPN Client certificate issued by Secrets Manager Private Cert engine
#
#  Using ibm_sm_private_certificate so that:
#   • client_ca_crn on the VPN server points to a Private Certificate secret
#   • IBM Cloud Console > VPN Server > Clients tab can auto-merge cert+key into
#     a ready-to-use .ovpn ("Download client profile with merged private cert+key")
#   • Users never need to manually add client_public_key.crt / client_private_key.key
resource "ibm_sm_private_certificate" "vpn_client_cert" {
  instance_id     = ibm_resource_instance.secrets_manager.guid
  region          = var.region
  name            = "vpn-client-certificate"
  description     = "VPN client certificate issued by Secrets Manager — enables auto-merged .ovpn download from IBM Cloud Console"
  labels          = ["vpn", "client-cert"]
  secret_group_id = "default"

  certificate_template = ibm_sm_private_certificate_configuration_template.vpn_cert_template.name
  common_name          = "vpn-client.${var.cert_common_name}"
  ttl                  = "${var.cert_validity_hours}h"

  depends_on = [
    ibm_sm_private_certificate_configuration_template.vpn_cert_template,
    time_sleep.wait_for_secrets_manager,
  ]
}

###############################################################################
# 8. SECURITY GROUP
#    Allows VPN client traffic (UDP/TCP 443) inbound and all outbound to VPC.
###############################################################################
resource "ibm_is_security_group" "vpn_sg" {
  name           = var.security_group_name
  vpc            = ibm_is_vpc.vpn_vpc.id
  resource_group = ibm_resource_group.vpn_rg.id
  tags           = var.tags
}

# Inbound — VPN client connections (UDP 443 from anywhere)
resource "ibm_is_security_group_rule" "vpn_inbound_udp" {
  group     = ibm_is_security_group.vpn_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"

  protocol = "udp"
  port_min = var.vpn_port
  port_max = var.vpn_port
}

# Inbound — TCP 443 fallback (for clients behind strict firewalls)
resource "ibm_is_security_group_rule" "vpn_inbound_tcp" {
  group     = ibm_is_security_group.vpn_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"

  protocol = "tcp"
  port_min = var.vpn_port
  port_max = var.vpn_port
}

# Outbound — Allow VPN server to reach all VPC resources
resource "ibm_is_security_group_rule" "vpn_outbound_all" {
  group     = ibm_is_security_group.vpn_sg.id
  direction = "outbound"
  remote    = "0.0.0.0/0"
}

# Inbound — Allow ICMP (ping) for health checks
resource "ibm_is_security_group_rule" "vpn_inbound_icmp" {
  group     = ibm_is_security_group.vpn_sg.id
  direction = "inbound"
  remote    = "0.0.0.0/0"

  protocol = "icmp"
  type     = 8
}

###############################################################################
# VPN SERVER
###############################################################################
resource "ibm_is_vpn_server" "vpn_server" {
  name           = var.vpn_server_name
  resource_group = ibm_resource_group.vpn_rg.id
  tags           = var.tags

  # ── Network ──────────────────────────────────────────────────────────────
  subnets         = [for s in ibm_is_subnet.vpn_subnet : s.id]
  security_groups = [ibm_is_security_group.vpn_sg.id]

  # ── Transport ─────────────────────────────────────────────────────────────
  protocol = var.vpn_protocol
  port     = var.vpn_port

  # ── Server Certificate (Req 6) ────────────────────────────────────────────
  certificate_crn = ibm_sm_imported_certificate.vpn_server_cert.crn

  # ── Client IP Pool (Req 3) ────────────────────────────────────────────────
  client_ip_pool = var.client_ip_pool

  # ── Authentication (Req 7) ────────────────────────────────────────────────
  # certificate → Private Certificate issued by Secrets Manager; enables
  #               IBM Cloud Console to auto-merge cert+key into .ovpn per user
  # username    → IBMid (UserID & Passcode / SAML federation)
  client_authentication {
    method        = "certificate"
    client_ca_crn = ibm_sm_private_certificate.vpn_client_cert.crn
  }

  client_authentication {
    method            = "username"
    identity_provider = "iam"
  }

  # ── DNS Servers (Req 9) ───────────────────────────────────────────────────
  client_dns_server_ips = var.client_dns_server_ips

  # ── Split Tunnel (Req 10) ─────────────────────────────────────────────────
  enable_split_tunneling = var.enable_split_tunneling

  # ── Idle Timeout (Req 11) ─────────────────────────────────────────────────
  client_idle_timeout = var.client_idle_timeout

  depends_on = [
    ibm_iam_authorization_policy.vpn_to_sm,
    ibm_sm_imported_certificate.vpn_server_cert,
    ibm_sm_private_certificate.vpn_client_cert,
    ibm_is_subnet.vpn_subnet,
    ibm_is_security_group_rule.vpn_inbound_udp,
  ]
}

###############################################################################
# VPN ROUTES
# Advertise VPC private subnets to connected clients (split tunnel mode).
###############################################################################
resource "ibm_is_vpn_server_route" "vpn_routes" {
  for_each = { for r in var.vpn_routes : r.name => r }

  vpn_server  = ibm_is_vpn_server.vpn_server.id
  name        = each.value.name
  destination = each.value.destination
  action      = "deliver"
}

###############################################################################
# CLIENT DOWNLOAD PACKAGE
#
# With ibm_sm_private_certificate as the client cert, the IBM Cloud Console
# (VPN Server > Clients tab) can auto-merge cert+key into a ready-to-use .ovpn:
#
#   Console path:
#     VPC Infrastructure → VPNs → Client-to-site servers → <your server>
#     → Clients tab → Download client profile
#       • "All client profiles"       → merged .ovpn for every certificate
#       • Select one cert → Download  → merged .ovpn for that certificate
#
# The merged .ovpn is fully complete — no manual cert/key files needed.
#
# Alternatively, use the Terraform-generated files below:
#
#   vpn-client.ovpn         — cert+key embedded inline, ready to import
#   client_public_key.crt   — for use with the IBM Console template .ovpn
#   client_private_key.key  — for use with the IBM Console template .ovpn
#   ca_chain.pem            — full CA chain for reference
#
# How to connect (any of the above profiles):
#   1.  Import the .ovpn into your OpenVPN client
#   2.  When prompted:
#         Username : your IBMid email  (e.g. user@example.com)
#         Password : one-time passcode from https://iam.cloud.ibm.com/identity/passcode
###############################################################################

# Terraform-generated .ovpn — cert+key from the Secrets Manager private cert, embedded inline.
resource "local_sensitive_file" "client_ovpn_profile" {
  filename        = "${path.module}/vpn-client.ovpn"
  file_permission = "0600"

  content = <<-OVPN
client
dev tun
proto ${ibm_is_vpn_server.vpn_server.protocol}
remote ${ibm_is_vpn_server.vpn_server.hostname} ${ibm_is_vpn_server.vpn_server.port}
resolv-retry infinite
nobind
persist-key
persist-tun
verb 3
reneg-sec 0

# IBM Cloud private DNS — resolves private VPC service endpoints
dhcp-option DNS 161.26.0.7
dhcp-option DNS 161.26.0.8

# Split-tunnel: only traffic matching VPN server routes goes through the tunnel
route-nopull
route-delay 0

# IBMid authentication — every user enters their own credentials at connect time
# Username : IBMid email address
# Password : one-time passcode from https://iam.cloud.ibm.com/identity/passcode
auth-user-pass

# CA chain — used to verify the VPN server's TLS certificate (Intermediate + Root CA)
<ca>
${tls_locally_signed_cert.intermediate_ca_cert.cert_pem}${tls_self_signed_cert.root_ca_cert.cert_pem}</ca>

# Client certificate — issued by Secrets Manager Private Cert engine
<cert>
${ibm_sm_private_certificate.vpn_client_cert.certificate}</cert>

# Client private key — issued by Secrets Manager Private Cert engine
<key>
${ibm_sm_private_certificate.vpn_client_cert.private_key}</key>
OVPN

  depends_on = [ibm_is_vpn_server.vpn_server]
}

# CA chain PEM — separate file for reference / troubleshooting
resource "local_file" "ca_chain_pem" {
  filename        = "${path.module}/ca_chain.pem"
  file_permission = "0644"
  content         = "${tls_locally_signed_cert.intermediate_ca_cert.cert_pem}${tls_self_signed_cert.root_ca_cert.cert_pem}"
}

# client_public_key.crt — exact filename referenced in the IBM Cloud Console
# template .ovpn profile (#cert client_public_key.crt).
# Drop alongside the Console template profile — OpenVPN finds it automatically.
resource "local_sensitive_file" "client_public_key_crt" {
  filename        = "${path.module}/client_public_key.crt"
  file_permission = "0600"
  content         = ibm_sm_private_certificate.vpn_client_cert.certificate
}

# client_private_key.key — exact filename referenced in the IBM Cloud Console
# template .ovpn profile (#key client_private_key.key).
resource "local_sensitive_file" "client_private_key_key" {
  filename        = "${path.module}/client_private_key.key"
  file_permission = "0600"
  content         = ibm_sm_private_certificate.vpn_client_cert.private_key
}
