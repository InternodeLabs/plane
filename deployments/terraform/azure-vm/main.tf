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

variable "use_external_postgres" {
  type        = bool
  description = "If true, do not run the local postgres container and instead use external_database_url."
  default     = false
}

variable "external_database_url" {
  type        = string
  description = "External DATABASE_URL (e.g. Azure Database for PostgreSQL). Recommended to include sslmode=require."
  default     = ""
  sensitive   = true
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

variable "backup_retention_days" {
  type        = number
  description = "How many days to keep local backup artifacts on the VM before deletion."
  default     = 14
}

variable "backup_include_minio" {
  type        = bool
  description = "If true, also back up the MinIO data directory (uploads)."
  default     = true
}

variable "backup_systemd_on_calendar" {
  type        = string
  description = "systemd OnCalendar schedule for backups (UTC unless you also set system timezone)."
  default     = "*-*-* 03:30:00"
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

resource "random_string" "storage_suffix" {
  length  = 6
  upper   = false
  lower   = true
  numeric = true
  special = false
}

resource "azurerm_storage_account" "backup" {
  name                     = "${var.name_prefix}${random_string.storage_suffix.result}"
  resource_group_name      = azurerm_resource_group.rg.name
  location                 = azurerm_resource_group.rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false

  blob_properties {
    versioning_enabled = true
  }
}

resource "azurerm_storage_container" "backup" {
  name                  = "plane-backups"
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

locals {
  database_url = var.use_external_postgres ? var.external_database_url : "postgresql://plane:${random_password.postgres_password.result}@plane-db:5432/plane"
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

      - path: /opt/plane/docker-compose.external-db.yml
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
                - plane-redis

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

      - path: /usr/local/bin/plane-backup.sh
        permissions: "0750"
        owner: root:root
        content: |
          #!/usr/bin/env bash
          set -euo pipefail

          BACKUP_ROOT="/data/plane/backups"
          PG_DIR="$BACKUP_ROOT/postgres"
          MINIO_DIR="$BACKUP_ROOT/minio"

          mkdir -p "$PG_DIR" "$MINIO_DIR"

          TS="$(date -u +%Y%m%dT%H%M%SZ)"

          PG_FILE=""
          if [[ "${BACKUP_INCLUDE_POSTGRES}" == "1" ]]; then
            PG_FILE="$PG_DIR/plane-postgres-${TS}.sql.gz"
            echo "[$(date -u +%FT%TZ)] Starting Postgres backup -> $PG_FILE"
            docker compose -f /opt/plane/docker-compose.yml --env-file /opt/plane/.env exec -T plane-db \
              sh -lc 'pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB"' | gzip -c > "$PG_FILE"
          fi

          MINIO_FILE=""
          if [[ "${BACKUP_INCLUDE_MINIO}" == "1" ]]; then
            MINIO_FILE="$MINIO_DIR/plane-minio-${TS}.tar.gz"
            echo "[$(date -u +%FT%TZ)] Starting MinIO backup -> $MINIO_FILE"
            tar -C /data/plane -czf "$MINIO_FILE" minio
          fi

          if ! command -v azcopy >/dev/null 2>&1; then
            echo "azcopy not installed" >&2
            exit 1
          fi

          # Managed Identity login (idempotent)
          azcopy login --identity >/dev/null 2>&1 || true

          DEST_BASE="https://${azurerm_storage_account.backup.name}.blob.core.windows.net/${azurerm_storage_container.backup.name}"

          echo "[$(date -u +%FT%TZ)] Uploading $PG_FILE"
          if [[ -n "$PG_FILE" ]]; then
            azcopy copy "$PG_FILE" "$DEST_BASE/postgres/" --overwrite=true
          fi

          if [[ -n "$MINIO_FILE" ]]; then
            echo "[$(date -u +%FT%TZ)] Uploading $MINIO_FILE"
            azcopy copy "$MINIO_FILE" "$DEST_BASE/minio/" --overwrite=true
          fi

          # Local retention
          find "$BACKUP_ROOT" -type f -mtime +${var.backup_retention_days} -print -delete || true
          echo "[$(date -u +%FT%TZ)] Backup completed"

      - path: /etc/systemd/system/plane-backup.service
        permissions: "0644"
        owner: root:root
        content: |
          [Unit]
          Description=Plane backup (Postgres dump + optional MinIO archive)
          Wants=network-online.target
          After=network-online.target

          [Service]
          Type=oneshot
          Environment=BACKUP_INCLUDE_POSTGRES=${var.use_external_postgres ? 0 : 1}
          Environment=BACKUP_INCLUDE_MINIO=${var.backup_include_minio ? 1 : 0}
          ExecStart=/usr/local/bin/plane-backup.sh

      - path: /etc/systemd/system/plane-backup.timer
        permissions: "0644"
        owner: root:root
        content: |
          [Unit]
          Description=Run Plane backup nightly

          [Timer]
          OnCalendar=${var.backup_systemd_on_calendar}
          Persistent=true

          [Install]
          WantedBy=timers.target

    runcmd:
      - |
        set -euo pipefail

        # Install Docker
        if ! command -v docker >/dev/null 2>&1; then
          curl -fsSL https://get.docker.com | sh
        fi

        # Install azcopy
        if ! command -v azcopy >/dev/null 2>&1; then
          apt-get update -y
          apt-get install -y ca-certificates curl unzip
          tmpdir=$(mktemp -d)
          curl -fsSL https://aka.ms/downloadazcopy-v10-linux -o "$tmpdir/azcopy.tgz"
          tar -xzf "$tmpdir/azcopy.tgz" -C "$tmpdir"
          install -m 0755 "$tmpdir"/azcopy_linux_amd64_*/azcopy /usr/local/bin/azcopy
          rm -rf "$tmpdir"
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
        COMPOSE_FILE="/opt/plane/docker-compose.yml"
        if [[ "${var.use_external_postgres}" == "true" ]]; then
          COMPOSE_FILE="/opt/plane/docker-compose.external-db.yml"
        fi
        docker compose -f "$COMPOSE_FILE" --env-file /opt/plane/.env up -d

        systemctl daemon-reload
        systemctl enable --now plane-backup.timer

  CLOUDINIT
}

resource "azurerm_linux_virtual_machine" "vm" {
  name                = "${var.name_prefix}-vm"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = var.vm_size
  admin_username      = var.admin_username

  identity {
    type = "SystemAssigned"
  }

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

resource "azurerm_role_assignment" "vm_blob_contributor" {
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_linux_virtual_machine.vm.identity[0].principal_id
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
