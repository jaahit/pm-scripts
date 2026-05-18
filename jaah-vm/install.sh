#!/bin/bash
# jaah-vm/install.sh — Bootstrap jaah-vm on a Proxmox cluster node.
# Idempotent: safe to re-run for upgrades.

set -Eeuo pipefail

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

# ────────────────────────────────────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────────────────────────────────────
log()  { printf "\033[1;36m[*]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[✗]\033[0m %s\n" "$*" >&2; exit 1; }

# ────────────────────────────────────────────────────────────────────────────
# Pre-flight
# ────────────────────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || fail "Run as root (sudo bash install.sh)"
command -v qm >/dev/null || fail "qm not found — must run on a Proxmox VE node"
command -v pvecm >/dev/null || fail "pvecm not found — Proxmox cluster tooling required"

log "Detected node: $(hostname -s)"
log "PVE version:   $(pveversion 2>/dev/null | head -1)"

# Cluster check (this tool only runs on cluster members)
if ! pvecm status >/dev/null 2>&1; then
    fail "Not in a Proxmox cluster — jaah-vm only supports cluster nodes (pmx-01/02/06)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Dependencies
# ────────────────────────────────────────────────────────────────────────────
log "Installing dependencies (jq, bats, openssl, python3)"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    jq bats openssl python3 python3-yaml 2>&1 | tail -3

# ────────────────────────────────────────────────────────────────────────────
# Install dispatcher + lib + completion + logrotate
# ────────────────────────────────────────────────────────────────────────────
log "Installing /usr/local/bin/jaah-vm"
install -o root -g root -m 755 "$SELF_DIR/jaah-vm" /usr/local/bin/jaah-vm

log "Installing /usr/local/lib/jaah-vm/"
install -d -o root -g root -m 755 /usr/local/lib/jaah-vm
install -o root -g root -m 644 "$SELF_DIR/lib-common.sh" /usr/local/lib/jaah-vm/

log "Installing bash completion"
install -o root -g root -m 644 "$SELF_DIR/completion.bash" /etc/bash_completion.d/jaah-vm

log "Installing logrotate"
install -o root -g root -m 644 "$SELF_DIR/logrotate.conf" /etc/logrotate.d/jaah-vm

# ────────────────────────────────────────────────────────────────────────────
# Bootstrap /etc/jaah/  (idempotent)
# ────────────────────────────────────────────────────────────────────────────
log "Bootstrapping /etc/jaah/"
install -d -o root -g root -m 700 /etc/jaah
install -d -o root -g root -m 755 /etc/jaah/keys

# SSH key — only if missing
if [ ! -f /etc/jaah/keys/default.pub ]; then
    # Try common locations in order
    SSH_SRC=""
    for cand in /root/.ssh/id_ed25519.pub /root/.ssh/id_rsa.pub; do
        if [ -f "$cand" ]; then SSH_SRC="$cand"; break; fi
    done
    if [ -z "$SSH_SRC" ]; then
        warn "No SSH public key found in /root/.ssh/"
        warn "Generate one (ssh-keygen -t ed25519), then place at /etc/jaah/keys/default.pub"
    else
        install -o root -g root -m 644 "$SSH_SRC" /etc/jaah/keys/default.pub
        ok "Installed default SSH key from $SSH_SRC"
    fi
else
    ok "SSH key already present"
fi

# Secrets file — install example if missing, leave existing alone
if [ ! -f /etc/jaah/vm-secrets.env ]; then
    install -o root -g root -m 600 "$SELF_DIR/vm-secrets.env.example" /etc/jaah/vm-secrets.env
    warn "Installed /etc/jaah/vm-secrets.env from example."
    warn "Edit it now to set VM_DEFAULT_PASSWORD:  ${EDITOR:-vim} /etc/jaah/vm-secrets.env"
else
    # Verify perms strict
    cur=$(stat -c '%U:%a' /etc/jaah/vm-secrets.env)
    if [ "$cur" != "root:600" ]; then
        warn "Fixing perms on /etc/jaah/vm-secrets.env (was $cur)"
        chmod 600 /etc/jaah/vm-secrets.env
        chown root:root /etc/jaah/vm-secrets.env
    fi
    ok "Secrets file already present"
fi


# ────────────────────────────────────────────────────────────────────────────
# Final health check
# ────────────────────────────────────────────────────────────────────────────
echo ""
log "Running jaah-vm doctor:"
echo ""
jaah-vm doctor || true

echo ""
ok "Install complete — try: jaah-vm types"
echo ""
log "Next: source /etc/bash_completion.d/jaah-vm  (or open a new shell)"
log "Then: jaah-vm create --name test-01 --type tiny --dry-run"
