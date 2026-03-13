resource "restapi_object" "resend_api_key_server" {
  for_each = {
    for k, v in local._servers : k => v
    if v.enable_resend
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

resource "restapi_object" "resend_api_key_service" {
  for_each = {
    for k, v in local._services_deployments : k => v
    if v.enable_resend
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
