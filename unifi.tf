# data "unifi_client_list" "all" {
#   wired = true
# }

locals {
  unifi_clients = {
    # for client in data.unifi_client_list.all.clients : client.name => client
  }
}
