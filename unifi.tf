data "unifi_client_list" "all" {
  wired = true
}

locals {
  # UniFi clients are matched to managed servers by the controller's `note`
  # field — set the note to the homelab server key for the client to be
  # picked up here.
  unifi_clients = {
    for client in data.unifi_client_list.all.clients : client.note => client
    if client.note != null
  }
}
