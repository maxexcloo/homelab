module "server_resend" {
  source = "./modules/resend"

  items = nonsensitive(keys(local.servers_model_by_feature.mail))

  providers = {
    restapi = restapi.resend
  }
}

module "service_resend" {
  source = "./modules/resend"

  items = nonsensitive(keys(local.services_model_by_feature.mail))

  providers = {
    restapi = restapi.resend
  }
}
