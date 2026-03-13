data "unifi_client_info_list" "all" {}

locals {
  unifi_clients = {
    for client in data.unifi_client_info_list.all.clients : client.name => client
  }
}
