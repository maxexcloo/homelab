locals {
  host_files = {
    for name in setunion(keys(local.cloudflare_tunnel_files), keys(local.onepassword_host_files)) : name => merge(
      try(local.cloudflare_tunnel_files[name], {}),
      try(local.onepassword_host_files[name], {}),
    )
  }
}
