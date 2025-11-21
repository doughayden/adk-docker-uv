output "project" {
  description = "Project ID"
  value       = local.project
}

output "location" {
  description = "Google Cloud location (Compute region)"
  value       = local.location
}

output "service_account_email" {
  description = "GCE instance service account email"
  value       = google_service_account.app.email
}

output "service_account_roles" {
  description = "Service account project IAM policy roles"
  value       = [for role in var.app_iam_roles : role]
}

output "cloud_run_services" {
  description = "Cloud Run service details per location"
  value = { for loc, svc in google_cloud_run_v2_service.app :
    loc => {
      latest_ready_revision = split("revisions/", svc.latest_ready_revision)[1]
      update_time           = svc.update_time
      uri                   = svc.uri
    }
  }
}

output "deployed_image" {
  description = "Deployed Docker image URI"
  value       = local.docker_image
}
