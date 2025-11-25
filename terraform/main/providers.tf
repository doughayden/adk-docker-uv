provider "google" {
  project = var.project
  region  = var.location
}

provider "random" {}
