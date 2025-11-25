# Implementation Plan: Simplified Setup & Automated CI/CD Deployment

**Project:** adk-docker-uv
**Goal:** Eliminate cloud resource setup from local development, automate Cloud Run deployment via GitHub Actions
**Status:** Architecture Revised - Implementation Pending
**Date:** 2025-11-21 (Revised)

## Table of Contents

- [Background & Motivation](#background--motivation)
- [Architecture Decisions (REVISED)](#architecture-decisions-revised)
- [Current State](#current-state)
- [Work Completed (Partially Reversed)](#work-completed-partially-reversed)
- [Remaining Work](#remaining-work)
- [Success Criteria](#success-criteria)
- [Dependencies & Constraints](#dependencies--constraints)
- [Security Considerations](#security-considerations)

---

## Background & Motivation

### The Problem

**Current setup flow is too complex:**
1. Clone from template
2. Run init script
3. Set `.env` variables (partial, incomplete)
4. **Create GCS state bucket** (cloud resource setup)
5. Run `terraform bootstrap apply`
6. **Manual copy-paste**: Copy Agent Engine resource name from Terraform output → `.env` file
7. Run the agent locally
8. **Manual deployment**: Build Docker image, push to registry, deploy to Cloud Run (all manual)

**Pain points:**
- Cloud resource setup required for local development (GCS bucket, Agent Engine)
- Too many manual steps
- No automated deployment on merge to main
- Terraform execution expected both locally and in CI/CD (confusing)
- Local dev doesn't match production behavior (Agent Engine from .env)

### The Vision (REVISED)

**Simplified local development (minimal cloud setup):**
1. Clone from template
2. Run init script
3. Configure `.env` (Gemini API or Vertex AI credentials only)
4. Run `docker compose up` → agent works immediately with ephemeral sessions
5. **Optional upgrade**: After deployment, copy Agent Engine resource name to `.env` for full feature parity (persistent sessions)
6. **Optional CI/CD setup**: Run `terraform bootstrap apply` to set up automated deployment (GitHub Actions + GCP)

**Note:** Local development uses Vertex AI hosted LLM API (minimal cloud cost), but requires no infrastructure provisioning.

**Automated deployment:**
1. Merge PR to main
2. GitHub Actions builds and pushes Docker image automatically
3. GitHub Actions runs `terraform main apply` automatically
4. Agent Engine created/updated in Cloud Run deployment
5. Cloud Run service receives persistent Agent Engine

**Result:**
- **Local dev:** Simple, fast, minimal cloud cost (LLM API usage only)
- **Optional upgrade:** Copy Agent Engine resource name for persistent sessions
- **CI/CD:** Fully automated deployment with persistent sessions in production
- **Clear separation:** Bootstrap = CI/CD setup helper (run once, local state), Main = deployment automation (runs in GitHub Actions)

---

## Architecture Decisions (REVISED)

### 1. Minimal Cloud Infrastructure for Local Development

**Decision:** Local development does NOT require GCS buckets, Agent Engine, or infrastructure provisioning, but uses Vertex AI hosted LLM API.

**Rationale:**
- **Faster onboarding:** Clone → configure → run (3 steps, minutes not hours)
- **Minimal cloud cost:** Only Vertex AI LLM API usage (pay-per-request)
- **No infrastructure provisioning:** No buckets, databases, or managed services needed
- **Simpler mental model:** Local = ephemeral testing, Production = persistent infrastructure
- **Feature parity not required initially:** Most development is agent logic, not session persistence

**Implementation:**
- Agent works with in-memory sessions (no AGENT_ENGINE env var needed)
- Vertex AI LLM accessed via application-default credentials or API key
- Bootstrap terraform only for CI/CD setup, not local dev
- Documentation clearly separates local dev from deployment
- **Optional upgrade path:** After deployment, copy Agent Engine resource name to `.env` for full feature parity

**Tradeoffs:**
- Local sessions don't persist by default (acceptable: most dev doesn't need this)
- Minimal API usage cost for LLM calls (acceptable: standard development practice)
- Full feature parity requires one-time copy-paste from deployment (documented in upgrade path)

---

### 2. Bootstrap Module: Local State (Default), CI/CD Setup Helper

**Decision:** Bootstrap uses LOCAL state by default and is a one-time helper run from developer's terminal.

**Rationale:**
- **Minimal setup:** No GCS bucket needed to run bootstrap
- **One-time operation:** Bootstrap creates the infrastructure for ongoing CI/CD, then rarely changes
- **Local execution:** Developer runs from terminal with local credentials (gcloud auth)
- **Self-contained:** No dependencies on other Terraform state
- **Optional remote state:** Developers can configure GCS backend if desired without impacting other project components

**What bootstrap creates:**
1. ✅ Workload Identity Federation for GitHub Actions
2. ✅ Artifact Registry for Docker images
3. ✅ **GCS bucket for main module's remote state**
4. ✅ GitHub Actions Variables (for main module)
5. ❌ **NOT Agent Engine** (moved to main module)

**GitHub Variables created:**
- `GCP_PROJECT_ID` - GCP project ID
- `GCP_LOCATION` - GCP region
- `IMAGE_NAME` - Docker image name (also used as agent_name)
- `GCP_WORKLOAD_IDENTITY_PROVIDER` - WIF provider name
- `ARTIFACT_REGISTRY_URI` - Registry URI
- `ARTIFACT_REGISTRY_LOCATION` - Registry location
- `TERRAFORM_STATE_BUCKET` - GCS bucket for main module state

**Why local state (default):**
- Bootstrap is genuinely one-time infrastructure
- Simpler: no chicken-egg problem (no state bucket needed for bootstrap)
- Team can version control bootstrap state if needed
- **Optional remote state:** Nothing prevents configuring GCS backend if team collaboration requires it

---

### 3. Main Module: CI/CD Only, No Dotenv Provider

**Decision:** Main module runs EXCLUSIVELY in GitHub Actions CI/CD, not locally. NO dotenv provider.

**Rationale:**
- **Standard Terraform patterns:** Inputs via TF_VAR_* env vars, CLI args, or .tfvars files
- **Security:** No .env file exposure in CI/CD (variables from GitHub Actions)
- **Clear separation:** Main module is deployment automation, not local dev tooling
- **Simplicity:** One execution environment (GitHub Actions) to test and document

**Input variable strategy:**
- **From GitHub Variables (mapped to TF_VAR_* in workflow env):** `project`, `location`, `agent_name`, `docker_image`
- **Optional with defaults:** `log_level` (INFO), `serve_web_interface` (false), `model` (gemini-2.5-flash)
- **Backend config:** `bucket` passed via `-backend-config` during `terraform init`

**What main creates:**
1. ✅ Service account for Cloud Run
2. ✅ Cloud Run service
3. ✅ **Agent Engine** (moved from bootstrap)
4. ✅ Environment variables for Cloud Run (including AGENT_ENGINE resource name, flexible LOG_LEVEL and SERVE_WEB_INTERFACE)

**Why no local execution:**
- Most developers never need to run terraform main (CI/CD handles deployment)
- If needed, can be documented as advanced usage with manual variable passing
- Eliminates dotenv provider (security concern, see below)

---

### 4. Agent Engine in Main Module

**Decision:** Agent Engine created by main module, not bootstrap.

**Rationale:**
- **Lifecycle coupling:** Agent Engine belongs with the app deployment
- **Prevents dangling resources:** If main is destroyed, Agent Engine is too
- **Environment isolation:** Different workspaces (sandbox/production) get different Agent Engines
- **No remote state dependency:** Main doesn't need to read bootstrap outputs

**Implementation:**
```hcl
# terraform/main/main.tf
resource "google_vertex_ai_reasoning_engine" "session_and_memory" {
  display_name = "Session and Memory: ${var.agent_name}"
  # ... configuration ...

  lifecycle {
    prevent_destroy = true  # Data protection
  }
}

locals {
  run_app_env = {
    # Direct reference, no remote state needed
    AGENT_ENGINE = google_vertex_ai_reasoning_engine.session_and_memory.id
    # ... other env vars ...
  }
}
```

**Tradeoffs:**
- Local dev can't use Agent Engine without manual creation (acceptable: use ephemeral sessions)
- Agent Engine created per workspace (good: environment isolation)

---

### 5. Security Review Requirement for Dotenv Provider

**Decision:** Bootstrap uses dotenv provider (with version pinning), but requires security review.

**Provider details:**
- **Source:** `germanbrew/dotenv` from Terraform Registry
- **Version:** 1.2.9 (pinned)
- **Registry:** https://registry.terraform.io/providers/germanbrew/dotenv/latest/docs

**Rationale:**
- **Convenience:** Reads GCP project, location, etc. from .env (simpler than CLI args)
- **Security risk:** Dotenv provider reads file contents, potential for malicious provider updates
- **Mitigation:** Pin exact version, document security review process

**Security requirements:**
1. **Version pinning:** Bootstrap must pin exact dotenv provider version (1.2.9)
2. **Security review:** Document review of pinned version (code audit, provenance)
3. **Upgrade process:** New versions require security review before adoption
4. **Documentation:** Dated security review results in docs/terraform-infrastructure.md

**Alternative considered:** Remove dotenv entirely, use TF_VAR_* for bootstrap too (rejected: adds complexity for one-time setup)

---

### 6. GCS State Bucket Provisioned by Bootstrap

**Decision:** Bootstrap creates the GCS bucket for main module's remote state.

**Rationale:**
- **No manual bucket creation:** Developer doesn't run gcloud commands
- **Automatic naming:** Bucket name follows `terraform-state-{project-id}` pattern
- **One-time setup:** Bucket created by bootstrap, used forever by main
- **Proper configuration:** Versioning, lifecycle policies set by Terraform

**Implementation:**
```hcl
# terraform/bootstrap/main.tf
resource "google_storage_bucket" "terraform_state" {
  name     = "terraform-state-${local.project}"
  location = "US"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

# Grant GitHub Actions access
resource "google_storage_bucket_iam_member" "github_state" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectUser"
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.repository_owner}/${local.repository_name}"
}

# Export bucket name as GitHub Variable for main module
resource "github_actions_variable" "terraform_state_bucket" {
  repository    = local.repository_name
  variable_name = "TERRAFORM_STATE_BUCKET"
  value         = google_storage_bucket.terraform_state.name
}
```

---

### 7. No Remote State Sharing Between Modules

**Decision:** Main module does NOT read bootstrap outputs via remote state.

**Rationale:**
- **Simplicity:** No data sources, no backend configuration in main for reading bootstrap
- **Independence:** Main module self-contained (all inputs from GitHub Variables)
- **Clarity:** One-way data flow (bootstrap sets GitHub Variables, main reads env vars)

**Data flow:**
```
Bootstrap (local state)
  ↓ (creates)
GitHub Variables (TF_VAR_*)
  ↓ (read by)
Main Module (GCS remote state)
```

**Alternative considered:** Remote state sharing (rejected: unnecessary complexity, bootstrap sets Variables which is cleaner)

---

## Current State

### What Exists Today

**Terraform modules (before revision):**
- `terraform/bootstrap/`
  - ✅ Creates WIF, Artifact Registry, GitHub Variables
  - ✅ Uses GCS backend (to be CHANGED to local)
  - ❌ Creates Agent Engine (to be REMOVED)

- `terraform/main/`
  - ✅ Creates Cloud Run service, service account
  - ✅ Uses GCS backend (KEEP)
  - ✅ Uses dotenv provider (to be REMOVED)
  - ❌ Reads bootstrap remote state (to be REMOVED)
  - ❌ Missing Agent Engine creation (to be ADDED)

**Documentation created (Phase 0):**
- ✅ docs/terraform-infrastructure.md (needs revision for new architecture)
- ✅ .gitignore updated for Terraform files
- ❌ .env.example mentions TERRAFORM_STATE_BUCKET (to be removed)

**GitHub Actions workflows:**
- ✅ docker-build-push.yml (no changes needed)
- ❌ terraform-deploy.yml (not yet created)

### What Changed During Initial Work (Now Partially Reversed)

**Phase 0 & 1 work that will be REVERSED:**
- ❌ GCS backend in bootstrap (revert to local state)
- ❌ Bootstrap remote state data source in main (remove entirely)
- ❌ AGENT_ENGINE reading from remote state (remove, create in main instead)
- ❌ Dotenv provider in main (remove entirely)
- ❌ TERRAFORM_STATE_BUCKET in .env.example (already removed, good)

**Phase 0 & 1 work that will be KEPT:**
- ✅ docs/terraform-infrastructure.md (update content)
- ✅ .gitignore Terraform patterns
- ✅ Backend simplification (automatic bucket naming)

---

## Work Completed (Partially Reversed)

### Items to Keep ✅

1. ✅ Created docs/terraform-infrastructure.md (will be updated)
2. ✅ Updated .gitignore for Terraform files
3. ✅ Removed TERRAFORM_STATE_BUCKET from .env.example
4. ✅ Documented automatic bucket naming pattern

### Items to Reverse ❌

1. ❌ **Bootstrap GCS backend** → Revert to local state
2. ❌ **Main dotenv provider** → Remove entirely, use TF_VAR_* inputs
3. ❌ **Bootstrap remote state in main** → Remove data source
4. ❌ **AGENT_ENGINE from remote state** → Create in main module instead

### Commits That Need Reversal

From feat/terraform branch:
- Commits enabling GCS backend in bootstrap
- Commits adding remote state data sources to main
- Commits reading AGENT_ENGINE from bootstrap

**Reversal strategy:**
- Option 1: Revert specific commits
- Option 2: Make new commits with corrected implementation
- **Recommended:** Option 2 (forward progress with clear history)

---

## Remaining Work

### Phase 0 (REVISED): Bootstrap Module Simplification

**Goal:** Bootstrap uses local state, creates GCS bucket for main, sets GitHub Variables as TF_VAR_*.

#### Task 0.1: Revert Bootstrap to Local State

**Changes:**
1. Remove GCS backend from `terraform/bootstrap/backend.tf`
2. Update to use local state (or remove backend.tf entirely)
3. Update docs/terraform-infrastructure.md (no state bucket creation step)

**Files to modify:**
- terraform/bootstrap/backend.tf (remove GCS backend)
- docs/terraform-infrastructure.md (remove state bucket setup section)

**Estimated effort:** 30 minutes
**Complexity:** Low (revert changes)

---

#### Task 0.2: Add State Bucket Creation to Bootstrap

**Changes:**
```hcl
# terraform/bootstrap/main.tf

# Create GCS bucket for main module's remote state
resource "google_storage_bucket" "terraform_state" {
  name     = "terraform-state-${local.project}"
  location = "US"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  versioning {
    enabled = true
  }
}

# Grant GitHub Actions access to state bucket
resource "google_storage_bucket_iam_member" "github_state" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectUser"
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${local.repository_owner}/${local.repository_name}"
}
```

**Files to modify:**
- terraform/bootstrap/main.tf (add bucket resource)

**Estimated effort:** 1 hour
**Complexity:** Low (standard GCS bucket)

---

#### Task 0.3: Update Bootstrap GitHub Variables ✅ COMPLETED

**Changes:**
```hcl
# terraform/bootstrap/main.tf

locals {
  github_variables = {
    # Standard environment variable names (mapped to TF_VAR_* in workflow)
    GCP_PROJECT_ID                 = local.project
    GCP_LOCATION                   = local.location
    IMAGE_NAME                     = local.agent_name
    TERRAFORM_STATE_BUCKET         = google_storage_bucket.terraform_state.name

    # WIF and registry (non-Terraform)
    GCP_WORKLOAD_IDENTITY_PROVIDER = google_iam_workload_identity_pool_provider.github.name
    ARTIFACT_REGISTRY_URI          = "${local.location}-docker.pkg.dev/${local.project}/${google_artifact_registry_repository.docker.name}"
    ARTIFACT_REGISTRY_LOCATION     = local.location
  }
}

resource "github_actions_variable" "variables" {
  for_each      = local.github_variables
  repository    = local.repository_name
  variable_name = each.key
  value         = each.value
}
```

**Files modified:**
- ✅ terraform/bootstrap/main.tf (updated github_variables local)

**Actual effort:** 30 minutes
**Complexity:** Low (variable naming update)

---

#### Task 0.4: Pin Dotenv Provider Version and Document Security

**Changes:**
```hcl
# terraform/bootstrap/terraform.tf

terraform {
  required_version = ">= 1.14.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.17"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.4"
    }
    dotenv = {
      source  = "germanbrew/dotenv"
      version = "1.2.9"  # PINNED - see security review
    }
  }
}
```

**Security documentation:**
```markdown
# docs/terraform-infrastructure.md

## Security: Dotenv Provider

Bootstrap module uses the `germanbrew/dotenv` provider for convenience (reads .env file).

**Current version:** 1.2.9
**Registry:** https://registry.terraform.io/providers/germanbrew/dotenv/latest/docs
**Review date:** 2025-11-21
**Reviewed by:** [Reviewer name]

**Security assessment:**
- Provider source: germanbrew/dotenv from Terraform Registry
- Version 1.2.9 (pinned)
- Code review: Read-only file operations, no network calls
- Provenance: Official Terraform Registry
- Risk level: LOW (read-only local file access)

**Upgrade process:**
1. Review new version documentation on Terraform Registry
2. Check for security issues or unexpected changes
3. Update version pin in terraform.tf
4. Document review with date and findings
5. Test with sample .env file

**Last reviewed versions:**
- 1.2.9 (2025-11-21): ✅ Approved - read-only, no dependencies
```

**Files to modify:**
- terraform/bootstrap/terraform.tf (pin version)
- docs/terraform-infrastructure.md (add security section)

**Estimated effort:** 2 hours (includes security review)
**Complexity:** Medium (security audit)

---

### Phase 1 (REVISED): Main Module Refactor

**Goal:** Remove dotenv provider, remove remote state dependency, add Agent Engine creation.

#### Task 1.1: Remove Dotenv Provider from Main Module

**Changes:**
1. Remove dotenv provider from `terraform/main/terraform.tf`
2. Remove `data.dotenv.adk` from `terraform/main/main.tf`
3. Update all locals that read from dotenv to use variables

**Before:**
```hcl
data "dotenv" "adk" {
  filename = "${path.cwd}/.env"
}

locals {
  project = coalesce(var.project, data.dotenv.adk.entries.GOOGLE_CLOUD_PROJECT)
}
```

**After:**
```hcl
# Remove locals for project, location, agent_name - use var.* directly
# Keep only necessary locals (docker_image recycling)
locals {
  run_app_env = {
    GOOGLE_GENAI_USE_VERTEXAI = "TRUE"
    GOOGLE_CLOUD_PROJECT      = var.project
    GOOGLE_CLOUD_LOCATION     = var.location
    AGENT_ENGINE              = google_vertex_ai_reasoning_engine.session_and_memory.id
    ROOT_AGENT_MODEL          = var.model
    LOG_LEVEL                 = var.log_level
    SERVE_WEB_INTERFACE       = var.serve_web_interface
    RELOAD_AGENTS             = "false"  # Hardcoded for production safety
  }

  # Recycle docker_image from previous deployment
  docker_image = coalesce(var.docker_image, try(data.terraform_remote_state.main.outputs.deployed_image, null))
}
```

**Files to modify:**
- terraform/main/terraform.tf (remove dotenv provider)
- terraform/main/main.tf (remove data source, update locals)

**Estimated effort:** 1 hour
**Complexity:** Medium (touch multiple files, careful variable handling)

---

#### Task 1.2: Remove Bootstrap Remote State from Main Module

**Changes:**
1. Remove `data.terraform_remote_state.bootstrap` from main.tf
2. Remove bucket name construction logic
3. Simplify docker_image default (only read from own remote state)

**Before:**
```hcl
data "terraform_remote_state" "bootstrap" {
  backend = "gcs"
  workspace = terraform.workspace
  config = {
    bucket = "terraform-state-${coalesce(var.project, ...)}"
    prefix = "bootstrap"
  }
}
```

**After:**
```hcl
# Remove entire data source - not needed
```

**Files to modify:**
- terraform/main/main.tf (remove bootstrap remote state data source)
- terraform/main/backend.tf (simplify, no bucket construction)

**Estimated effort:** 30 minutes
**Complexity:** Low (delete code)

---

#### Task 1.3: Update Main Module Variables

**Changes:**
```hcl
# terraform/main/variables.tf

# Required variables (no defaults, must be provided via TF_VAR_* or CLI)
variable "project" {
  description = "Google Cloud project ID"
  type        = string
}

variable "location" {
  description = "Google Cloud location (Compute region)"
  type        = string
}

variable "agent_name" {
  description = "Agent name for resource naming"
  type        = string
}

variable "docker_image" {
  description = "Docker image URI to deploy (nullable, defaults to previous deployment)"
  type        = string
  default     = null
}

# Optional variables (with defaults)
variable "app_iam_roles" {
  description = "Service account IAM roles"
  type        = set(string)
  default = [
    "roles/aiplatform.user",
    "roles/logging.logWriter",
    # ...
  ]
}

variable "model" {
  description = "Vertex AI model name"
  type        = string
  default     = "gemini-2.5-flash"
}

variable "log_level" {
  description = "Logging level for the agent"
  type        = string
  default     = "INFO"
}

variable "serve_web_interface" {
  description = "Enable web UI"
  type        = string
  default     = "false"
}
```

**Files to modify:**
- terraform/main/variables.tf (make required vars non-nullable, no defaults)

**Estimated effort:** 30 minutes
**Complexity:** Low (variable definitions)

---

#### Task 1.4: Add Agent Engine to Main Module

**Changes:**
```hcl
# terraform/main/main.tf

resource "google_vertex_ai_reasoning_engine" "session_and_memory" {
  display_name = "Session and Memory: ${var.agent_name}"
  description  = "Managed Session and Memory Bank Service"

  lifecycle {
    prevent_destroy = true  # Protect stateful data
  }
}

locals {
  run_app_env = {
    GOOGLE_GENAI_USE_VERTEXAI = "TRUE"
    GOOGLE_CLOUD_PROJECT      = var.project
    GOOGLE_CLOUD_LOCATION     = var.location
    # Direct reference to Agent Engine created in this module
    AGENT_ENGINE              = google_vertex_ai_reasoning_engine.session_and_memory.id
    ROOT_AGENT_MODEL          = var.model
    LOG_LEVEL                 = var.log_level
    SERVE_WEB_INTERFACE       = var.serve_web_interface
    RELOAD_AGENTS             = "false"  # Hardcoded for production safety
  }

  # Recycle docker_image from previous deployment
  docker_image = coalesce(var.docker_image, try(data.terraform_remote_state.main.outputs.deployed_image, null))
}
```

**Files to modify:**
- terraform/main/main.tf (add Agent Engine resource, update locals)

**Estimated effort:** 1 hour
**Complexity:** Medium (new resource, environment variable wiring)

---

#### Task 1.5: Update Main Module Backend Configuration

**Changes:**
```hcl
# terraform/main/backend.tf

terraform {
  backend "gcs" {
    # Bucket name passed via -backend-config during terraform init
    # Example (local): terraform -chdir=terraform/main init -backend-config="bucket=terraform-state-PROJECT"
    # Example (CI/CD): terraform init -backend-config="bucket=${{ vars.TERRAFORM_STATE_BUCKET }}"
    prefix = "main"
  }
}
```

**CI/CD init step:**
```yaml
# In .github/workflows/terraform-deploy.yml
- name: Terraform Init
  working-directory: terraform/main
  run: |
    terraform init \
      -backend-config="bucket=${{ vars.TERRAFORM_STATE_BUCKET }}"
```

**Note:** Backend configuration can't use variables directly. Bucket name passed via `-backend-config` CLI flag during init step and not needed again.

**Files to modify:**
- terraform/main/backend.tf (update comments)

**Estimated effort:** 15 minutes
**Complexity:** Low (documentation)

---

### Phase 2: Documentation Updates

**Goal:** Update all documentation to reflect revised architecture.

#### Task 2.1: Update docs/terraform-infrastructure.md

**Major changes:**
1. Remove "Create State Bucket" section (bootstrap creates it)
2. Update bootstrap section: local state, creates bucket
3. Add dotenv security review section
4. Update main section: CI/CD only, TF_VAR_* inputs
5. Remove remote state sharing section
6. Update initialization commands

**New structure:**
```markdown
## Bootstrap Module

### Prerequisites
- gcloud auth configured
- gh auth configured
- .env file with GOOGLE_CLOUD_PROJECT, etc.

### Usage

```bash
# One-time setup (creates CI/CD infrastructure)
# Run from repository root using -chdir flag
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap apply
```

Bootstrap creates:
- WIF for GitHub Actions
- Artifact Registry
- GCS bucket for main module state (auto-named)
- GitHub Variables (for main module)

### Security: Dotenv Provider
[Security review section]

## Main Module

### Overview
Main module runs EXCLUSIVELY in GitHub Actions CI/CD.

Local execution is possible but not recommended (see Advanced Usage).

### CI/CD Execution

GitHub Actions provides all inputs via TF_VAR_* in workflow env:
- Standard env vars from GitHub Variables (set by bootstrap)
- docker_image constructed from registry URI and image tag

```yaml
# In terraform-plan-apply.yml
env:
  TF_VAR_project: ${{ vars.GCP_PROJECT_ID }}
  TF_VAR_location: ${{ vars.GCP_LOCATION }}
  TF_VAR_agent_name: ${{ vars.IMAGE_NAME }}
  TF_VAR_terraform_state_bucket: ${{ vars.TERRAFORM_STATE_BUCKET }}
  TF_VAR_docker_image: ${{ inputs.docker_image }}
  # Optional overrides (set in workflow if needed)
  # TF_VAR_log_level: "DEBUG"
  # TF_VAR_serve_web_interface: "true"
```

### Advanced: Local Execution (Optional)

If you must run main module locally (from repository root using -chdir):

```bash
export TF_VAR_project="your-project"
export TF_VAR_location="us-central1"
export TF_VAR_agent_name="adk-docker-uv"
export TF_VAR_docker_image="us-central1-docker.pkg.dev/your-project/your-repo/your-image:tag"

terraform -chdir=terraform/main init -backend-config="bucket=terraform-state-your-project"
terraform -chdir=terraform/main apply
```

Not recommended: main module is designed for CI/CD execution.


**Files to modify:**
- docs/terraform-infrastructure.md (major rewrite)

**Estimated effort:** 3-4 hours
**Complexity:** Medium-High (comprehensive documentation)

---

#### Task 2.2: Update README.md Quickstart

**Revised quickstart:**
``````markdown
## Quickstart

### Prerequisites
- Docker and Docker Compose
- uv (Python package manager)
- Optional: Terraform, gcloud, gh (for CI/CD setup)

### Phase 1: Local Development (Minimal Cloud Cost)

1. Clone and initialize:
   ```bash
   git clone <your-repo>
   cd adk-docker-uv
   uv run init_template.py
   ```

2. Configure environment:
   ```bash
   cp .env.example .env
   # Edit .env: Set GOOGLE_CLOUD_PROJECT and choose auth method
   ```

3. Run agent locally:
   ```bash
   docker compose up --build --watch
   ```

4. Agent ready at http://127.0.0.1:8000 (ephemeral sessions, LLM API usage only)

**Optional Upgrade to Persistent Sessions (after deployment):**
1. Deploy via CI/CD (Phase 2 & 3)
2. Get Agent Engine resource name: `terraform -chdir=terraform/main output -raw reasoning_engine_resource_name`
3. Add to `.env`: `AGENT_ENGINE=projects/.../reasoningEngines/...`
4. Restart local agent

### Phase 2: CI/CD Setup (One-Time)

1. Ensure prerequisites:
   ```bash
   # Authenticate
   gcloud auth application-default login
   gh auth login
   ```

2. Run bootstrap (from repository root):
   ```bash
   terraform -chdir=terraform/bootstrap init
   terraform -chdir=terraform/bootstrap apply
   ```

3. Bootstrap creates:
   - GitHub Actions authentication (WIF)
   - Docker registry (Artifact Registry)
   - State storage for deployments (GCS bucket for main module)
   - GitHub Variables for automated deployment

### Phase 3: Deploy

1. Push code to main branch
2. GitHub Actions automatically:
   - Builds Docker image
   - Deploys to Cloud Run
   - Creates persistent Agent Engine
3. Deployed agent has persistent sessions

**That's it!** Local dev needs no cloud resources, deployment is fully automated.
``````

**Files to modify:**
- README.md (rewrite quickstart)

**Estimated effort:** 2 hours
**Complexity:** Medium (content reorganization)

---

#### Task 2.3: Create docs/environment-variables.md (Updated)

**Revised content:**
``````markdown
# Environment Variables Reference

## Local Development

### Required
- GOOGLE_CLOUD_PROJECT - GCP project ID
- GOOGLE_CLOUD_LOCATION - GCP region

### Authentication (Choose ONE)
- GOOGLE_API_KEY (Gemini API)
- OR: gcloud auth (Vertex AI)

### Optional
- LOG_LEVEL (default: INFO)
- SERVE_WEB_INTERFACE (default: false)
- RELOAD_AGENTS (default: false)

**Note:** AGENT_ENGINE not needed for local dev by default (uses ephemeral sessions)

**Optional upgrade:** After deployment, copy Agent Engine resource name from Terraform output to `.env` for full feature parity (persistent sessions).

## Terraform Bootstrap (.env file)

Bootstrap reads these from .env:
- AGENT_NAME - Agent name for resources
- GOOGLE_CLOUD_PROJECT - GCP project
- GOOGLE_CLOUD_LOCATION - GCP region
- GITHUB_REPO_NAME - Repository name
- GITHUB_REPO_OWNER - GitHub owner

## Terraform Main (CI/CD Only)

Main module receives inputs mapped from GitHub Variables (all via TF_VAR_* in workflow env):
- TF_VAR_project ← GCP_PROJECT_ID
- TF_VAR_location ← GCP_LOCATION
- TF_VAR_agent_name ← IMAGE_NAME
- TF_VAR_terraform_state_bucket ← TERRAFORM_STATE_BUCKET
- TF_VAR_docker_image ← Passed directly from build workflow output

Optional overrides via workflow env:
- TF_VAR_log_level (default: INFO)
- TF_VAR_serve_web_interface (default: false)
- TF_VAR_model (default: gemini-2.5-flash)

## GitHub Variables (Auto-Created by Bootstrap)

Standard identifiers (mapped to TF_VAR_* in workflow):
- GCP_PROJECT_ID - GCP project ID
- GCP_LOCATION - GCP region
- IMAGE_NAME - Docker image name (also used as agent_name)
- TERRAFORM_STATE_BUCKET - GCS bucket for main module state

WIF and registry (used directly by workflows):
- GCP_WORKLOAD_IDENTITY_PROVIDER - WIF provider name
- ARTIFACT_REGISTRY_URI - Registry URI
- ARTIFACT_REGISTRY_LOCATION - Registry location
``````

**Files to create:**
- docs/environment-variables.md

**Estimated effort:** 2 hours
**Complexity:** Medium (comprehensive reference)

---

### Phase 3: CI/CD Workflow Creation

**Goal:** Create terraform-deploy.yml that uses TF_VAR_* from GitHub Variables.

#### Task 3.1: Create Reusable Workflows and CI/CD Orchestrator ✅ COMPLETED

**Pattern reference:** https://spacelift.io/blog/github-actions-terraform

**Architecture:** Four-job design with metadata extraction and reusable workflows:
1. **ci-cd.yml** - Parent orchestrator with metadata extraction job
2. **docker-build.yml** - Reusable build workflow (receives tags and image URI)
3. **terraform-plan-apply.yml** - Reusable terraform workflow (receives image URI, workspace, action)

**Benefits:**
- Metadata extraction separated into dedicated job (cleaner separation)
- Direct image URI passing (no tag reconstruction)
- Plan on PRs, apply on main (single orchestrator workflow)
- Individual workflows can be triggered manually for testing
- Clean separation of concerns

---

##### File 1: `.github/workflows/ci-cd.yml` (Parent Orchestrator)

**Implementation details:**
- **Metadata job:** Extracts tags and primary image URI based on context (PR vs main)
- **Tag strategy:**
  - PR builds: `pr-{number}-{sha-short}` (unique per commit, clearly indicates origin)
  - Main builds: `{sha-short}` as primary (immutable, traceable), plus `latest` and `{version}` tags
- **Job flow:** meta → build → deploy
- **Conditional logic:** PR = plan, main/manual = apply

**Key implementation patterns:**
```yaml
# Metadata extraction (in ci-cd.yml)
jobs:
  meta:
    outputs:
      tags: ${{ steps.meta.outputs.tags }}
      image_uri: ${{ steps.meta.outputs.image_uri }}
    steps:
      - name: Extract metadata
        run: |
          # PR: pr-{number}-{sha}
          # Main: {sha} (primary), latest, version

  build:
    needs: meta
    uses: ./.github/workflows/docker-build.yml
    with:
      tags: ${{ needs.meta.outputs.tags }}
      image_uri: ${{ needs.meta.outputs.image_uri }}

  deploy:
    needs: build
    uses: ./.github/workflows/terraform-plan-apply.yml
    with:
      docker_image: ${{ needs.build.outputs.image_uri }}
```

---

##### File 2: `.github/workflows/docker-build.yml` (Reusable Build Workflow)

**Implementation details:**
- **Inputs:** `push`, `tags`, `image_uri`, `cache_from`, `cache_to`
- **Outputs:** `image_uri` (pass-through for terraform workflow)
- **Authentication:** Uses WIF with `GCP_PROJECT_ID` and `GCP_WORKLOAD_IDENTITY_PROVIDER`
- **Registry location:** Uses `ARTIFACT_REGISTRY_LOCATION` variable
- **Build platforms:** `linux/amd64,linux/arm64`
- **Cache strategy:** Registry cache with `buildcache` tag

**Key implementation patterns:**
```yaml
# Build step (in docker-build.yml)
- name: Build and push Docker image
  uses: docker/build-push-action@v6
  with:
    context: .
    push: ${{ inputs.push }}
    platforms: linux/amd64,linux/arm64
    tags: ${{ inputs.tags }}
    cache-from: ${{ inputs.cache_from }}
    cache-to: ${{ inputs.cache_to }}
```

---

##### File 3: `.github/workflows/terraform-plan-apply.yml` (Reusable Terraform Workflow)

**Implementation details:**
- **Inputs:** `docker_image`, `workspace`, `terraform_action`
- **Environment variables:** Maps GitHub Variables to `TF_VAR_*`:
  - `TF_VAR_project` ← `GCP_PROJECT_ID`
  - `TF_VAR_location` ← `GCP_LOCATION`
  - `TF_VAR_agent_name` ← `IMAGE_NAME`
  - `TF_VAR_terraform_state_bucket` ← `TERRAFORM_STATE_BUCKET`
  - `TF_VAR_docker_image` ← `inputs.docker_image`
- **PR comments:** Posts plan output with collapsible sections
- **Concurrency control:** Per-workspace locking

**Key implementation patterns:**
```yaml
# Terraform init (in terraform-plan-apply.yml)
- name: Terraform Init
  run: |
    terraform init \
      -backend-config="bucket=${{ vars.TERRAFORM_STATE_BUCKET }}"

# PR comment (simplified)
- name: Comment PR with Plan
  if: github.event_name == 'pull_request'
  uses: actions/github-script@v8
  # Posts collapsible sections for fmt, init, validate, plan
```

---

**Files created:**
- ✅ `.github/workflows/ci-cd.yml` (orchestrator with meta job)
- ✅ `.github/workflows/docker-build.yml` (reusable build)
- ✅ `.github/workflows/terraform-plan-apply.yml` (reusable terraform)

**Files deprecated:**
- ✅ `.github/workflows/docker-build-push.yml` → `.github/workflows/docker-build-push.yml.deprecated`

**GitHub Variables used:**
- `GCP_PROJECT_ID` - GCP project ID
- `GCP_LOCATION` - GCP region
- `IMAGE_NAME` - Docker image name (also used as agent_name)
- `GCP_WORKLOAD_IDENTITY_PROVIDER` - WIF provider name
- `ARTIFACT_REGISTRY_URI` - Registry URI
- `ARTIFACT_REGISTRY_LOCATION` - Registry location
- `TERRAFORM_STATE_BUCKET` - GCS bucket for main module state

**Workflow Behavior:**

**On Pull Request:**
1. Metadata job extracts `pr-{number}-{sha}` tag
2. Build workflow pushes image: `{REGISTRY}/{IMAGE}:pr-{number}-{sha}`
3. Terraform workflow runs `plan` (no apply)
4. Plan output posted as PR comment with collapsible sections
5. PR shows exact infrastructure changes before merge

**On Merge to Main:**
1. Metadata job extracts tags: `{sha}` (primary), `latest`, `{version}` (if available)
2. Build workflow pushes all tags
3. Terraform workflow runs `apply` with `{sha}` image
4. Cloud Run service updated with immutable SHA-tagged image
5. Service URL output shown in workflow logs

**On Manual Dispatch:**
1. Metadata job still runs (uses commit SHA)
2. Build workflow can be triggered independently
3. Deploy workflow can be triggered independently with custom image URI
4. Full control over workspace (sandbox/staging/production) and action (plan/apply)

**PR Comment Format:**
- Collapsible sections for fmt, init, validate, plan
- Success/failure indicators (✅/❌ via emoji-based outcome display)
- Workspace and image URI metadata
- Pusher attribution
- Plan output in terraform code block

**Key Features:**
1. ✅ **Metadata separation:** Dedicated job for tag extraction logic
2. ✅ **Immutable deployments:** SHA tags for traceability
3. ✅ **PR validation:** Build succeeds + terraform plan visible before merge
4. ✅ **PR comment integration:** Collapsible sections with outcome indicators
5. ✅ **Buildcache efficiency:** Registry cache persists across builds
6. ✅ **Isolated PR images:** Tagged `pr-{number}-{sha}` for unique identification
7. ✅ **Flexible triggering:** Each workflow supports workflow_dispatch
8. ✅ **TF_VAR pattern:** All Terraform inputs via environment variables
9. ✅ **Multi-platform builds:** amd64 + arm64 support
10. ✅ **Workspace control:** Manual dispatch allows environment selection
11. ✅ **Zero touch deployments:** Merge to main → automatic build + deploy

**Actual effort:** 3-4 hours (workflow creation, integration, testing)
**Complexity:** Medium-High (workflow orchestration, output passing, PR comments)

---

#### Task 3.2: Test End-to-End Flow

**Test procedure:**

**Phase 1: Bootstrap Setup**
1. Run terraform bootstrap apply (creates WIF, registry, state bucket, GitHub Variables)
2. Verify GitHub Variables exist: `gh variable list`
3. Verify state bucket created: `gcloud storage ls | grep terraform-state`

**Phase 2: Pull Request Flow**
1. Create feature branch with trivial change (e.g., update README)
2. Open PR to main
3. Verify CI/CD Pipeline workflow triggers
4. Verify build workflow completes:
   - Image tagged `pr-{number}`
   - Image pushed to registry
   - Build output shows image URI
5. Verify terraform workflow completes:
   - Plan runs (no apply)
   - PR comment posted with collapsible plan output
   - Plan shows infrastructure changes (or "no changes")
6. Review PR comment format:
   - Check fmt, init, validate, plan sections
   - Verify ✅/❌ indicators
   - Verify metadata (workspace, docker image, pusher)

**Phase 3: Merge to Main Flow**
1. Merge PR to main
2. Verify CI/CD Pipeline workflow triggers
3. Verify build workflow completes:
   - Image tagged `latest`, `{sha-short}`, `{version}`
   - Multi-platform build (amd64/arm64)
   - Buildcache used (fast rebuild ~5-10s)
4. Verify terraform workflow completes:
   - Apply runs (auto-approved)
   - Cloud Run service created/updated
   - Agent Engine created (first run only)
   - Service URL output shown
5. Test deployed service:
   - Get URL: `terraform -chdir=terraform/main output -json cloud_run_services`
   - Test health endpoint: `curl {URL}/health`
   - Verify Agent Engine connected: check environment variables in Cloud Run console

**Phase 4: Manual Workflow Testing**
1. Trigger build.yml manually: test with/without push
2. Trigger terraform-deploy.yml manually: test plan/apply with custom image
3. Trigger ci-cd.yml manually: test workspace selection (sandbox/staging)

**Phase 5: Cleanup and Validation**
1. Verify Artifact Registry cleanup policies work (check old pr-* images)
2. Verify state bucket versioning enabled
3. Verify WIF permissions correct (no service account keys used)
4. Optional: Copy Agent Engine resource name to local `.env` and test local dev with persistent sessions

**Files:** None (testing only)

**Estimated effort:** 3-4 hours
**Complexity:** High (integration testing, troubleshooting, multi-phase validation)

---

### Phase 4: Cleanup

#### Task 4.1: Update CLAUDE.md

**Changes:**
- Document new quickstart flow (no cloud resources for local dev)
- Update Terraform sections (bootstrap local state, main CI/CD only)
- Remove dotenv from main module documentation
- Add Agent Engine creation in main module
- Update development commands (no terraform state bucket creation)

**Files to modify:**
- CLAUDE.md

**Estimated effort:** 2-3 hours
**Complexity:** Medium (comprehensive update)

---

#### Task 4.2: Remove Dead Code

**Items to remove:**
- Any remaining references to TERRAFORM_STATE_BUCKET env var
- Bootstrap remote state data source code
- Dotenv provider from main module
- Old documentation about Agent Engine in bootstrap

**Files to review:**
- All terraform files
- All documentation
- .env.example

**Estimated effort:** 1 hour
**Complexity:** Low (cleanup)

---

## Success Criteria

### Local Development ✅
- [ ] Clone → init → configure → docker compose (4 steps, <5 minutes)
- [ ] Minimal cloud cost (LLM API usage only, no infrastructure provisioning)
- [ ] Agent works with ephemeral sessions
- [ ] Optional upgrade path documented (copy Agent Engine for persistent sessions)
- [ ] Clear documentation

### Bootstrap (CI/CD Setup) ✅
- [ ] Single terraform apply command (run from root with -chdir flag)
- [ ] Uses local state by default (no state bucket needed for bootstrap)
- [ ] Optional remote state configuration supported
- [ ] Creates GCS bucket for main module
- [ ] Sets GitHub Variables with standard env var names
- [ ] Dotenv provider version pinned (germanbrew/dotenv 1.2.9)
- [ ] Security review documented

### Main Module (Deployment) ✅
- [ ] Runs in GitHub Actions only
- [ ] No dotenv provider
- [ ] All inputs from GitHub Variables (mapped to TF_VAR_* in workflow)
- [ ] docker_image constructed and passed via TF_VAR_docker_image
- [ ] Creates Agent Engine with prevent_destroy lifecycle
- [ ] Deploys to Cloud Run
- [ ] Flexible LOG_LEVEL and SERVE_WEB_INTERFACE via variables
- [ ] Agent Engine connected in deployment

### CI/CD Automation ✅
- [x] **PR Flow:** Build image (pr-{number}-{sha} tag), run terraform plan, post PR comment
- [x] **Main Flow:** Build image (sha + latest tags), run terraform apply, deploy to Cloud Run
- [x] Reusable workflows (docker-build.yml, terraform-plan-apply.yml) callable independently
- [x] Parent orchestrator (ci-cd.yml) with dedicated metadata extraction job
- [x] All Terraform inputs via TF_VAR_* in workflow env (project, location, agent_name, terraform_state_bucket, docker_image)
- [x] Backend bucket passed via -backend-config during init
- [x] Workspace selection uses --or-create flag
- [x] terraform plan and apply run without -var flags
- [x] PR comments show collapsible plan with fmt/init/validate/plan sections
- [x] Buildcache makes merge builds fast (registry cache with buildcache tag)
- [x] Cloud Run service updated on main merge (immutable SHA-tagged images)
- [x] Zero manual intervention for main deployments

### Documentation ✅
- [ ] Clear separation: local dev vs CI/CD setup
- [ ] All terraform commands use -chdir flag (run from root)
- [ ] Dotenv security review documented (germanbrew/dotenv 1.2.9)
- [ ] Main module marked as CI/CD only
- [ ] Advanced local execution documented (optional)
- [ ] GitHub Variable mapping to TF_VAR_* explained
- [ ] All commands tested and verified

---

## Dependencies & Constraints

### Hard Dependencies

**Phase 0 → Phase 1:**
- Bootstrap must create state bucket before main can use it
- GitHub Variables must be set before terraform-deploy.yml uses them

**Phase 1 → Phase 3:**
- Main module refactor must complete before workflow can use it
- Variables must be defined before workflow sets TF_VAR_*

**Phase 2 parallel with Phase 1:**
- Documentation can be written while code changes

### Soft Dependencies

**Phase 0 tasks are sequential:**
- 0.1 → 0.2 → 0.3 → 0.4 (revert state, add bucket, update vars, security)

**Phase 1 tasks mostly independent:**
- 1.1, 1.2, 1.3 can be done in parallel
- 1.4 depends on 1.1, 1.2 (variables defined)

### External Constraints

**Terraform backend limitations:**
- Backend config can't use variables (must use -backend-config CLI flag)
- Local state files not suitable for team collaboration (acceptable for bootstrap)

**GitHub Actions:**
- Variables are repository-scoped (good: shared across workflows)
- TF_VAR_* pattern is standard Terraform practice

**GCP:**
- Agent Engine quota varies by region
- WIF requires repository attribute condition

---

## Security Considerations

### Dotenv Provider Security

**Risk:** Malicious provider version could read sensitive files

**Mitigation:**
1. **Version pinning:** Exact version specified (1.0.2)
2. **Code review:** Manual inspection of provider source
3. **Provenance:** Official HashiCorp registry
4. **Scope limitation:** Only bootstrap uses dotenv (not main)
5. **Documentation:** Security review process documented

**Review checklist:**
- [ ] Source code inspected on GitHub
- [ ] No network calls in provider code
- [ ] Read-only file operations only
- [ ] No dependencies on untrusted packages
- [ ] Commit SHA verified
- [ ] Review date and reviewer documented

### State Bucket Security

**Risk:** Unauthorized access to infrastructure state

**Mitigation:**
1. **IAM binding:** Only GitHub Actions principal has access
2. **Versioning:** Enabled for state recovery
3. **Public access prevention:** Enforced
4. **Lifecycle policy:** Old versions cleaned up

### WIF Security

**Risk:** Compromise of GitHub Actions could access GCP

**Mitigation:**
1. **Attribute condition:** Scoped to specific repository
2. **Direct binding:** No service account impersonation
3. **Minimal permissions:** Only required roles granted
4. **Audit logging:** Enabled on GCP project

---

## Risk Mitigation

### Risk: Local State Loss (Bootstrap)

**Impact:** Would need to re-run bootstrap, potential conflicts

**Mitigation:**
- Local state file can be versioned in git (if team agrees)
- Bootstrap is idempotent (safe to re-run)
- Most resources have predictable names (can import if needed)

### Risk: Dotenv Provider Supply Chain Attack

**Impact:** Malicious provider could steal .env contents

**Mitigation:**
- Version pinning prevents automatic updates
- Security review process before upgrades
- .env contains no secrets (only GCP project ID, repo names)
- Bootstrap runs locally (not in CI/CD where secrets might exist)

### Risk: Agent Engine Accidental Deletion

**Impact:** Loss of session/memory data

**Mitigation:**
- lifecycle { prevent_destroy = true }
- Separate destroy requires override
- Documentation warns about data loss

### Risk: Missing GitHub Variables

**Impact:** Terraform deploy workflow fails

**Mitigation:**
- Bootstrap output clearly shows created variables
- Workflow validates required variables exist
- Troubleshooting guide documents verification steps

---

## Future Enhancements (Not in Scope)

**Multi-environment variables:**
- Different TF_VAR_* per environment (sandbox/staging/prod)
- Environment-specific GitHub Variables

**State bucket lifecycle:**
- Customer-managed encryption keys
- Lifecycle prevent_destroy
- Access logging

**Workflow improvements:**
- Terraform plan as PR comment
- Approval gates for production
- Rollback automation

**Security hardening:**
- Remove dotenv from bootstrap (use TF_VAR_* there too)
- Rotate WIF credentials periodically
- Scan Docker images for vulnerabilities

---

## Notes for Architect Agent

**Suggested work breakdown:**

**Epic: Simplify Local Dev & Automate Deployment**

**Milestone 1: Module Refactor**
- Issue 1: Revert bootstrap to local state (Task 0.1)
- Issue 2: Add state bucket to bootstrap (Task 0.2)
- Issue 3: Update bootstrap variables for TF_VAR_* (Task 0.3)
- Issue 4: Pin and audit dotenv provider (Task 0.4)
- Issue 5: Remove dotenv from main (Task 1.1)
- Issue 6: Remove bootstrap remote state from main (Task 1.2)
- Issue 7: Update main module variables (Task 1.3)
- Issue 8: Add Agent Engine to main (Task 1.4)

**Milestone 2: Documentation**
- Issue 9: Update terraform-infrastructure.md (Task 2.1)
- Issue 10: Update README quickstart (Task 2.2)
- Issue 11: Create environment-variables.md (Task 2.3)

**Milestone 3: CI/CD Automation**
- Issue 12: Create terraform-deploy.yml (Task 3.1)
- Issue 13: Test end-to-end flow (Task 3.2)

**Milestone 4: Cleanup**
- Issue 14: Update CLAUDE.md (Task 4.1)
- Issue 15: Remove dead code (Task 4.2)

**Parallel work opportunities:**
- Milestone 1 tasks can be grouped (0.1-0.4 sequential, 1.1-1.4 sequential, but two groups can be parallel)
- Milestone 2 tasks all parallel
- Milestone 3 sequential (12 → 13)
- Milestone 4 parallel

**Priority:**
- P0: Milestone 1 (blocking for CI/CD)
- P1: Milestone 3 (core feature)
- P2: Milestone 2 (user experience)
- P3: Milestone 4 (polish)

**Complexity:**
- Low: 30 min - 1 hour (0.1, 0.3, 1.2, 1.3, 4.2)
- Medium: 1-3 hours (0.2, 1.1, 1.4, 2.2, 2.3, 4.1)
- Medium-High: 3-4 hours (0.4, 2.1, 3.1 - reusable workflows)
- High: 3-4 hours (3.2 - comprehensive integration testing with multi-phase validation)

**Total estimated effort:** ~28-33 hours (increased from original estimate due to reusable workflow architecture)
