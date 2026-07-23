# Fly deploys share one repository key because app files are isolated by app
# directory in the deploy repo.
resource "age_secret_key" "fly" {
  lifecycle {
    prevent_destroy = true
  }
}
