terraform {
  backend "gcs" {
    bucket = "homelab-opentofu"
    prefix = "states/homelab-kubernetes/au"
  }
}
