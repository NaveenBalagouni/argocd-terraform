terraform {
  required_version = ">= 1.0.0"
  
  # CRITICAL: Store state in K8s so the Job remembers previous runs
  backend "kubernetes" {
    secret_suffix    = "ssd-state"
    namespace        = "tf-ssd"
    in_cluster_config = true
  }

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
  # When running inside a Job, it uses the ServiceAccount token automatically
}

provider "helm" {
  kubernetes {
    # Uses ServiceAccount token automatically
  }
}

resource "kubernetes_namespace" "opmsx_ns" {
  metadata {
    name = var.namespace
  }
}

# Clone the Helm Chart from Git
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

data "local_file" "ssd_values" {
  filename   = "/tmp/enterprise-ssd/charts/ssd/ssd-minimal-values.yaml"
  depends_on = [null_resource.clone_ssd_chart]
}

resource "helm_release" "opsmx_ssd" {
  for_each   = toset(var.ingress_hosts)
  depends_on = [null_resource.clone_ssd_chart, kubernetes_namespace.opmsx_ns]

  name       = "ssd-${replace(each.value, ".", "-")}"
  namespace  = kubernetes_namespace.opmsx_ns.metadata[0].name
  chart      = "/tmp/enterprise-ssd/charts/ssd"
  
  values = [data.local_file.ssd_values.content]

  set {
    name  = "ingress.enabled"
    value = "true"
  }

  set {
    name  = "global.certManager.installed"
    value = var.cert_manager_installed
  }

  set {
    name  = "global.ssdUI.host"
    value = each.value
  }

  # Safe Upgrade Settings
  force_update    = true
  recreate_pods   = true
  cleanup_on_fail = true
  wait            = true
  atomic          = true

  lifecycle {
    # If the git branch changes, Terraform will treat this as an upgrade trigger
    replace_triggered_by = [null_resource.clone_ssd_chart]
  }
}
