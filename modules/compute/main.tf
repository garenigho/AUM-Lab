variable "location" { type = string }
variable "resource_group_name" { type = string }
variable "subnet_id" { type = string }
variable "admin_username" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "domain_name" { type = string }
variable "domain_netbios" { type = string }

locals {
  vm_size = "Standard_E2bds_v5"
  img = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }
  # Escape single quotes so the password is safe inside PowerShell '...' strings.
  pw_ps = replace(var.admin_password, "'", "''")
}

# ---------- Public IPs ----------
resource "azurerm_public_ip" "dc01" {
  name                = "pip-dc01"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "ws01" {
  name                = "pip-ws01"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_public_ip" "ws02" {
  name                = "pip-ws02"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
}

# ---------- NICs ----------
# All static. If WS01/WS02 were Dynamic, one could grab 10.0.1.4 (the first
# usable address) before DC01's NIC is created and DC01 would fail.
resource "azurerm_network_interface" "dc01" {
  name                = "nic-dc01"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.4"
    public_ip_address_id          = azurerm_public_ip.dc01.id
  }
}

resource "azurerm_network_interface" "ws01" {
  name                = "nic-ws01"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.5"
    public_ip_address_id          = azurerm_public_ip.ws01.id
  }
}

resource "azurerm_network_interface" "ws02" {
  name                = "nic-ws02"
  location            = var.location
  resource_group_name = var.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.6"
    public_ip_address_id          = azurerm_public_ip.ws02.id
  }
}

# ---------- VMs ----------
# patch_mode = AutomaticByPlatform + bypass_platform_safety_checks... are REQUIRED
# for a VM to be patched by a customer-managed maintenance schedule.
# patch_assessment_mode = AutomaticByPlatform enables periodic (24h) assessment;
# it is set here too so Terraform doesn't fight the Azure Policy that also sets it.
resource "azurerm_windows_virtual_machine" "dc01" {
  name                  = "DC01"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = local.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc01.id]

  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.img.publisher
    offer     = local.img.offer
    sku       = local.img.sku
    version   = local.img.version
  }
}

resource "azurerm_windows_virtual_machine" "ws01" {
  name                  = "WS01"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = local.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.ws01.id]

  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.img.publisher
    offer     = local.img.offer
    sku       = local.img.sku
    version   = local.img.version
  }
}

resource "azurerm_windows_virtual_machine" "ws02" {
  name                  = "WS02"
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = local.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.ws02.id]

  patch_mode                                             = "AutomaticByPlatform"
  patch_assessment_mode                                  = "AutomaticByPlatform"
  bypass_platform_safety_checks_on_user_schedule_enabled = true

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = local.img.publisher
    offer     = local.img.offer
    sku       = local.img.sku
    version   = local.img.version
  }
}

# ---------- DC promotion ----------
# Scripts are passed as -EncodedCommand (base64 UTF-16LE) so quotes/symbols in
# the password can't break the command line, and via protected_settings so the
# password is encrypted and not visible in the portal.
# -NoRebootOnCompletion + delayed restart lets the extension report success
# BEFORE the VM reboots (otherwise the extension can hang or report failure).
locals {
  dc_script = <<-EOT
    $ErrorActionPreference = 'Stop'
    Install-WindowsFeature AD-Domain-Services -IncludeManagementTools
    Import-Module ADDSDeployment
    $dsrm = ConvertTo-SecureString '${local.pw_ps}' -AsPlainText -Force
    Install-ADDSForest -DomainName '${var.domain_name}' -DomainNetbiosName '${var.domain_netbios}' -SafeModeAdministratorPassword $dsrm -InstallDns -NoRebootOnCompletion -Force
    shutdown.exe /r /t 60 /c "Completing DC promotion"
    exit 0
  EOT

  join_script = <<-EOT
    $ErrorActionPreference = 'Stop'
    $nic = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
    Set-DnsClientServerAddress -InterfaceIndex $nic.InterfaceIndex -ServerAddresses '10.0.1.4'
    $user = '${var.domain_netbios}\${var.admin_username}'
    $cred = New-Object System.Management.Automation.PSCredential($user, (ConvertTo-SecureString '${local.pw_ps}' -AsPlainText -Force))
    # DC01 restarts ~60s after promotion - give it time, then retry for up to ~20 min.
    Start-Sleep -Seconds 120
    for ($i = 1; $i -le 40; $i++) {
      try {
        Clear-DnsClientCache
        Resolve-DnsName '${var.domain_name}' -ErrorAction Stop | Out-Null
        Add-Computer -DomainName '${var.domain_name}' -Credential $cred -Force -ErrorAction Stop
        shutdown.exe /r /t 30 /c "Completing domain join"
        exit 0
      } catch {
        Write-Output "Attempt $i failed: $($_.Exception.Message)"
        Start-Sleep -Seconds 30
      }
    }
    exit 1
  EOT

  dc_cmd   = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(local.dc_script, "UTF-16LE")}"
  join_cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(local.join_script, "UTF-16LE")}"
}

resource "azurerm_virtual_machine_extension" "setup_dc" {
  name                 = "SetupDC"
  virtual_machine_id   = azurerm_windows_virtual_machine.dc01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  protected_settings   = jsonencode({ commandToExecute = local.dc_cmd })

  timeouts {
    create = "60m"
  }
}

# depends_on: WS01/WS02 cannot start joining until DC01 promotion has succeeded.
resource "azurerm_virtual_machine_extension" "join_ws01" {
  name                 = "JoinDomain"
  virtual_machine_id   = azurerm_windows_virtual_machine.ws01.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  protected_settings   = jsonencode({ commandToExecute = local.join_cmd })
  depends_on           = [azurerm_virtual_machine_extension.setup_dc]

  timeouts {
    create = "60m"
  }
}

resource "azurerm_virtual_machine_extension" "join_ws02" {
  name                 = "JoinDomain"
  virtual_machine_id   = azurerm_windows_virtual_machine.ws02.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  protected_settings   = jsonencode({ commandToExecute = local.join_cmd })
  depends_on           = [azurerm_virtual_machine_extension.setup_dc]

  timeouts {
    create = "60m"
  }
}

output "dc01_id" { value = azurerm_windows_virtual_machine.dc01.id }
output "ws01_id" { value = azurerm_windows_virtual_machine.ws01.id }
output "ws02_id" { value = azurerm_windows_virtual_machine.ws02.id }
output "dc01_public_ip" { value = azurerm_public_ip.dc01.ip_address }
output "ws01_public_ip" { value = azurerm_public_ip.ws01.ip_address }
output "ws02_public_ip" { value = azurerm_public_ip.ws02.ip_address }
