locals {
  _incus_vms = {
    for server_key, server in local.incus_vm_requests : server_key => server
    if(
      server.parent != "" &&
      can(local.incus_servers[server.parent])
    )
  }

  _onepassword_integration_ready = nonsensitive(var.integrations.onepassword.ready)
  defaults                       = var.defaults

  incus_servers = {
    for server_key, server in local.servers_model : server_key => server
    if(
      server.platform == "incus" &&
      server.type == "server" &&
      server.networking.management_host != ""
    )
  }

  incus_vm_requests = {
    for server_key, server in local.servers_model : server_key => server
    if(
      server.platform == "incus" &&
      server.type == "vm"
    )
  }

  oci_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.platform == "oci"
  }

  oci_vms = {
    for server_key, server in local.oci_servers : server_key => server
    if server.type == "vm"
  }

  render_json_template_expression_pattern     = "/\\$\\{([^}]*)\\}/"
  render_json_template_expression_replacement = "$${substr(jsonencode(tostring($1)), 1, length(jsonencode(tostring($1))) - 2)}"
  tailscale_device_addresses                  = var.integrations.tailscale_device_addresses
}
