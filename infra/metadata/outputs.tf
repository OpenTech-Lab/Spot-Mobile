output "project_ref" {
  description = "Supabase project reference for the metadata backend"
  value       = local.project_ref
}

output "project_name" {
  description = "Provisioned or linked metadata project name"
  value       = var.create_project ? supabase_project.metadata[0].name : local.project_resource_name
}

output "api_url" {
  description = "Supabase API URL to use as SUPABASE_URL"
  value       = "https://${local.project_ref}.supabase.co"
}

output "dashboard_url" {
  description = "Supabase dashboard URL for the managed metadata project"
  value       = "https://supabase.com/dashboard/project/${local.project_ref}"
}
