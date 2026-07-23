data "unifi_client" "server" {
  for_each = local._unifi_servers

  mac = each.value.networking.mac_address
}

locals {
  _unifi_servers = {
    for server_key, server in local.servers_model : server_key => server
    if server.networking.mac_address != ""
  }

  unifi_clients = data.unifi_client.server
}
