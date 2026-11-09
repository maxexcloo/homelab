import {
  for_each = local.clusters

  id = "svc:${each.value.tailscale_ingress_service}"
  to = tailscale_service.cluster_ingress[each.key]
}
