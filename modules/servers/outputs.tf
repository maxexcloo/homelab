output "bootstrap" {
  description = "Rendered server bootstrap artifacts"
  sensitive   = true
  value = {
    cloud_config        = local.bootstrap_cloud_config
    setup_commands      = local._bootstrap_setup_commands
    truenas_custom_apps = local._bootstrap_truenas_custom_apps
  }
}

output "infrastructure" {
  description = "Server infrastructure values consumed outside the module"
  value = {
    age_public_keys = {
      for server_key, key in age_secret_key.server :
      server_key => key.public_key
    }
    cloudflare_tunnel_ids = {
      for server_key, tunnel in cloudflare_zero_trust_tunnel_cloudflared.server :
      server_key => tunnel.id
    }
    oci_addresses = {
      for server_key, server in oci_core_instance.server : server_key => {
        public_ipv4 = server.public_ip
        public_ipv6 = one(one(server.create_vnic_details).ipv6address_ipv6subnet_cidr_pair_details).ipv6address
      }
    }
  }
}

output "model" {
  description = "Deterministic server input and computed model"
  value = nonsensitive({
    by_feature       = local.servers_model_by_feature
    input            = local.servers_input
    servers          = local.servers_model
    x509_credentials = local.servers_model_x509_credentials
  })
}

output "render" {
  description = "Rendered server objects keyed by server"
  sensitive   = true
  value       = local.servers_render_servers
}

output "runtime" {
  description = "Server runtime objects keyed by server"
  sensitive   = true
  value       = local.servers
}
