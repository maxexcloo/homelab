locals {
  script      = "python3 ${path.module}/encrypt.py"
  script_hash = filesha256("${path.module}/encrypt.py")
}
