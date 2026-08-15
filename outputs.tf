output "installer_images" {
  description = "Talos installer images by cluster."
  value = {
    for name, image in data.talos_image_factory_urls.cluster : name => image.urls.installer
  }
}

output "iso_urls" {
  description = "Talos ISO URLs by cluster."
  value = {
    for name, image in data.talos_image_factory_urls.cluster : name => image.urls.iso
    if image.urls.iso != ""
  }
}

output "schematic_ids" {
  description = "Content-addressed Talos Image Factory schematic IDs by cluster."
  value       = local.talos_schematic_ids
}

output "virtual_machine_iso_paths" {
  description = "TrueNAS ISO paths attached to managed virtual machines."
  value = {
    for key, device in local.virtual_machine_devices : device.virtual_machine => device.attributes.path
    if endswith(key, "/cdrom")
  }
}

output "virtual_machine_mac_addresses" {
  description = "Fixed MAC addresses for managed virtual-machine DHCP reservations."
  value = {
    for name in keys(local.virtual_machines) : name => local.machines[name].mac_address
  }
}

output "nfs_exports" {
  description = "TrueNAS NFS export paths managed for Kubernetes."
  value = {
    for name, share in truenas_share_nfs.managed : name => share.path
  }
}

output "oci_disk_image_url" {
  description = "Image Factory disk image used to prepare the OCI image archive."
  value       = try(data.talos_image_factory_urls.cluster[local.oci_cluster_name].urls.disk_image, null)
}

output "oci_public_addresses" {
  description = "Public IP addresses assigned to OCI Talos nodes."
  value = {
    for name, node in oci_core_instance.node : name => node.public_ip
  }
}
