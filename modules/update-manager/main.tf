variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "resource_group_id" { type = string }
variable "patch_window_start" { type = string }
variable "dc01_id" { type = string }
variable "ws01_id" { type = string }
variable "ws02_id" { type = string }

# ---------- 1. ENROLLMENT: Azure Policy ----------
# Built-in "Configure periodic checking for missing system updates on azure virtual machines".
# It uses the Modify effect, so the assignment MUST have a managed identity
# (and a location), plus a role that lets it change VMs during remediation.
# Assessment only - it never installs patches.
resource "azurerm_resource_group_policy_assignment" "aum_assessment" {
  name                 = "aum-periodic-assessment"
  display_name         = "AUM Lab - periodic assessment for missing updates"
  resource_group_id    = var.resource_group_id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/59efceea-0c96-497e-a4a1-4eb2290dac15"
  location             = var.location

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_role_assignment" "policy_vm_contributor" {
  scope                = var.resource_group_id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = azurerm_resource_group_policy_assignment.aum_assessment.identity[0].principal_id
}

# ---------- 2. SCHEDULE: Maintenance Configuration ----------
# scope InGuestPatch       = patches installed inside the guest OS
# in_guest_user_patch_mode = User -> customer-managed schedule
# Only Critical, Security, UpdateRollup; reboot only if a patch needs it.
resource "azurerm_maintenance_configuration" "weekly" {
  name                     = "aum-weekly-patches"
  resource_group_name      = var.resource_group_name
  location                 = var.location
  scope                    = "InGuestPatch"
  in_guest_user_patch_mode = "User"

  window {
    start_date_time = var.patch_window_start
    time_zone       = "Eastern Standard Time"
    duration        = "03:00"
    recur_every     = "1Week Sunday"
  }

  install_patches {
    reboot = "IfRequired"
    windows {
      classifications_to_include = ["Critical", "Security", "UpdateRollup"]
    }
  }
}

# ---------- 3. TARGETING: Maintenance Assignments ----------
# Without these, VMs are assessed but never patched on the schedule.
resource "azurerm_maintenance_assignment_virtual_machine" "dc01" {
  location                     = var.location
  maintenance_configuration_id = azurerm_maintenance_configuration.weekly.id
  virtual_machine_id           = var.dc01_id
}

resource "azurerm_maintenance_assignment_virtual_machine" "ws01" {
  location                     = var.location
  maintenance_configuration_id = azurerm_maintenance_configuration.weekly.id
  virtual_machine_id           = var.ws01_id
}

resource "azurerm_maintenance_assignment_virtual_machine" "ws02" {
  location                     = var.location
  maintenance_configuration_id = azurerm_maintenance_configuration.weekly.id
  virtual_machine_id           = var.ws02_id
}
