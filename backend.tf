terraform {
  backend "gcs" {
    bucket = "homelab-opentofu"
    prefix = "states/core"
  }
}
