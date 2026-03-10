# data "unifi_client_info_list" "default" {}

locals {
  unifi_clients = {
    # for client in data.unifi_client_info_list.default.clients : client.name => client
  }
}
