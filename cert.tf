# Private key for ACME account registration
resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "acme_registration" "reg" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = var.acme_email
}

resource "acme_certificate" "cert" {
  account_key_pem           = acme_registration.reg.account_key_pem
  common_name               = trimsuffix(var.dns_name, ".")
  subject_alternative_names = []

  dns_challenge {
    provider = "gcloud"
    config = {
      GCE_PROJECT             = var.project_id
      GCE_PROPAGATION_TIMEOUT = "300"
    }
  }

  depends_on = [
    google_dns_record_set.bitbucket,
  ]
}

resource "google_certificate_manager_certificate" "default" {
  name = "${var.cluster_name}-letsencrypt-cert"
  self_managed {
    # Include full chain: leaf certificate + intermediate
    pem_certificate = "${acme_certificate.cert.certificate_pem}${acme_certificate.cert.issuer_pem}"
    pem_private_key = acme_certificate.cert.private_key_pem
  }
}

# Certificate Map for Let's Encrypt certificate
resource "google_certificate_manager_certificate_map" "bitbucket" {
  name        = var.cluster_name
  description = "Certificate map for Bitbucket (Let's Encrypt)"
}

# Certificate Map Entry to associate Let's Encrypt certificate with the map
resource "google_certificate_manager_certificate_map_entry" "bitbucket" {
  name         = var.cluster_name
  description  = "Certificate map entry for Bitbucket domain (Let's Encrypt)"
  map          = google_certificate_manager_certificate_map.bitbucket.name
  certificates = [google_certificate_manager_certificate.default.id]
  hostname     = local.bitbucket_domain
}
