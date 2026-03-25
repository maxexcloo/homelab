variable "oci_private_key_base64" {
  description = "OCI private key (base64 encoded)"
  sensitive   = true
  type        = string
}

variable "oci_tenancy_ocid" {
  description = "OCI tenancy OCID"
  sensitive   = true
  type        = string
}

variable "resend_api_key" {
  description = "Resend API key"
  sensitive   = true
  type        = string
}
