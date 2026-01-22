terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "2.16.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

########################
# Providers
########################
# When running inside a K8s Job, omit config_path to use the ServiceAccount token automatically
provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  }
}

########################
# Namespace (Fixes the "already exists" error)
########################
resource "kubernetes_namespace" "ssd" {
  metadata {
    name = var.namespace
  }

  # This block tells Terraform: "If it exists, just use it. If not, create it."
  # This prevents the error you are seeing during automated runs.
  lifecycle {
    ignore_changes = all
  }
}

########################
# Clone the Helm chart repository
########################
resource "null_resource" "clone_ssd_chart" {
  triggers = {
    # This ensures a re-run/upgrade whenever the branch or repo URL changes
    git_repo   = var.git_repo_url
    git_branch = var.git_branch
  }

  provisioner "local-exec" {
    working_dir = "/tmp"
    command     = <<EOT
      rm -rf enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} enterprise-ssd
    EOT
  }
}

########################
# OpsMx SSD Helm Release (Handles Upgrades)
########################
resource "helm_release" "opsmx_ssd" {
  for_each = toset(var.ingress_hosts)

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = kubernetes_namespace.ssd.metadata[0].name

  chart = "/tmp/enterprise-ssd/charts/ssd"

  values = [
    "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  ]

  # Deployment Settings
  create_namespace = false
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  
  # Upgrade Settings
  force_update     = true
  recreate_pods    = true
  # This ensures that if the chart content changes, Helm performs an upgrade
  replace          = false 

  set {
    name  = "ingress.enabled"
    value = "true"
  }

  set {
    name  = "global.certManager.installed"
    value = tostring(var.cert_manager_installed)
  }

  set {
    name  = "global.ssdUI.host"
    value = each.value
  }

  depends_on = [null_resource.clone_ssd_chart]
}

########################
# Outputs
########################
output "ssd_releases" {
  value = {
    for k, v in helm_release.opsmx_ssd :
    k => {
      name      = v.name
      namespace = v.namespace
      version   = v.version
    }
  }
}
