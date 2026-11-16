terraform {
  backend "azurerm" {
    resource_group_name  = "RG-TerraformState"
    storage_account_name =  "tfstategaren1115"
    container_name       = "tfstate"
    key                  = "aum-lab.tfstate"
    # Separate from the Lab 1 / Lab 2 state keys - all labs can share one container.
  }
}
