# The generic REST provider has no first-class Resend resource. read_search
# keeps API key creation idempotent by matching existing keys by name.
resource "restapi_object" "resend_api_key_server" {
  for_each = local.servers_output_by_feature.resend

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

# Service keys use the expanded service-target key, so each deployment target
# gets its own Resend credential.
resource "restapi_object" "resend_api_key_service" {
  for_each = local.services_output_by_feature.resend

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
