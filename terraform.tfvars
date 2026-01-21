git_repo_url           = "https://github.com/OpsMx/enterprise-ssd.git"
git_branch             = "2025-09" # initial installation branch
kubeconfig_path        = "/home/admins/snap/kubectl/ssd-use.config"
ingress_hosts          = ["tf-ssd-test.ssd-uat.opsmx.org"]
# Chart version to upgrade to
namespace              = "tf-ssd"
cert_manager_installed = true
