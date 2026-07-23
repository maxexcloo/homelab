module "object_storage" {
  source = "../object_storage"

  items = nonsensitive(keys(local.services_model_by_feature.object_storage))
}
