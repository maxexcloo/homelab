# data "unifi_client_info_list" "all" {}

locals {
  unifi_clients_by_name = {
    # for client in data.unifi_client_info_list.all.clients : client.name => client
  }
}
