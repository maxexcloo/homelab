terraform {
  backend "s3" {
    bucket                      = "homelab-terraform-state"
    key                         = "services.tfstate"
    region                      = "us-west-002"
    endpoint                    = "s3.us-west-002.backblazeb2.com"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
