###############################################################################
# OUTPUTS — IBM Cloud Client-to-Site VPN Server
###############################################################################

###############################################################################
# Resource Group
###############################################################################
output "resource_group_id" {
  description = "ID of the provisioned Resource Group."
  value       = ibm_resource_group.vpn_rg.id
}

output "resource_group_name" {
  description = "Name of the provisioned Resource Group."
  value       = ibm_resource_group.vpn_rg.name
}

###############################################################################
# VPC
###############################################################################
output "vpc_id" {
  description = "ID of the VPC."
  value       = ibm_is_vpc.vpn_vpc.id
}

output "vpc_crn" {
  description = "CRN of the VPC."
  value       = ibm_is_vpc.vpn_vpc.crn
}

output "vpc_default_security_group" {
  description = "Default security group ID of the VPC."
  value       = ibm_is_vpc.vpn_vpc.default_security_group
}

###############################################################################
# Subnets
###############################################################################
output "subnet_ids" {
  description = "IDs of provisioned VPN subnets (2 for HA, 1 for standalone)."
  value       = [for s in ibm_is_subnet.vpn_subnet : s.id]
}

output "subnet_cidrs" {
  description = "CIDR blocks of provisioned VPN subnets."
  value       = [for s in ibm_is_subnet.vpn_subnet : s.ipv4_cidr_block]
}

output "subnet_zones" {
  description = "Availability zones of provisioned VPN subnets."
  value       = [for s in ibm_is_subnet.vpn_subnet : s.zone]
}

###############################################################################
# Secrets Manager
###############################################################################
output "secrets_manager_id" {
  description = "GUID / instance ID of the Secrets Manager instance."
  value       = ibm_resource_instance.secrets_manager.guid
}

output "secrets_manager_crn" {
  description = "CRN of the Secrets Manager instance."
  value       = ibm_resource_instance.secrets_manager.crn
}

###############################################################################
# Certificates — CRNs
###############################################################################
output "vpn_server_certificate_crn" {
  description = "CRN of the VPN server imported certificate in Secrets Manager (certificate_crn on the VPN server)."
  value       = ibm_sm_imported_certificate.vpn_server_cert.crn
}

output "vpn_client_certificate_crn" {
  description = "CRN of the VPN client Private Certificate in Secrets Manager (client_ca_crn on the VPN server). Used by IBM Cloud Console to auto-merge cert+key into .ovpn."
  value       = ibm_sm_private_certificate.vpn_client_cert.crn
}

output "root_ca_name" {
  description = "Name of the Root CA configuration in the Secrets Manager Private Certificate engine."
  value       = ibm_sm_private_certificate_configuration_root_ca.root_ca.name
}

output "intermediate_ca_name" {
  description = "Name of the Intermediate CA configuration in the Secrets Manager Private Certificate engine."
  value       = ibm_sm_private_certificate_configuration_intermediate_ca.intermediate_ca.name
}

###############################################################################
# Certificates — PEM material (sensitive)
# Use: terraform output -raw <name>  to extract each PEM to a file.
###############################################################################
output "root_ca_certificate_pem" {
  description = "Root CA certificate PEM."
  value       = tls_self_signed_cert.root_ca_cert.cert_pem
  sensitive   = true
}

output "intermediate_ca_certificate_pem" {
  description = "Intermediate CA certificate PEM."
  value       = tls_locally_signed_cert.intermediate_ca_cert.cert_pem
  sensitive   = true
}

output "ca_chain_pem" {
  description = "Full CA chain (Intermediate CA + Root CA). Use as the <ca> block in your .ovpn profile."
  value       = "${tls_locally_signed_cert.intermediate_ca_cert.cert_pem}${tls_self_signed_cert.root_ca_cert.cert_pem}"
  sensitive   = true
}

output "client_certificate_pem" {
  description = "VPN client certificate PEM issued by Secrets Manager. This is client_public_key.crt."
  value       = ibm_sm_private_certificate.vpn_client_cert.certificate
  sensitive   = true
}

output "client_private_key_pem" {
  description = "VPN client private key PEM issued by Secrets Manager. This is client_private_key.key."
  value       = ibm_sm_private_certificate.vpn_client_cert.private_key
  sensitive   = true
}

###############################################################################
# Security Group
###############################################################################
output "vpn_security_group_id" {
  description = "ID of the VPN server security group."
  value       = ibm_is_security_group.vpn_sg.id
}

###############################################################################
# VPN Server
###############################################################################
output "vpn_server_id" {
  description = "ID of the Client-to-Site VPN server."
  value       = ibm_is_vpn_server.vpn_server.id
}

output "vpn_server_crn" {
  description = "CRN of the Client-to-Site VPN server."
  value       = ibm_is_vpn_server.vpn_server.crn
}

