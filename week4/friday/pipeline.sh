#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="${SCRIPT_DIR}/terraform"
ANSIBLE_DIR="${SCRIPT_DIR}/ansible"
INVENTORY="${ANSIBLE_DIR}/inventory.ini"

# --- Phase 1: Terraform ---
echo "=== Phase 1: Terraform Apply ==="
terraform -chdir="${TF_DIR}" init -input=false
terraform -chdir="${TF_DIR}" apply -auto-approve -input=false

# --- Phase 2: Extract IPs into Ansible inventory ---
echo "=== Phase 2: Writing Ansible inventory ==="
terraform -chdir="${TF_DIR}" output -raw ansible_inventory > "${INVENTORY}"
echo ""
echo "Inventory written to ${INVENTORY}:"
cat "${INVENTORY}"
echo ""

# --- Phase 3: Ansible ---
echo "=== Phase 3: Ansible Playbook ==="
ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg" \
  ansible-playbook -i "${INVENTORY}" "${ANSIBLE_DIR}/kijanikiosk.yml"

echo "=== Pipeline complete ==="