data "unifi_client_list" "all" {
  wired = true
}

locals {
  # Placeholder for UniFi client lookup output. When enabled, this should map
  # server keys to UniFi clients so private DNS/IPs can enrich server views.
  unifi_clients = {
    for client in data.unifi_client_list.all.clients : client.note => client
    if client.note != null
  }
}
