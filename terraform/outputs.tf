# outputs.tf
#
# WHAT: Values Terraform prints to your terminal after `terraform apply`
#       finishes, and that you can re-query anytime with `terraform output`.
# WHY:  Instead of tabbing over to the Azure Portal to hunt for the public
#       IP every time, it's right there in your terminal — and scriptable
#       for later steps (SSH commands, Ansible inventory, etc.).

output "public_ip_address" {
  description = "Public IP of the Splunk VM"
  value       = azurerm_public_ip.splunk.ip_address
}

output "private_ip_address" {
  description = "Private IP of the Splunk VM (use this when installing the Universal Forwarder's Receiving Indexer setting on the AD VM)"
  value       = azurerm_network_interface.splunk.private_ip_address
}

output "ssh_command" {
  description = "Ready-to-use SSH command"
  value       = "ssh ${var.admin_username}@${azurerm_public_ip.splunk.ip_address}"
}

output "splunk_web_ui_url" {
  description = "URL for the Splunk web UI once installed (SOP §4)"
  value       = "http://${azurerm_public_ip.splunk.ip_address}:8000"
}