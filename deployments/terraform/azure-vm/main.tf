terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

variable "location" {
  type        = string
  description = "Azure region"
  default     = "eastus"
}

variable "resource_group_name" {
  type        = string
  description = "Resource group name"
  default     = "plane-rg"
}

variable "name_prefix" {
  type        = string
  description = "Prefix used for resource names"
  default     = "plane"
}

variable "admin_username" {
  type        = string
  description = "Admin username for the VM"
  default     = "azureuser"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key contents (e.g. ~/.ssh/id_ed25519.pub)"
}

variable "ssh_allowed_cidr" {
  type        = string
  description = "CIDR allowed to SSH (port 22)"
  default     = "0.0.0.0/0"
}

variable "app_domain" {
  type        = string
  description = "Public domain name for Plane (DNS A-record should point to the VM public IP). Can also be an IP for initial bring-up."
}

variable "cert_email" {
  type        = string
  description = "Email used for Let's Encrypt (optional; empty disables ACME email)."
  default     = ""
}

variable "app_release" {
  type        = string
  description = "Plane docker image release tag"
  default     = "stable"
}

variable "vm_size" {
  type        = string
  description = "Azure VM size"
  default     = "Standard_B2ms"
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB"
  default     = 64
}

variable "data_disk_size_gb" {
  type        = number
  description = "Data disk size in GB (Plane state)"
  default     = 256
}

variable "data_disk_sku" {
  type        = string
  description = "Managed disk SKU for data disk (e.g. StandardSSD_LRS, Premium_LRS)"
  default     = "StandardSSD_LRS"
}

variable "prevent_destroy_data_disk" {
  type        = bool
  description = "If true, Terraform will refuse to destroy the data disk (safety rail to avoid accidental data loss)."
  default     = true
}

resource "azurerm_resource_group" "rg" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.name_prefix}-vnet"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  address_space       = ["10.42.0.0/16"]
}

resource "azurerm_subnet" "subnet" {
  name                 = "${var.name_prefix}-subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.42.1.0/24"]
}

