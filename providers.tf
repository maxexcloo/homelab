provider "truenas" {
  destroy_protection = true
  read_only          = var.truenas_read_only
  url                = var.truenas_url
}
