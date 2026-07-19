# versions.tf
#
# WHAT: Pins the exact Terraform CLI version range and provider version range
#       this configuration was written and tested against.
# WHY:  Without pinning, `terraform init` grabs the LATEST provider version
#       available at the time you run it. HashiCorp/Azure ship breaking
#       changes between major versions — an untested provider bump can
#       silently change resource behavior or fail outright. Pinning is
#       what keeps "it worked on my machine last month" from happening.
# HOW THIS FITS: In an enterprise environment, version pinning is usually
#       enforced by policy (e.g. in a CI pipeline that runs `terraform
#       validate`) so no engineer accidentally applies against an
#       unvetted provider release in production.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.100"
    }
  }
}

provider "azurerm" {
  features {}
}