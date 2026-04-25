terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "7.17.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.36"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = ">= 1.14.0"
    }
    acme = {
      source  = "vancluever/acme"
      version = "2.43.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.5"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone

  default_labels = merge(var.default_labels, {
    "name" = var.cluster_name
  })
}

data "google_client_config" "default" {}

provider "acme" {
  server_url = var.acme_server
}

provider "kubernetes" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = "https://${google_container_cluster.primary.endpoint}"
    token                  = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = "https://${google_container_cluster.primary.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(google_container_cluster.primary.master_auth[0].cluster_ca_certificate)
  load_config_file       = false
}

# Local to get domain without trailing dot, and product-specific service port
locals {
  app_domain = trimsuffix(var.dns_name, ".")

  default_service_ports = {
    jira       = 8080
    confluence = 8090
    bitbucket  = 7990
    crowd      = 8095
    bamboo     = 8085
  }
  service_port = var.service_port != null ? var.service_port : lookup(local.default_service_ports, var.product, 8080)
}

resource "google_compute_network" "vpc_network" {
  name                    = var.cluster_name
  auto_create_subnetworks = true
}

# Static IP for Ingress
resource "google_compute_global_address" "app_ip" {
  name = "${var.cluster_name}-ip"
}

# DNS Record
resource "google_dns_record_set" "app" {
  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = var.dns_name
  type         = "A"
  ttl          = 300
  rrdatas      = [google_compute_global_address.app_ip.address]
}
