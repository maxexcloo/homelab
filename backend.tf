terraform {
  backend "gcs" {
    bucket = "homelab-opentofu"
    prefix = "homelab"
  }
}
