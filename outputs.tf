output "clusters" {
  description = "Talos Kubernetes cluster substrate configuration and endpoints."
  value = {
    for name, cluster in local.clusters : name => merge(
      {
        endpoint        = local.talos_cluster_endpoints[name]
        installer_image = data.talos_image_factory_urls.cluster[name].urls.installer
        schematic_id    = local.talos_image_factory_schematic_ids[name]
      },
      can(cloudflare_zero_trust_tunnel_cloudflared.cluster[name]) ? {
        tunnel_id = cloudflare_zero_trust_tunnel_cloudflared.cluster[name].id
      } : {},
      data.talos_image_factory_urls.cluster[name].urls.iso != "" ? {
        iso_url = data.talos_image_factory_urls.cluster[name].urls.iso
      } : {},
      try(data.talos_image_factory_urls.cluster[name].urls.disk_image, "") != "" ? {
        disk_image_url = data.talos_image_factory_urls.cluster[name].urls.disk_image
      } : {},
    )
  }
}

output "github_identity" {
  description = "GitHub Actions inputs for the Tailscale identity."
  sensitive   = true
  value = {
    audience  = tailscale_federated_identity.github.audience
    client_id = tailscale_federated_identity.github.id
  }
}

output "machines" {
  description = "Managed machine network identities and addresses."
  value = {
    for name, machine in local.machines : name => {
      address      = try(coalesce(local.machine_private_ipv4_addresses[name], try(machine.public_ipv4, null)), null)
      fqdn         = local.machine_fqdns[name]
      hostname     = local.machine_hostnames[name]
      tailscale_ip = try(local.tailscale_device_addresses[local.tailscale_machine_device_names[name]].ipv4, null)
    }
  }
}

output "storage" {
  description = "TrueNAS persistent dataset mount points."
  value = {
    for name, dataset in merge(truenas_dataset.child, truenas_dataset.root) : name => dataset.mount_point
  }
}
