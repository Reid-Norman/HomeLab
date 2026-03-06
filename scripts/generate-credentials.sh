#!/usr/bin/env bash
# Generates credentials for a specific stack and saves them to Ansible Vault.
# Usage: ./scripts/generate-credentials.sh <stack>
# Example: ./scripts/generate-credentials.sh semaphore
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_FILE="${REPO_ROOT}/ansible/group_vars/all/vault.yml"
STACK="${1:?Usage: $0 <stack-name>  (available: semaphore)}"

# Prompt for vault password once
read -s -p "Vault password: " VAULT_PASS
echo

# Temp files for vault operations
VAULT_PASS_FILE=$(mktemp)
TMPFILE=$(mktemp)
chmod 600 "$VAULT_PASS_FILE" "$TMPFILE"
echo "$VAULT_PASS" > "$VAULT_PASS_FILE"
trap 'rm -f "$VAULT_PASS_FILE" "$TMPFILE"' EXIT

# Decrypt current vault
if ! ansible-vault view "$VAULT_FILE" --vault-password-file="$VAULT_PASS_FILE" > "$TMPFILE" 2>/dev/null; then
    echo "Error: Failed to decrypt vault. Wrong password?"
    exit 1
fi

generate_password() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "${1:-32}"
}

var_exists() {
    grep -q "^${1}:" "$TMPFILE"
}

case "$STACK" in
    semaphore)
        if var_exists vault_semaphore_db_password; then
            echo "Semaphore credentials already exist in vault. Use 'make vault-edit' to modify."
            exit 0
        fi

        # Reuse LE email for admin email if available
        ADMIN_EMAIL=$(grep "^vault_le_email:" "$TMPFILE" | sed 's/^vault_le_email: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || echo "admin@localhost")

        DB_PASS=$(generate_password 32)
        ADMIN_PASS=$(generate_password 24)

        cat >> "$TMPFILE" << EOF

# Semaphore (auto-generated)
vault_semaphore_admin_user: "admin"
vault_semaphore_admin_name: "Admin"
vault_semaphore_admin_email: "${ADMIN_EMAIL}"
vault_semaphore_admin_password: "${ADMIN_PASS}"
vault_semaphore_db_password: "${DB_PASS}"
EOF

        echo ""
        echo "Generated Semaphore credentials:"
        echo "  Admin user:     admin"
        echo "  Admin email:    ${ADMIN_EMAIL}"
        echo "  Admin password: ${ADMIN_PASS}"
        echo "  DB password:    (saved to vault)"
        echo ""
        echo "Save the admin password above — it is only shown once."
        ;;
    *)
        echo "Unknown stack: ${STACK}"
        echo "Available stacks: semaphore"
        exit 1
        ;;
esac

# Re-encrypt vault with new values
ansible-vault encrypt "$TMPFILE" --vault-password-file="$VAULT_PASS_FILE" --output="$VAULT_FILE"

echo ""
echo "Credentials saved to vault."
echo "Next steps:"
echo "  make ansible-sync      # regenerate .env files"
echo "  make deploy-automation # deploy the stack"
