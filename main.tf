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
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
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

# ----------------------------------------
# 1. Ensure the namespace exists (ignore if already present)
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }

  lifecycle {
    ignore_changes = [metadata]
  }
}

# ----------------------------------------
# 2. Clone Helm chart repository to /workspace
resource "null_resource" "clone_ssd_chart" {
  triggers = {
    git_repo   = var.git_repo_url
    git_branch = var.git_branch
  }

  provisioner "local-exec" {
    command = <<EOT
      rm -rf /workspace/enterprise-ssd
      git clone --branch ${var.git_branch} ${var.git_repo_url} /workspace/enterprise-ssd
    EOT
  }
}

# ----------------------------------------
# 3. Load Helm values dynamically from cloned repo
data "local_file" "ssd_values" {
  filename   = "/workspace/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  depends_on = [null_resource.clone_ssd_chart]
}

# ----------------------------------------
# 4. Deploy Helm release(s) with upgrade support
resource "helm_release" "opsmx_ssd" {
  for_each   = toset(var.ingress_hosts)
  depends_on = [null_resource.clone_ssd_chart, kubernetes_namespace.opmsx_ns]

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = kubernetes_namespace.opmsx_ns.metadata[0].name
  chart      = "/workspace/enterprise-ssd/charts/ssd"
  values     = [data.local_file.ssd_values.content]

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

  force_update      = true
  recreate_pods     = true
  cleanup_on_fail   = true
  wait              = true
  atomic            = true  # rollback if upgrade fails

  lifecycle {
    replace_triggered_by = [null_resource.clone_ssd_chart]
  }
}
