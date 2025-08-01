terraform {
  backend "s3" {
    bucket = "homelab-terraform-state"
    key    = "infrastructure/terraform.tfstate"
    region = "us-west-002"
    
    endpoint = "s3.us-west-002.backblazeb2.com"
    
    # Credentials from environment:
    # export AWS_ACCESS_KEY_ID=<B2_APPLICATION_KEY_ID>
    # export AWS_SECRET_ACCESS_KEY=<B2_APPLICATION_KEY>
    
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_metadata_api_check     = true
    
    # Use S3 state locking
    dynamodb_table = "terraform-state-lock"
  }
}