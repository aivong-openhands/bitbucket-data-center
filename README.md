# Atlassian Data Center on GKE

Deploys an Atlassian Data Center product (Jira, Confluence, Bitbucket, Crowd, or Bamboo) on a GKE cluster in GCP using the [official Atlassian Data Center Helm charts](https://atlassian.github.io/data-center-helm-charts/).

**What Terraform creates:**
- VPC network
- GKE cluster with a managed node pool
- Cloud SQL (PostgreSQL) instance via private VPC peering
- Global static IP and Cloud DNS A record
- Let's Encrypt TLS certificate via ACME + GCP Certificate Manager
- GKE Ingress with HTTPS forwarding rule and HTTP→HTTPS redirect
- Atlassian product deployed via Helm


## Prerequisites

- GCP project with billing enabled
- Cloud DNS managed zone
- `gcloud` authenticated with sufficient permissions
- `tfenv` or Terraform 1.14.4


## Terraform

### Install Terraform

```
tfenv install 1.14.4
tfenv use 1.14.4
```

### Initialize

```
terraform init
```

### Create a workspace

```
terraform workspace new <YOUR_NAME>-<PRODUCT>-01
```

### Create a tfvars file

Copy the example and fill in your values:

```
cp tfvars.example <WORKSPACE_NAME>.tfvars
```

Required variables:

| Variable | Description | Example |
|---|---|---|
| `cluster_name` | GKE cluster name (also used as VPC name) | `myname-jira-01` |
| `product` | Atlassian product (`jira`, `confluence`, `bitbucket`, `crowd`, `bamboo`) | `jira` |
| `dns_name` | FQDN for the product (trailing dot required) | `jira.example.com.` |
| `dns_zone_name` | Cloud DNS managed zone name | `example-com-zone` |
| `acme_email` | Email for Let's Encrypt registration | `you@example.com` |

See `tfvars.example` and `variables.tf` for all available options.

### Plan and apply

```
terraform plan -var-file=<WORKSPACE_NAME>.tfvars -out <WORKSPACE_NAME>.out
terraform apply <WORKSPACE_NAME>.out
```

After apply, Terraform outputs the `app_url` where the product is accessible.
