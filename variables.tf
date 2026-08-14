variable "truenas_read_only" {
  default     = true
  description = "Refuse TrueNAS mutations. Set false only in the reviewed saved plan used for an approved apply."
  type        = bool
}
