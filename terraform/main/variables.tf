variable "agent_name" {
  description = "Agent name used to name Terraform resources"
  type        = string
  nullable    = true
  default     = null
}

variable "project" {
  description = "Google Cloud project ID"
  type        = string
  nullable    = true
  default     = null
}

variable "location" {
  description = "Google Cloud location (Compute region)"
  type        = string
  nullable    = true
  default     = null
}

variable "app_iam_roles" {
  description = "Service account project IAM policy roles"
  type        = set(string)
  default = [
    "roles/aiplatform.user",
    "roles/logging.logWriter",
    "roles/cloudtrace.agent",
    "roles/telemetry.tracesWriter",
    "roles/serviceusage.serviceUsageConsumer",
  ]
}

variable "model" {
  description = "Vertex AI model name"
  type        = string
  nullable    = true
  default     = null
}

variable "docker_image" {
  description = "Docker image to deploy to Cloud Run"
  type        = string
  nullable    = true
  default     = null
}
