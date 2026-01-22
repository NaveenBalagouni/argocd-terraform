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
  # When running in a K8s Job, this automatically uses the Pod's ServiceAccount
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
    # Prevents errors if the namespace already exists in the cluster
    ignore_changes = all
  }
}

########################
# 1. Clone the Repository
########################
resource "null_resource" "clone_ssd_chart" {
  triggers = {
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
# 2. Load YAML Content (Apply-time only)
########################
# Using a data source with depends_on solves the "file does not exist" plan error
data "local_file" "ssd_values" {
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  depends_on = [null_resource.clone_ssd_chart]
}

########################
# 3. OpsMx SSD Helm Release
########################
resource "helm_release" "opsmx_ssd" {
  for_each = toset(var.ingress_hosts)

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = kubernetes_namespace.ssd.metadata[0].name
  
  # Path to the chart directory inside the cloned repo
  chart      = "/tmp/enterprise-ssd/charts/ssd"

  # We pass the loaded content from the data source to avoid unmarshaling errors
  values = [
    data.local_file.ssd_values.content
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

  # Ensure everything is cloned and read before Helm starts
  depends_on = [
    null_resource.clone_ssd_chart,
    data.local_file.ssd_values
  ]
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
