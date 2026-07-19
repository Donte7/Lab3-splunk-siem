# variables.tf
#
# WHAT: Every value that could reasonably change between deployments lives
#       here as an input variable, instead of being hardcoded in main.tf.
# WHY:  This is what makes a Terraform config REUSABLE rather than a
#       one-off script. Redeploying this for Lab 4, or from a different
#       location, or with a different VM size, means changing values in
#       terraform.tfvars — never touching main.tf itself.
# SECURITY NOTE: `my_ip_cidr` and `ad_vnet_cidr` have NO defaults on
#       purpose. Terraform will refuse to run without you explicitly
#       providing them. A default of "0.0.0.0/0" here would be a silent
#       invitation to expose SSH/8000 to the entire internet — the exact
#       mistake this variable is designed to prevent.

variable "location" {
  description = "Azure region to deploy into"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group for the Splunk lab"
  type        = string
  default     = "rg-lab3-splunk"
}

variable "vnet_name" {
  description = "Name of the VNet created for the Splunk VM"
  type        = string
  default     = "vnet-splunk"
}

variable "vnet_address_space" {
  description = "Address space for the Splunk VNet. Deliberately in a DIFFERENT range than the Lab 1 AD VNet (commonly 10.0.0.0/16) so the two can be connected later via VNet Peering without an overlap conflict."
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "subnet_name" {
  description = "Name of the subnet the Splunk VM's NIC lives in"
  type        = string
  default     = "snet-splunk"
}

variable "subnet_prefix" {
  description = "CIDR block for the Splunk subnet"
  type        = list(string)
  default     = ["10.1.1.0/24"]
}

variable "nsg_name" {
  description = "Name of the Network Security Group protecting the Splunk VM"
  type        = string
  default     = "nsg-splunk"
}

variable "my_ip_cidr" {
  description = "YOUR public IP in CIDR notation (e.g. \"203.0.113.42/32\"). Used to scope SSH (22) and the Splunk web UI (8000) to ONLY your machine. Find yours at https://ifconfig.me and append /32."
  type        = string
  # No default — you must supply this. See SECURITY NOTE above.
}

variable "ad_vnet_cidr" {
  description = "CIDR range of the Lab 1 Active Directory VM's VNet (commonly 10.0.0.0/16). Used to scope the forwarder-input port (9997) to only that VNet, once peered — never to the public internet."
  type        = string
  # No default — you must supply this.
}

variable "vm_name" {
  description = "Name of the Splunk Ubuntu VM"
  type        = string
  default     = "vm-splunk-indexer"
}

variable "vm_size" {
  description = "Azure VM size. Standard_B2s = 2 vCPU / 4GB RAM, matching Splunk's stated minimum for this lab."
  type        = string
  default     = "Standard_D2s_V3"
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB. Splunk's index + logs need headroom beyond the base OS image."
  type        = number
  default     = 30
}

variable "admin_username" {
  description = "Admin username for SSH login to the Ubuntu VM"
  type        = string
  default     = "azureuser"
}

variable "ssh_public_key_path" {
  description = "Path to your LOCAL SSH public key file (e.g. ~/.ssh/id_ed25519.pub). Never point this at a private key."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "tags" {
  description = "Common resource tags applied to everything this config creates. Enterprise cost-tracking and ownership accountability starts here."
  type        = map(string)
  default = {
    project     = "home-lab-security-series"
    lab         = "lab3-splunk-siem"
    managed_by  = "terraform"
    environment = "lab"
  }
}