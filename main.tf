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

# 1. Ensure the namespace exists (Automated creation)
resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }
}

# 2. Clone/Update Helm Chart Repo
# The 'triggers' block ensures this runs again if the branch or URL changes
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

# 3. Dynamic Values loading
data "local_file" "ssd_values" {
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  depends_on = [null_resource.clone_ssd_chart]
}

# 4. SSD Helm Release with Upgrade Logic
resource "helm_release" "opsmx_ssd" {
  for_each   = toset(var.ingress_hosts)
  depends_on = [null_resource.clone_ssd_chart, kubernetes_namespace.opmsx_ns]

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = kubernetes_namespace.opmsx_ns.metadata[0].name
  chart      = "/tmp/enterprise-ssd/charts/ssd"
  
  
  # Inject values from the cloned git repo
  values = [data.local_file.ssd_values.content]

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

  # Upgrade Strategy Settings
  force_update      = true
  recreate_pods     = true
  cleanup_on_fail   = true
  wait              = true
  atomic            = false # Rolls back automatically if upgrade fails

  lifecycle {
    # This forces a re-deployment if the git metadata changes
    replace_triggered_by = [null_resource.clone_ssd_chart]
  }
}
