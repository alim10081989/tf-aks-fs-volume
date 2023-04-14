resource "random_string" "resource_code" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_storage_account" "aks-sc" {
  name                     = "akssc${random_string.resource_code.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  tags = {
    Application = "Terraform"
    Purpose     = "Volume"
    Type        = "StorageAccount"
  }
}

resource "azurerm_storage_share" "aks-fshare" {
  name                 = "aksfshare-${random_string.resource_code.result}"
  storage_account_name = azurerm_storage_account.aks-sc.name
  quota                = 5
}
