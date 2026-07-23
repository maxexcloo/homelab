variable "capabilities" {
  default = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readBuckets",
    "readFiles",
    "shareFiles",
    "writeFiles",
  ]
  description = "Capabilities granted to each bucket-scoped application key"
  type        = set(string)
}

variable "endpoint" {
  default     = "s3.us-east-005.backblazeb2.com"
  description = "S3-compatible endpoint exposed to consumers"
  type        = string
}

variable "items" {
  description = "Stable logical keys requiring isolated object storage"
  type        = set(string)
}
