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

provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}

provider "helm" {
  kubernetes {
    config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  }
}

# 1. Clone/Update Helm Chart Repo
resource "null_resource" "clone_ssd_chart" {
  triggers = {
    git_repo   = var.git_repo_url
    git_branch = var.git_branch
  }

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /tmp/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /tmp/enterprise-ssd
    EOT
  }
}

# 2. SSD Helm Release
resource "helm_release" "opsmx_ssd" {
  for_each   = toset(var.ingress_hosts)
  
  # This ensures the clone happens first
  depends_on = [null_resource.clone_ssd_chart]

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = var.namespace
  
  # FIX: We use a path that Terraform won't validate until it's actually applying
  chart      = "/tmp/enterprise-ssd/charts/ssd"
  
  values = [
    "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  ]

  create_namespace = true
  force_update     = true
  recreate_pods    = true
  cleanup_on_fail  = true
  wait             = true

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

  lifecycle {
    replace_triggered_by = [null_resource.clone_ssd_chart]
  }
}
