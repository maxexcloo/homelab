# resource "local_file" "ssh_config" {
#   filename        = pathexpand("~/.ssh/config.d/homelab")
#   file_permission = "0600"
#
#   content = join("\n", [
#     for k, v in local.servers : <<-EOT
#       Host ${k}
#         HostName ${v.networking.management_address != "" ? v.networking.management_address : v.fqdn_internal}
#         Port ${v.networking.management_port}
#         User ${v.identity.username}
#     EOT
#     if v.networking.management_address != "" || v.features.tailscale
#   ])
# }
