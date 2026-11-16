variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}

data "azurerm_client_config" "current" {}

# Key Vault names must be globally unique.
resource "random_string" "kv_suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_key_vault" "main" {
  name                       = "kv-aum-${random_string.kv_suffix.result}"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  enable_rbac_authorization  = true # REQUIRED - otherwise role assignments are ignored
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

# Grant whoever ran `az login` permission to write secrets.
resource "azurerm_role_assignment" "kv_deployer" {
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# depends_on only orders creation - it does not wait for RBAC to propagate.
# A short pause avoids the 403 on the first secret write.
resource "time_sleep" "rbac_propagation" {
  create_duration = "60s"
  depends_on      = [azurerm_role_assignment.kv_deployer]
}

resource "azurerm_key_vault_secret" "admin_password" {
  name         = "vm-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.main.id
  depends_on   = [time_sleep.rbac_propagation]
}

output "key_vault_name" { value = azurerm_key_vault.main.name }
output "key_vault_id" { value = azurerm_key_vault.main.id }
