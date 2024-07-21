terraform {
  required_version = "~>1.7.3"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.108.0"
    }
  }
}

provider "azurerm" {
  skip_provider_registration = true
  features {}

  subscription_id = var.provider_sp.subscription_id
  tenant_id       = var.provider_sp.tenant_id
  client_id       = var.provider_sp.client_id
  client_secret   = var.provider_sp.client_secret
}

resource "azurerm_resource_group" "rg" {
  name     = var.rg_name
  location = var.location

  tags = local.tags
}

resource "azurerm_network_security_group" "nsg" {
  name                = "aliyun-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "ssh"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow_outbound_internet"
    priority                   = 200
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "Internet"
  }

  security_rule {
    name                       = "allow_azure_cloud"
    priority                   = 300
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "AzureCloud"
  }

  depends_on = [
    azurerm_resource_group.rg
  ]

  tags = local.tags
}

resource "azurerm_virtual_network" "vnet" {
  name                = "aliyun-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.1.0.0/16"]

  depends_on = [
    azurerm_network_security_group.nsg
  ]

  tags = local.tags
}

resource "azurerm_subnet" "cluster-snet" {
  name                 = "aliyun-cluster-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = "aliyun-vnet"
  address_prefixes     = ["10.1.1.0/24"]

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

resource "azurerm_subnet" "jumpbox-snet" {
  name                 = "aliyun-jumpbox-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = "aliyun-vnet"
  address_prefixes     = ["10.1.2.0/24"]

  depends_on = [
    azurerm_virtual_network.vnet
  ]
}

resource "azurerm_subnet_network_security_group_association" "nsga1" {
  subnet_id                 = azurerm_subnet.jumpbox-snet.id
  network_security_group_id = azurerm_network_security_group.nsg.id

  depends_on = [
    azurerm_subnet.cluster-snet,
    azurerm_subnet.jumpbox-snet
  ]
}

resource "azurerm_subnet_network_security_group_association" "nsga2" {
  subnet_id                 = azurerm_subnet.cluster-snet.id
  network_security_group_id = azurerm_network_security_group.nsg.id

  depends_on = [
    azurerm_subnet.cluster-snet,
    azurerm_subnet.jumpbox-snet
  ]
}

resource "azurerm_kubernetes_cluster" "cluster" {
  name                = var.cluster_name
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  dns_prefix          = "aliyunaks"
  kubernetes_version  = "1.28.9"

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = var.workers_type
    os_disk_size_gb = 100
    vnet_subnet_id  = azurerm_subnet.cluster-snet.id
    node_labels = {
      "gpushare" : "true" # For Aliyun plugin DaemoSet to run on the workers
    }
  }
  identity {
    type = "SystemAssigned"
  }
  # If SkipGPUDriverInstall is set, nVidia driver must be manually installed
  tags = merge(local.tags, { "sku" = "gpu" })
  network_profile {
    network_plugin = "azure"
  }
  depends_on = [
    azurerm_subnet_network_security_group_association.nsga1,
    azurerm_subnet_network_security_group_association.nsga2
  ]
}

resource "azurerm_public_ip" "vmpip" {
  name                = "aliyun-pip"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  domain_name_label   = "aliyundnl"

  depends_on = [
    azurerm_kubernetes_cluster.cluster
  ]

  tags = local.tags
}

resource "azurerm_network_interface" "nic" {
  name                = "aliyun-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jumpbox-snet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vmpip.id
  }

  depends_on = [
    azurerm_public_ip.vmpip
  ]

  tags = local.tags
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "example-machine"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.nic.id
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/aliyun_rsa.pub")
  }

  connection {
    host        = self.public_ip_address
    user        = "adminuser"
    type        = "ssh"
    private_key = file("~/.ssh/aliyun_rsa")
    timeout     = "1m"
    agent       = false
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  identity {
    type = "SystemAssigned"
  }

  provisioner "file" {
    content     = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_key)
    destination = "/home/adminuser/client-key"
  }

  provisioner "file" {
    content     = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].client_certificate)
    destination = "/home/adminuser/client-certificate"
  }

  provisioner "file" {
    content     = base64decode(azurerm_kubernetes_cluster.cluster.kube_config[0].cluster_ca_certificate)
    destination = "/home/adminuser/certificate-authority"
  }

  provisioner "file" {
    content     = replace(templatefile("${path.module}/script.sh", {}), "\r\n", "\n")
    destination = "/home/adminuser/script.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "bash -i /home/adminuser/script.sh ${azurerm_kubernetes_cluster.cluster.name} ${azurerm_kubernetes_cluster.cluster.fqdn} ${nonsensitive(azurerm_kubernetes_cluster.cluster.kube_config[0].username)} ${nonsensitive(azurerm_kubernetes_cluster.cluster.kube_config[0].password)}"
    ]
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.nic
  ]

  tags = local.tags
}
