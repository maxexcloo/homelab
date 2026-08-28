resource "resend_api_key" "cluster" {
  for_each = local.clusters

  name       = "cluster-${each.key}"
  permission = "full_access"
}
