resource "resend_api_key" "cluster" {
  for_each = local.clusters

  name       = "kubelab-${each.key}"
  permission = "full_access"
}
