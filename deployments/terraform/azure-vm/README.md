# Plane on Azure VM (Terraform)

## Prereqs

- Terraform `>= 1.6`
- Azure CLI logged in (`az login`) and access to the target subscription
- A domain name (recommended) with DNS you can edit
- An SSH keypair

## What this deploys

- Ubuntu VM + VNet/Subnet/NSG + Static Public IP
- Managed data disk mounted at `/data` (guarded by `prevent_destroy_data_disk=true`)
- Docker + Plane docker-compose stack
- Azure Blob storage + a nightly **systemd timer** that backs up:
  - MinIO data (uploads) to Blob (enabled by default)
  - Postgres dump **only if** `use_external_postgres=false`

## Required manual steps

1. **DNS**

- Create an `A` record:
  - `plane.yourdomain.com` -> (Terraform output) `public_ip`

2. **Managed Postgres (recommended)**

If you want to use your existing Azure Postgres:

- Create a database named `plane` on your server
- Ensure the VM can connect to the server (firewall / private networking)
- Use a connection string like:

```text
postgresql://<user>:<pass>@<fqdn>:5432/plane?sslmode=require
```

## Configure

Create `terraform.tfvars` in this folder:

```hcl
location            = "eastus"
resource_group_name = "plane-rg"
name_prefix         = "plane"

admin_username = "azureuser"
ssh_public_key = "ssh-ed25519 AAAA..."
ssh_allowed_cidr = "YOUR.PUBLIC.IP/32"

app_domain = "plane.yourdomain.com"
cert_email = "you@yourdomain.com" # optional but recommended

# Use existing Azure Postgres
use_external_postgres = true
external_database_url = "postgresql://..."
```

Optional:

- `vm_size` (default `Standard_B2ms`)
- `data_disk_size_gb` (default `256`)
- `backup_include_minio` (default `true`)
- `backup_systemd_on_calendar` (default `*-*-* 03:30:00`)

## Deploy

From this folder:

```bash
terraform init
terraform apply
```

Then open:

- `https://<app_domain>`

## Verify backups

SSH into the VM and run:

```bash
systemctl status plane-backup.timer
systemctl start plane-backup.service
journalctl -u plane-backup.service -n 200 --no-pager
```

Backups are uploaded to the private Blob container:

- `plane-backups/minio/` (uploads)
- `plane-backups/postgres/` (only when using local Postgres)

## Notes

- This uses **VM Managed Identity** + RBAC for Blob uploads. No Blob keys/SAS required.
- Terraform state contains generated secrets; treat `terraform.tfstate` as sensitive.
