provider "aws" {
  region = var.region

  # Tagged at the provider so nothing is missed: after `make down`, anything still tagged Layer=platform is a
  # leftover (scripts/leftovers.sh).
  default_tags {
    tags = {
      Project   = var.project
      Layer     = "platform"
      ManagedBy = "terraform"
    }
  }
}
