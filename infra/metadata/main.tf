terraform {
  required_version = ">= 1.5"

  required_providers {
    supabase = {
      source  = "supabase/supabase"
      version = "~> 1.0"
    }
  }
}

provider "supabase" {
  access_token = var.supabase_access_token
}

locals {
  project_resource_name = "${var.project_name}-${var.environment}"
  project_ref           = var.create_project ? supabase_project.metadata[0].id : var.linked_project
  sql_files             = sort(fileset("${path.module}/sql", "*.sql"))
  sql_fingerprint       = sha256(join("", [for file in local.sql_files : filesha256("${path.module}/sql/${file}")]))
}

resource "supabase_project" "metadata" {
  count = var.create_project ? 1 : 0

  organization_id   = var.organization_id
  name              = local.project_resource_name
  database_password = var.database_password
  region            = var.supabase_region

  lifecycle {
    ignore_changes = [database_password]
  }
}

resource "supabase_settings" "metadata" {
  project_ref = local.project_ref

  api = jsonencode({
    db_schema            = "public,storage,graphql_public"
    db_extra_search_path = "public,extensions"
    max_rows             = var.db_max_rows
  })
}

resource "terraform_data" "metadata_schema" {
  count = var.apply_database_migrations ? 1 : 0

  triggers_replace = {
    project_ref      = local.project_ref
    sql_fingerprint  = local.sql_fingerprint
    database_url_sha = sha256(nonsensitive(var.database_url))
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/apply_sql.sh ${path.module}/sql"

    environment = {
      DATABASE_URL = nonsensitive(var.database_url)
    }
  }

  depends_on = [supabase_settings.metadata]
}
