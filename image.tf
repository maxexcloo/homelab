data "talos_image_factory_urls" "cluster" {
  for_each = local.talos_clusters

  architecture  = each.value.image.architecture
  platform      = each.value.image.platform
  schematic_id  = local.talos_image_factory_schematic_ids[each.key]
  talos_version = each.value.talos_version
}

locals {
  talos_image_factory_schematic_ids = {
    for name, schematic in talos_image_factory_schematic.cluster :
    name => schematic.id
  }
}

resource "talos_image_factory_schematic" "cluster" {
  for_each = local.talos_clusters

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = each.value.image.extensions
      }
    }
  })
}
