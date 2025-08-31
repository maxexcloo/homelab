locals {
  acme_dns_homelab = {
    for k, v in restapi_object.acme_dns_homelab : k => jsondecode(v.create_response)
  }
}

resource "restapi_object" "acme_dns_homelab" {
  for_each = local.homelab_discovered

  data                      = jsonencode({})
  id_attribute              = "username"
  ignore_all_server_changes = true
  object_id                 = each.key
  path                      = "/register"
  provider                  = restapi.acme_dns
}
