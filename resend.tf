resource "restapi_object" "resend_api_key_homelab" {
  for_each = {
    for k, v in local.homelab_discovered : k => v
    if contains(local.homelab_flags[k].resources, "resend")
  }

  data                      = jsonencode({ name = each.key })
  id_attribute              = "id"
  ignore_all_server_changes = true
  path                      = "/api-keys"
  provider                  = restapi.resend
  read_path                 = "/api-keys"

  read_search = {
    query_string = ""
    results_key  = "data"
    search_key   = "name"
    search_value = each.key
  }
}
