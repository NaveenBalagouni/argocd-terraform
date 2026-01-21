git_repo_url           = "https://github.com/OpsMx/enterprise-ssd.git"
git_branch             = "2025-06" # initial installation branch
kubeconfig_path        = ""
ingress_hosts          = ["ssd-tf-argocd.ssd-uat.opsmx.org"]
# Chart version to upgrade to
chart_version = "2025.07"
namespace              = "ssd-tf-argocd"
cert_manager_installed = true
