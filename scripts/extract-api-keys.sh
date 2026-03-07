#!/usr/bin/env bash
# Extracts API keys from running Radarr, Sonarr, and Prowlarr containers
# and saves them to Ansible Vault.
# Usage: ./scripts/extract-api-keys.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VAULT_FILE="${REPO_ROOT}/ansible/group_vars/all/vault.yml"

SERVICES=(radarr sonarr prowlarr)

# --- Vault password handling ---
read -r -s -p "Vault password: " VAULT_PASS
echo

VAULT_PASS_FILE=$(mktemp)
TMPFILE=$(mktemp)
chmod 600 "$VAULT_PASS_FILE" "$TMPFILE"
echo "$VAULT_PASS" > "$VAULT_PASS_FILE"
trap 'rm -f "$VAULT_PASS_FILE" "$TMPFILE"' EXIT

# Decrypt vault
if ! ansible-vault view "$VAULT_FILE" --vault-password-file="$VAULT_PASS_FILE" > "$TMPFILE" 2>/dev/null; then
    echo "Error: Failed to decrypt vault. Wrong password?"
    exit 1
fi

get_var() {
    grep "^${1}:" "$TMPFILE" | sed 's/^[^:]*: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/'
}

var_needs_value() {
    local name="$1"
    if ! grep -q "^${name}:" "$TMPFILE"; then
        return 0
    fi
    local current
    current=$(get_var "$name")
    [[ "$current" == REPLACE_* ]]
}

set_var() {
    local name="$1" value="$2"
    if grep -q "^${name}:" "$TMPFILE"; then
        # Remove existing line
        grep -v "^${name}:" "$TMPFILE" > "${TMPFILE}.new"
        mv "${TMPFILE}.new" "$TMPFILE"
    fi
    printf '%s: "%s"\n' "$name" "$value" >> "$TMPFILE"
}

CHANGED=false
echo ""

for service in "${SERVICES[@]}"; do
    vault_var="${service}_api_key"

    # Check if we already have a real value
    if ! var_needs_value "$vault_var"; then
        echo "  ${service}: API key already in vault (skipping)"
        continue
    fi

    # Check container is running
    if ! docker inspect --format='{{.State.Running}}' "$service" 2>/dev/null | grep -q true; then
        echo "  ${service}: container not running (skipping)"
        continue
    fi

    # Extract API key from config.xml
    api_key=$(docker exec "$service" cat /config/config.xml 2>/dev/null \
        | grep -o '<ApiKey>[^<]*</ApiKey>' \
        | sed 's/<ApiKey>\(.*\)<\/ApiKey>/\1/' || true)

    if [ -z "$api_key" ]; then
        echo "  ${service}: could not extract API key (skipping)"
        continue
    fi

    set_var "$vault_var" "$api_key"
    CHANGED=true
    echo "  ${service}: extracted API key ${api_key:0:8}..."
done

if [ "$CHANGED" = false ]; then
    echo ""
    echo "No new API keys extracted."
    exit 0
fi

# Re-encrypt vault
ansible-vault encrypt "$TMPFILE" --vault-password-file="$VAULT_PASS_FILE" --output="$VAULT_FILE"

echo ""
echo "API keys saved to vault."
echo "Next step:"
echo "  make ansible-sync   # regenerate .env files and configure services"