output "vpn_server_hostname" {
  description = "Public hostname of the VPN server. Use this in the OpenVPN client profile (.ovpn)."
  value       = ibm_is_vpn_server.vpn_server.hostname
}

output "vpn_server_protocol" {
  description = "Transport protocol in use (udp or tcp)."
  value       = ibm_is_vpn_server.vpn_server.protocol
}

output "vpn_server_port" {
  description = "Port number the VPN server listens on."
  value       = ibm_is_vpn_server.vpn_server.port
}

output "vpn_client_ip_pool" {
  description = "IPv4 CIDR pool assigned to connecting VPN clients."
  value       = ibm_is_vpn_server.vpn_server.client_ip_pool
}

output "vpn_server_health" {
  description = "VPN server health status reported by IBM Cloud."
  value       = ibm_is_vpn_server.vpn_server.health_state
}

output "vpn_server_lifecycle_state" {
  description = "Lifecycle state of the VPN server (stable / pending / etc.)."
  value       = ibm_is_vpn_server.vpn_server.lifecycle_state
}

output "vpn_server_ha_mode" {
  description = "Subnet mode — 'ha' (2 subnets across 2 zones) or 'standalone' (1 subnet)."
  value       = var.subnet_mode
}

output "vpn_split_tunneling" {
  description = "Whether split tunneling is enabled on the VPN server."
  value       = ibm_is_vpn_server.vpn_server.enable_split_tunneling
}

output "vpn_idle_timeout" {
  description = "Client idle timeout in seconds."
  value       = ibm_is_vpn_server.vpn_server.client_idle_timeout
}

output "vpn_dns_servers" {
  description = "DNS server IPs pushed to VPN clients (IBM Cloud private DNS)."
  value       = ibm_is_vpn_server.vpn_server.client_dns_server_ips
}

###############################################################################
# VPN Routes
###############################################################################
output "vpn_route_ids" {
  description = "Map of VPN route names to their IDs."
  value       = { for k, r in ibm_is_vpn_server_route.vpn_routes : k => r.id }
}

###############################################################################
# Convenience: Client Config hint
###############################################################################
output "client_ovpn_hint" {
  description = "Key values to populate in the OpenVPN client .ovpn profile."
  value = {
    remote   = ibm_is_vpn_server.vpn_server.hostname
    port     = ibm_is_vpn_server.vpn_server.port
    protocol = ibm_is_vpn_server.vpn_server.protocol
    auth     = "certificate + username (IBMid)"
    dns1     = "161.26.0.7"
    dns2     = "161.26.0.8"
  }
}

###############################################################################
# Full rendered OpenVPN client profile (.ovpn) — shared by ALL users.
#
# IBM Cloud Console path (preferred — auto-merged, no extra files needed):
#   VPC Infrastructure → VPNs → Client-to-site servers → <server>
#   → Clients tab → Download client profile
#
# Or save the Terraform-rendered profile directly:
#   terraform output -raw client_ovpn_profile > vpn-client.ovpn
###############################################################################
output "client_ovpn_profile" {
  description = "Ready-to-import .ovpn with cert+key embedded. Save with: terraform output -raw client_ovpn_profile > vpn-client.ovpn"
  sensitive   = true
  value       = <<-OVPN
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

# CA chain — verifies the VPN server's TLS certificate (Intermediate + Root CA)
<ca>
${tls_locally_signed_cert.intermediate_ca_cert.cert_pem}${tls_self_signed_cert.root_ca_cert.cert_pem}</ca>

# Client certificate — issued by Secrets Manager Private Cert engine
<cert>
${ibm_sm_private_certificate.vpn_client_cert.certificate}</cert>

# Client private key — issued by Secrets Manager Private Cert engine
<key>
${ibm_sm_private_certificate.vpn_client_cert.private_key}</key>
OVPN
}

###############################################################################
# client_public_key.crt / client_private_key.key
# Exact filenames referenced in the IBM Cloud Console template .ovpn profile
# (#cert client_public_key.crt / #key client_private_key.key).
# Drop these alongside the Console template and OpenVPN finds them automatically
# — no "Missing external certificate" prompt.
###############################################################################
output "client_public_key_crt" {
  description = "Client certificate PEM (client_public_key.crt). Place alongside the IBM Cloud Console template .ovpn."
  sensitive   = true
  value       = ibm_sm_private_certificate.vpn_client_cert.certificate
}

output "client_private_key_key" {
  description = "Client private key PEM (client_private_key.key). Place alongside the IBM Cloud Console template .ovpn."
  sensitive   = true
  value       = ibm_sm_private_certificate.vpn_client_cert.private_key
}
