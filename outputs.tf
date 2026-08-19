output "clusters" {
  description = "Talos Kubernetes cluster substrate configuration and endpoints."
  value = {
    for name, cluster in local.talos_clusters : name => merge(
      {
        endpoint        = local.talos_cluster_endpoints[name]
        installer_image = data.talos_image_factory_urls.cluster[name].urls.installer
        schematic_id    = local.talos_schematic_ids[name]
        tunnel_id       = cloudflare_zero_trust_tunnel_cloudflared.cluster[name].id
      },
      data.talos_image_factory_urls.cluster[name].urls.iso != "" ? {
        iso_url = data.talos_image_factory_urls.cluster[name].urls.iso
      } : {},
      try(data.talos_image_factory_urls.cluster[name].urls.disk_image, "") != "" ? {
        disk_image_url = data.talos_image_factory_urls.cluster[name].urls.disk_image
      } : {},
    )
  }
}

output "machines" {
  description = "Managed machine network identities and addresses."
  value = {
    for name, machine in local.machines : name => {
      address      = try(machine.address, machine.public_ipv4)
      fqdn         = local.machine_fqdns[name]
      tailscale_ip = try(local.tailscale_device_ipv4[name], null)
    }
  }
}

output "storage" {
  description = "TrueNAS persistent storage NFS exports managed for Kubernetes."
  value = {
    for name, share in truenas_share_nfs.managed : name => share.path
  }
}
