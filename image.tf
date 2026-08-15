resource "talos_image_factory_schematic" "cluster" {
  for_each = local.clusters

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = each.value.image.extensions
      }
    }
  })
}

data "talos_image_factory_urls" "cluster" {
  for_each = local.clusters

  architecture  = each.value.image.architecture
  platform      = each.value.image.platform
  schematic_id  = local.talos_schematic_ids[each.key]
  talos_version = each.value.talos_version
}
