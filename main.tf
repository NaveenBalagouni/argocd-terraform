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
provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  }
}

########################
# Namespace
########################
resource "kubernetes_namespace" "ssd" {
  metadata {
    name = var.namespace
  }

  lifecycle {
    # Set to true if you want to ensure Terraform never deletes this namespace
    prevent_destroy = false 
    ignore_changes  = all
  }
}

########################
# Clone the Helm chart repository
########################
resource "null_resource" "clone_ssd_chart" {
  triggers = {
    git_repo   = var.git_repo_url
    git_branch = var.git_branch
  }

  provisioner "local-exec" {
    # This prevents the "No such file or directory" error by giving git a stable home
    working_dir = "/tmp"
    command     = <<EOT
      rm -rf enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} enterprise-ssd
    EOT
  }
}

########################
# OpsMx SSD Helm Release
########################
resource "helm_release" "opsmx_ssd" {
  for_each = toset(var.ingress_hosts)

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = kubernetes_namespace.ssd.metadata[0].name

  # Reference the absolute path from the clone location
  chart = "/tmp/enterprise-ssd/charts/ssd"

  values = [
    "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  ]

  create_namespace = false
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  force_update     = true
  recreate_pods    = true

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
