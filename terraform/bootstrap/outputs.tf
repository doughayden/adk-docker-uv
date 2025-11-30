output "project" {
  description = "Google Cloud project ID"
  value       = local.project
}

output "location" {
  description = "Google Cloud location (Compute region)"
  value       = local.location
}

output "agent_name" {
  description = "Agent name to identify cloud resources and logs"
  value       = local.agent_name
}

output "repository_full_name" {
  description = "Full GitHub repository name (owner/repo)"
  value       = "${local.repository_owner}/${local.repository_name}"
}

output "enabled_services" {
  description = "Enabled Google Cloud services"
  value       = [for service in google_project_service.main : service.service]
}

output "workload_identity_provider_name" {
  description = "GitHub Actions workload identity provider resource name"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "workload_identity_roles" {
  description = "GitHub Actions workload identity project IAM roles"
  value       = [for role in google_project_iam_member.github : role.role]
}

output "terraform_state_bucket" {
  description = "Terraform state GCS bucket name for main module"
  value       = google_storage_bucket.terraform_state.name
}

output "artifact_registry_repository_uri" {
  description = "Artifact Registry Docker repository URI"
  value       = google_artifact_registry_repository.cloud_run.registry_uri
}

output "github_repository_full_name" {
  description = "GitHub repository full name"
  value = "${local.repository_owner}/${local.repository_name}"
}

output "github_repository_id" {
  description = "GitHub repository ID"
  value = data.github_repository.agent.repo_id
}

output "github_variables_configured" {
  description = "GitHub repository variables configured"
  value = { for index, instance in github_actions_variable.variable :
    index => instance.value
  }
}
