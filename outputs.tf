output "helm_release_names" {
  description = "The names of the deployed Helm releases"
  # This mapping is critical because you are using for_each
  value       = { for host, release in helm_release.opsmx_ssd : host => release.name }
}

output "helm_namespace" {
  description = "The namespace where SSD is deployed"
  value       = var.namespace
}

output "ssd_ingress_host" {
  description = "List of ingress hosts configured"
  value       = var.ingress_hosts
}
