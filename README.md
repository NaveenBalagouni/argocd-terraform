# argocd-terraform

“Terraform Automation for SSD Instance Setup for SaaS Profile.”

Connects to the Kubernetes cluster using kubeconfig.

Ensures the target namespace exists and is protected.

Clones the OpsMx SSD Helm chart from Git.

Loads Helm configuration (values.yaml) from Git for version control.

Deploys SSD using Helm with safe, atomic installation settings.

Configures ingress and SSD UI hostname dynamically.

Automatically re-deploys if Git repo or branch changes.

Exposes Helm release names and namespaces for validation.

Runs fully inside Kubernetes via a Job for repeatable, GitOps-style automation.
