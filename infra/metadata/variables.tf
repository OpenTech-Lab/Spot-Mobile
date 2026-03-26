variable "supabase_access_token" {
  description = "Supabase personal access token used by the Terraform provider"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "Base name used for the Supabase metadata project"
  type        = string
  default     = "spot-metadata"
}

variable "environment" {
  description = "Deployment environment suffix"
  type        = string
  default     = "prod"
}

variable "create_project" {
  description = "Whether Terraform should create a Supabase project instead of linking an existing project"
  type        = bool
  default     = false
}

variable "linked_project" {
  description = "Existing Supabase project ref to manage when create_project is false"
  type        = string
  default     = ""
}

variable "organization_id" {
  description = "Supabase organization id used when create_project is true"
  type        = string
  default     = ""
}

variable "database_password" {
  description = "Database password used when create_project is true"
  type        = string
  default     = ""
  sensitive   = true
}

variable "supabase_region" {
  description = "Supabase region for a newly-created project"
  type        = string
  default     = "ap-northeast-1"
}

variable "db_max_rows" {
  description = "API row cap for PostgREST queries"
  type        = number
  default     = 1000
}

variable "apply_database_migrations" {
  description = "Whether Terraform should apply the SQL files under ./sql via psql"
  type        = bool
  default     = false
}

variable "database_url" {
  description = "Direct Postgres connection URL for applying SQL migrations when apply_database_migrations is true"
  type        = string
  default     = ""
  sensitive   = true
}
