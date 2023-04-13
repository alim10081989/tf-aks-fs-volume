output "host" {
  value     = azurerm_kubernetes_cluster.k8s.kube_config[0].host
  sensitive = true
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.k8s.kube_config_raw
  sensitive = true
}

output "resource_group_name" {
  description = "Resource Group Name : "
  value       = azurerm_resource_group.rg.name
}

output "storage_account_name" {
  description = "Storage Accout Name : "
  value       = azurerm_storage_account.aks-sc.name
}

output "storage_account_access_key" {
  description = "Storage Account Primary Key : "
  value       = azurerm_storage_account.aks-sc.primary_access_key
  sensitive   = true
}

output "storage_account_fileshare_name" {
  description = "Storage Account File Share Name : "
  value       = azurerm_storage_share.aks-fshare.name
}

output "container_registry_name" {
  description = "Container Registry Name : "
  value       = azurerm_container_registry.demoacr.name
}