resource "azurerm_network_security_group" "nsg" {
  name                = "${var.name_prefix}-nsg"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.ssh_allowed_cidr
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTPS"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_public_ip" "pip" {
  name                = "${var.name_prefix}-pip"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nic" {
  name                = "${var.name_prefix}-nic"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

resource "azurerm_network_interface_security_group_association" "nic_nsg" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

resource "random_password" "postgres_password" {
  length  = 32
  special = false
}

resource "random_password" "rabbitmq_password" {
  length  = 32
  special = false
}

resource "random_password" "django_secret_key" {
  length  = 50
  special = false
}

resource "random_password" "live_server_secret_key" {
  length  = 50
  special = false
}

resource "random_password" "minio_access_key" {
  length  = 20
  special = false
}

resource "random_password" "minio_secret_key" {
  length  = 40
  special = false
}

locals {
  database_url = "postgresql://plane:${random_password.postgres_password.result}@plane-db:5432/plane"
  amqp_url     = "amqp://plane:${random_password.rabbitmq_password.result}@plane-mq:5672/plane"

  web_url              = "https://${var.app_domain}"
  cors_allowed_origins = "https://${var.app_domain},http://${var.app_domain}"

  cloud_init = <<-CLOUDINIT
    #cloud-config
    package_update: true
    package_upgrade: true

    write_files:
      - path: /opt/plane/docker-compose.yml
        permissions: "0644"
        owner: root:root
        content: |
          services:
            web:
              image: artifacts.plane.so/makeplane/plane-frontend:${var.app_release}
              restart: unless-stopped
              depends_on:
                - api
                - worker

            space:
              image: artifacts.plane.so/makeplane/plane-space:${var.app_release}
              restart: unless-stopped
              depends_on:
                - api
                - worker
                - web

            admin:
              image: artifacts.plane.so/makeplane/plane-admin:${var.app_release}
              restart: unless-stopped
              depends_on:
                - api
                - web

            live:
              image: artifacts.plane.so/makeplane/plane-live:${var.app_release}
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              depends_on:
                - api
                - web

            api:
              image: artifacts.plane.so/makeplane/plane-backend:${var.app_release}
              command: ./bin/docker-entrypoint-api.sh
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              volumes:
                - /data/plane/logs/api:/code/plane/logs
              depends_on:
                - plane-db
                - plane-redis
                - plane-mq
                - plane-minio

            worker:
              image: artifacts.plane.so/makeplane/plane-backend:${var.app_release}
              command: ./bin/docker-entrypoint-worker.sh
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              volumes:
                - /data/plane/logs/worker:/code/plane/logs
              depends_on:
                - api
                - plane-db
                - plane-redis
                - plane-mq
                - plane-minio

            beat-worker:
              image: artifacts.plane.so/makeplane/plane-backend:${var.app_release}
              command: ./bin/docker-entrypoint-beat.sh
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              volumes:
                - /data/plane/logs/beat-worker:/code/plane/logs
              depends_on:
                - api
                - plane-db
                - plane-redis
                - plane-mq
                - plane-minio

            migrator:
              image: artifacts.plane.so/makeplane/plane-backend:${var.app_release}
              command: ./bin/docker-entrypoint-migrator.sh
              restart: on-failure
              env_file:
                - /opt/plane/.env
              volumes:
                - /data/plane/logs/migrator:/code/plane/logs
              depends_on:
                - plane-db
                - plane-redis

            plane-db:
              image: postgres:15.7-alpine
              command: postgres -c 'max_connections=1000'
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              volumes:
                - /data/plane/postgres:/var/lib/postgresql/data

            plane-redis:
              image: valkey/valkey:7.2.11-alpine
              restart: unless-stopped
              volumes:
                - /data/plane/redis:/data

            plane-mq:
              image: rabbitmq:3.13.6-management-alpine
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              volumes:
                - /data/plane/rabbitmq:/var/lib/rabbitmq

            plane-minio:
              image: minio/minio:latest
              command: server /export --console-address ":9090"
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              volumes:
                - /data/plane/minio:/export

            proxy:
              image: artifacts.plane.so/makeplane/plane-proxy:${var.app_release}
              restart: unless-stopped
              env_file:
                - /opt/plane/.env
              ports:
                - "80:80"
                - "443:443"
              volumes:
                - /data/plane/proxy_config:/config
                - /data/plane/proxy_data:/data
              depends_on:
                - web
                - api
                - space
                - admin
                - live

      - path: /opt/plane/.env
        permissions: "0600"
        owner: root:root
        content: |
          APP_RELEASE=${var.app_release}
          APP_DOMAIN=${var.app_domain}
          WEB_URL=${local.web_url}
          CORS_ALLOWED_ORIGINS=${local.cors_allowed_origins}
          DEBUG=0
          GUNICORN_WORKERS=1
          USE_MINIO=1
          FILE_SIZE_LIMIT=5242880
          MINIO_ENDPOINT_SSL=0
          API_KEY_RATE_LIMIT=60/minute

          POSTGRES_USER=plane
          POSTGRES_PASSWORD=${random_password.postgres_password.result}
          POSTGRES_DB=plane
          POSTGRES_PORT=5432
          PGHOST=plane-db
          PGDATABASE=plane
          PGDATA=/var/lib/postgresql/data
          DATABASE_URL=${local.database_url}

          REDIS_URL=redis://plane-redis:6379/
          REDIS_HOST=plane-redis
          REDIS_PORT=6379

          RABBITMQ_DEFAULT_USER=plane
          RABBITMQ_DEFAULT_PASS=${random_password.rabbitmq_password.result}
          RABBITMQ_DEFAULT_VHOST=plane
          RABBITMQ_HOST=plane-mq
          RABBITMQ_PORT=5672
          AMQP_URL=${local.amqp_url}

          AWS_REGION=
          AWS_ACCESS_KEY_ID=${random_password.minio_access_key.result}
          AWS_SECRET_ACCESS_KEY=${random_password.minio_secret_key.result}
          AWS_S3_ENDPOINT_URL=http://plane-minio:9000
          AWS_S3_BUCKET_NAME=uploads

          MINIO_ROOT_USER=${random_password.minio_access_key.result}
          MINIO_ROOT_PASSWORD=${random_password.minio_secret_key.result}

          SECRET_KEY=${random_password.django_secret_key.result}
          LIVE_SERVER_SECRET_KEY=${random_password.live_server_secret_key.result}
          API_BASE_URL=http://api:8000

          LISTEN_HTTP_PORT=80
          LISTEN_HTTPS_PORT=443
          SITE_ADDRESS=:80
          CERT_EMAIL=${var.cert_email}
          CERT_ACME_CA=https://acme-v02.api.letsencrypt.org/directory
          CERT_ACME_DNS=

    runcmd:
      - |
        set -euo pipefail

        # Install Docker
        if ! command -v docker >/dev/null 2>&1; then
          curl -fsSL https://get.docker.com | sh
        fi

        # Attach/mount data disk (idempotent). The data disk attachment can race VM boot.
        DISK_DEV=""
        for i in $(seq 1 60); do
          if [ -e /dev/disk/azure/scsi1/lun0 ]; then
            DISK_DEV=$(readlink -f /dev/disk/azure/scsi1/lun0)
            break
          fi

          if [ -e /dev/sdc ]; then
            DISK_DEV=/dev/sdc
            break
          fi

          sleep 2
        done

        if [ -z "$DISK_DEV" ] || [ ! -e "$DISK_DEV" ]; then
          echo "Data disk device not found; cannot mount /data" >&2
          exit 1
        fi

        mkdir -p /data

        if ! blkid "$DISK_DEV" >/dev/null 2>&1; then
          mkfs.ext4 -F "$DISK_DEV"
        fi

        UUID=$(blkid -s UUID -o value "$DISK_DEV")
        if ! grep -q "$UUID" /etc/fstab; then
          echo "UUID=$UUID /data ext4 defaults,nofail 0 2" >> /etc/fstab
        fi

        mount -a

        mkdir -p /data/plane/{postgres,redis,rabbitmq,minio,proxy_config,proxy_data,logs/api,logs/worker,logs/beat-worker,logs/migrator}
        chmod 700 /opt/plane

        # Start Plane
        docker compose -f /opt/plane/docker-compose.yml --env-file /opt/plane/.env up -d

  CLOUDINIT
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.name_prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username

  network_interface_ids = [azurerm_network_interface.nic.id]

  admin_ssh_key {
    username   = var.admin_username
    public_key = var.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = var.os_disk_size_gb
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  disable_password_authentication = true

  custom_data = base64encode(local.cloud_init)
}

resource "azurerm_managed_disk" "data" {
  name                 = "${var.name_prefix}-data"
  location             = azurerm_resource_group.rg.location
  resource_group_name  = azurerm_resource_group.rg.name
  storage_account_type = var.data_disk_sku
  create_option        = "Empty"
  disk_size_gb         = var.data_disk_size_gb

  lifecycle {
    prevent_destroy = var.prevent_destroy_data_disk
  }
}

resource "azurerm_virtual_machine_data_disk_attachment" "attach" {
  managed_disk_id    = azurerm_managed_disk.data.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm.id
  lun                = 0
  caching            = "ReadWrite"
}

output "public_ip" {
  value = azurerm_public_ip.pip.ip_address
}

output "plane_url" {
  value = "https://${var.app_domain}"
}
