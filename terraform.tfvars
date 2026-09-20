###############################################################################
# terraform.tfvars — Variable values for the IBM Cloud Client-to-Site VPN
# DO NOT commit this file to git — it contains your API key.
###############################################################################

# ibmcloud_api_key = "YOUR_IBM_CLOUD_API_KEY"   # Or set IC_API_KEY env var

region = "us-east"
zones  = ["us-east-1"]

resource_group_name = "hpc_prod"

vpc_name           = "wdccom-vpc-common"
vpc_address_prefix = "192.0.2.0/24"

subnet_mode  = "standalone"
subnet_cidrs = ["192.0.2.0/24"]

secrets_manager_name = "common-secrets-manager"
secrets_manager_plan = "standard"

root_ca_name         = "wdc-vpn-root-ca"
intermediate_ca_name = "wdc-vpn-intermediate-ca"
cert_template_name   = "wdc-vpn-cert-template"

cert_common_name       = "wdc-vpn.wf.ibmcloud"
cert_organization      = "Wells Fargo Grid-aaS"
cert_ca_validity_hours = 26280
cert_validity_hours    = 26280

security_group_name = "wdc-vpn-server-sg"
vpn_port            = 443
vpn_protocol        = "tcp"

vpn_server_name        = "wdc-vpn-client-to-site"
client_ip_pool         = "192.168.32.0/22"
client_dns_server_ips  = ["161.26.0.7", "161.26.0.8"]
enable_split_tunneling = true
client_idle_timeout    = 7200

vpn_routes = [
  {
    name        = "vpc-private-subnet-1"
    destination = "192.0.2.0/24"
  }
]

tags = ["vpn", "client-to-site", "wells-fargo", "grid-aas", "Schematics"]
