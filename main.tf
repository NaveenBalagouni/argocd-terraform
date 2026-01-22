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

provider "kubernetes" {}
provider "helm" {
  kubernetes {}
}

########################
# 1. Namespace - Data Source
########################
# Using 'data' instead of 'resource' prevents the "already exists" error
data "kubernetes_namespace" "ssd" {
  metadata {
    name = var.namespace
  }
}

########################
# 2. Clone the Repository
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
# 3. OpsMx SSD Helm Release
########################
resource "helm_release" "opsmx_ssd" {
  for_each = toset(var.ingress_hosts)

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = data.kubernetes_namespace.ssd.metadata[0].name
  
  # Point directly to the folder that will be created
  chart      = "/tmp/enterprise-ssd/charts/ssd"

  # We pass the PATH as a string, NOT the content via a function.
  # This prevents Terraform from looking for the file during the "Refresh" phase.
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
    name  = "global.ssdUI.host"
    value = each.value
  }

  # This ensures the clone finishes before Helm tries to read the path
  depends_on = [null_resource.clone_ssd_chart]
}
