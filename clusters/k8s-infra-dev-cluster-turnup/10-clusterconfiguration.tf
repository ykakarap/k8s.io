/*
This file defines:
- GCP Service Account for nodes
- GKE cluster configuration

Note that it does not configure any node pools; this is done in a separate file.
*/

// Create SA for nodes
resource "google_service_account" "cluster_node_sa" {
  project      = data.google_project.project.id
  account_id   = "sa-${var.cluster_name}"
  display_name = "Service Account for ${var.cluster_name}"
}

// Add roles for SA
resource "google_project_iam_member" "cluster_node_sa_logging" {
  project = data.google_project.project.id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cluster_node_sa.email}"
}
resource "google_project_iam_member" "cluster_node_sa_monitoring_viewer" {
  project = data.google_project.project.id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.cluster_node_sa.email}"
}
resource "google_project_iam_member" "cluster_node_sa_monitoring_metricwriter" {
  project = data.google_project.project.id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.cluster_node_sa.email}"
}

resource "google_bigquery_dataset" "usage_metering" {
  dataset_id  = "usage_metering_${var.cluster_name}"
  project     = data.google_project.project.id
  description = "GKE Usage Metering for ${var.cluster_name}"
  location    = "US"

  access {
    role          = "OWNER"
    special_group = "projectOwners"
  }
  access {
    role          = "WRITER"
    user_by_email = "${google_service_account.cluster_node_sa.email}"
  }
}

// Create GKE cluster, but with no node pools. Node pools can be provisioned below
resource "google_container_cluster" "cluster" {
  provider = google-beta

  name               = var.cluster_name
  project            = data.google_project.project.id
  location           = data.google_container_engine_versions.us-central1.location
  min_master_version = data.google_container_engine_versions.us-central1.latest_master_version

  // Start with a single node, because we're going to delete the default pool
  initial_node_count = 1

  // Removes the default node pool, so we can custom create them as separate
  // objects
  remove_default_node_pool = true

  // Disable local and certificate auth
  master_auth {
    username = ""
    password = ""

    client_certificate_config {
      issue_client_certificate = false
    }
  }

  // Enable Stackdriver Kubernetes Monitoring
  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  // Set maintenance time to 03:00 PST
  maintenance_policy {
    daily_maintenance_window {
      start_time = "11:00"
    }
  }

  // Restrict master to Google IP space; use Cloud Shell to access
  master_authorized_networks_config {
  }

  // Enable GKE Usage Metering
  resource_usage_export_config {
    enable_network_egress_metering = true
    bigquery_destination {
      dataset_id = google_bigquery_dataset.usage_metering.dataset_id
    }
  }

  // Enable GKE Network Policy
  network_policy {
    enabled = true
    provider = "CALICO"
  }

  // Configure cluster addons
  addons_config {
    network_policy_config {
      disabled = false
    }
  }

  // GKE clusters are critical objects and should not be destroyed
  lifecycle {
    prevent_destroy = true
  }
}
