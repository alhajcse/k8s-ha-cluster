# ============================================================
# Terraform: Generate Ansible inventory
# ============================================================

terraform {
  # Minimum Terraform version
  required_version = ">= 1.5.0"

  # Provider = plugin যেটা resource তৈরি করে
  required_providers {
    # local provider = local file তৈরি করতে
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# ------------------------------------------------------------
# Variables (variables.tf থেকে আসে)
# ------------------------------------------------------------
locals {
  # Control Plane nodes
  cp_nodes = [
    { name = "k8s-cp-01", ip = var.cp1_ip },
    { name = "k8s-cp-02", ip = var.cp2_ip },
    { name = "k8s-cp-03", ip = var.cp3_ip },
  ]

  # Worker nodes (এখন ২টা, পরে আরো যোগ করা যাবে)
  worker_nodes = [
    { name = "k8s-worker-01", ip = var.worker1_ip },
    { name = "k8s-worker-02", ip = var.worker2_ip },
    { name = "k8s-worker-03", ip = var.worker3_ip },  # ⭐ New node
  ]
}

# ------------------------------------------------------------
# Resource: Ansible inventory file তৈরি করা
# ------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  # File location
  filename = "${path.module}/../../../ansible/inventory/local/hosts.ini"

  # Template থেকে content generate
  content = templatefile("${path.module}/templates/inventory.tpl", {
    cp_nodes     = local.cp_nodes
    worker_nodes = local.worker_nodes
    vm_user      = var.vm_user
    ssh_key      = var.ssh_key
  })
}
