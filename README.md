# Description

Spins up a BitBucket Data Center GKE cluster in GCP using the official BitBuckeet Data Center helm chart: https://atlassian.github.io/data-center-helm-charts/

## Install Terraform

```
tfenv install 1.14.4
tfenv use 1.14.4
```

## Create a workspace

Initialize working directory:
```
terraform init
```

This project uses Terraform workspaces. Create a new workspace:
```
terraform workspace new <<YOUR_NAME>>-bitbucket-01
```

## Create tfvars file

Make a copy of `example.tfvars` and name it `<<WORKSPACE_NAME>>.tfvars`:

```
cp example.tfvars name-bitbucket-01.tfvars
```

Update variables for your Replicated VM instance.

## Terraform plan

```
terraform plan -var-file=<<WORKSPACE_NAME>>.tfvars -out <<WORKSPACE_NAME>>.out
```

## Terraform apply

```
terraform apply <<WORKSPACE_NAME>>.out
```