resource "restapi_object" "resend_api_key_server" {
  for_each = {
    for k, v in local._servers : k => v
    if local.servers_resources[k].resend
  }

  data                      = jsonencode({ name = each.key })
  id_attribute              = "id"
  ignore_all_server_changes = true
  path                      = "/api-keys"
  provider                  = restapi.resend
}
