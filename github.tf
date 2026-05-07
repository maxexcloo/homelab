# username = "" resolves to the currently authenticated GitHub user.
data "github_user" "default" {
  username = ""
}
