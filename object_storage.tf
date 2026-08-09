module "server_object_storage" {
  source = "./modules/object_storage"

  items = nonsensitive(keys(local.servers_model_by_feature.object_storage))
}

module "service_object_storage" {
  source = "./modules/object_storage"

  items = nonsensitive(keys(local.services_model_by_feature.object_storage))
}
