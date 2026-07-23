# The generic REST provider has no first-class Resend resource. read_search
# keeps API key creation idempotent by matching existing keys by name.
resource "restapi_object" "resend_api_key_server" {
  for_each = local.servers_model_by_feature.mail

  id_attribute              = "id"
  ignore_all_server_changes = true
  path                      = "/api-keys"
  provider                  = restapi.resend
  read_path                 = "/api-keys"

  data = jsonencode({
    name = each.key
  })

  read_search = {
    query_string = ""
    results_key  = "data"
    search_key   = "name"
    search_value = each.key
  }
}
