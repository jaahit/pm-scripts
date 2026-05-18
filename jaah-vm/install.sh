#!/bin/bash
# jaah-vm/install.sh — Bootstrap jaah-vm on a Proxmox cluster node.
# Idempotent: safe to re-run for upgrades.
#
# FLAGS:
#   --generate-fresh-key   Generate a NEW ed25519 keypair for VM access. The
#                          PRIVATE key is printed ONCE to stdout (copy it now,
#                          there is no second chance). Only the public key is
#                          saved to /etc/jaah/keys/default.pub.
#                          Replaces any existing default.pub.

set -Eeuo pipefail

SELF_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)

# ────────────────────────────────────────────────────────────────────────────
# Args
# ────────────────────────────────────────────────────────────────────────────
GEN_FRESH_KEY="no"
while [ $# -gt 0 ]; do
    case "$1" in
        --generate-fresh-key) GEN_FRESH_KEY="yes"; shift;;
        --help|-h)
            sed -n '2,/^set -/p' "$0" | sed 's/^# \{0,1\}//; /^set -/d'
            exit 0;;
        *) echo "Unknown flag: $1 (use --help)" >&2; exit 1;;
    esac
done

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
log "Installing dependencies (jq, bats, openssl, python3, whiptail)"
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    jq bats openssl python3 python3-yaml whiptail 2>&1 | tail -3

# ────────────────────────────────────────────────────────────────────────────
# Install dispatcher + lib + completion + logrotate
# ────────────────────────────────────────────────────────────────────────────
log "Installing /usr/local/bin/jaah-vm"
install -o root -g root -m 755 "$SELF_DIR/jaah-vm" /usr/local/bin/jaah-vm

log "Installing /usr/local/lib/jaah-vm/"
install -d -o root -g root -m 755 /usr/local/lib/jaah-vm
install -o root -g root -m 644 "$SELF_DIR/lib-common.sh" /usr/local/lib/jaah-vm/

# Embed git SHA so `jaah-vm --version` shows it without git working tree.
if git -C "$SELF_DIR/.." rev-parse --short HEAD &>/dev/null; then
    SHA=$(git -C "$SELF_DIR/.." rev-parse --short HEAD)
    install -o root -g root -m 644 /dev/stdin /usr/local/lib/jaah-vm/git-sha <<< "$SHA"
fi

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

# ────────────────────────────────────────────────────────────────────────────
# SSH key handling
# ────────────────────────────────────────────────────────────────────────────
# Modes:
#   --generate-fresh-key  → make a NEW ed25519, print private once, save public
#   default               → reuse /root/.ssh/id_ed25519.pub or id_rsa.pub
# ────────────────────────────────────────────────────────────────────────────
generate_fresh_key() {
    log "Generating fresh ed25519 keypair for VM access"
    local tmpdir
    tmpdir=$(mktemp -d -t jaah-keygen.XXXXXX)
    chmod 700 "$tmpdir"
    # The private key never leaves $tmpdir; we shred it after print.
    ssh-keygen -q -t ed25519 -N "" -C "jaah-vm-access-$(hostname -s)-$(date +%Y%m%d)" \
        -f "$tmpdir/key"

    # Save PUBLIC key to /etc/jaah/keys/default.pub (replace existing)
    install -o root -g root -m 644 "$tmpdir/key.pub" /etc/jaah/keys/default.pub

    local fp
    fp=$(ssh-keygen -lf "$tmpdir/key.pub" | awk '{print $2}')

    # Print private key ONCE — between distinctive markers for easy copy-paste
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════"
    echo "  ⚠  COPY THIS PRIVATE KEY NOW — IT WILL NOT BE SHOWN AGAIN"
    echo "════════════════════════════════════════════════════════════════════════════"
    echo ""
    cat "$tmpdir/key"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════"
    echo "  Public key fingerprint:"
    echo "    $fp"
    echo "    (saved to /etc/jaah/keys/default.pub)"
    echo ""
    echo "  Save the lines above (BEGIN to END inclusive) on your local machine:"
    echo ""
    echo "    Linux/Mac:"
    echo "      vim ~/.ssh/jaah-vm-access     # paste; save"
    echo "      chmod 600 ~/.ssh/jaah-vm-access"
    echo "      ssh -i ~/.ssh/jaah-vm-access ibra@<vm-ip>"
    echo ""
    echo "    Windows (modern PuTTY/WinSCP/VS Code):"
    echo "      Save as: C:\\Users\\YOU\\.ssh\\jaah-vm-access  (no extension)"
    echo "      Modern PuTTY (0.75+) loads OpenSSH format directly."
    echo ""
    echo "    Windows (older PuTTY needing .ppk):"
    echo "      Open PuTTYgen → Load → choose the saved file →"
    echo "      Save private key → jaah-vm-access.ppk"
    echo "      (or on Linux:  puttygen jaah-vm-access -O private -o jaah-vm-access.ppk)"
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════"
    echo ""

    # Securely delete the private key from disk + memory
    shred -u "$tmpdir/key" 2>/dev/null || rm -f "$tmpdir/key"
    rm -rf "$tmpdir"
    ok "Fresh keypair generated. Private key shown above — copy it now."
}

if [ "$GEN_FRESH_KEY" = "yes" ]; then
    if [ -f /etc/jaah/keys/default.pub ]; then
        warn "Existing /etc/jaah/keys/default.pub will be REPLACED."
        warn "Existing VMs will NOT accept the new key (only future ones)."
    fi
    generate_fresh_key
elif [ ! -f /etc/jaah/keys/default.pub ]; then
    # Try common locations in order
    SSH_SRC=""
    for cand in /root/.ssh/id_ed25519.pub /root/.ssh/id_rsa.pub; do
        if [ -f "$cand" ]; then SSH_SRC="$cand"; break; fi
    done
    if [ -z "$SSH_SRC" ]; then
        warn "No SSH public key found in /root/.ssh/"
        warn "Re-run with --generate-fresh-key to create one, or place your own"
        warn "public key at /etc/jaah/keys/default.pub manually."
    else
        install -o root -g root -m 644 "$SSH_SRC" /etc/jaah/keys/default.pub
        ok "Installed default SSH key from $SSH_SRC"
    fi
else
    ok "SSH key already present (pass --generate-fresh-key to replace)"
fi

# ────────────────────────────────────────────────────────────────────────────
# Secrets file
# ────────────────────────────────────────────────────────────────────────────
if [ ! -f /etc/jaah/vm-secrets.env ]; then
    install -o root -g root -m 600 "$SELF_DIR/vm-secrets.env.example" /etc/jaah/vm-secrets.env
    warn "Installed /etc/jaah/vm-secrets.env from example."
    warn "Edit it now to set VM_DEFAULT_PASSWORD:  ${EDITOR:-vim} /etc/jaah/vm-secrets.env"
else
    cur=$(stat -c '%U:%a' /etc/jaah/vm-secrets.env)
    if [ "$cur" != "root:600" ]; then
        warn "Fixing perms on /etc/jaah/vm-secrets.env (was $cur)"
        chmod 600 /etc/jaah/vm-secrets.env
        chown root:root /etc/jaah/vm-secrets.env
    fi
    ok "Secrets file already present"
fi

# ────────────────────────────────────────────────────────────────────────────
# Final health check + summary
# ────────────────────────────────────────────────────────────────────────────
echo ""
log "Running jaah-vm doctor:"
echo ""
jaah-vm doctor || true

# Resolve fingerprint for the summary block
KEY_FP="(missing)"
if [ -r /etc/jaah/keys/default.pub ]; then
    KEY_FP=$(ssh-keygen -lf /etc/jaah/keys/default.pub 2>/dev/null | awk '{print $1, $2}')
fi

echo ""
echo "══════════════════════════════════════════════════════════════════════"
echo "  ✓ jaah-vm installed on $(hostname -s)"
echo "══════════════════════════════════════════════════════════════════════"
echo "  Tool:       /usr/local/bin/jaah-vm  ($(jaah-vm --version 2>/dev/null))"
echo "  Lib:        /usr/local/lib/jaah-vm/lib-common.sh"
echo "  Config:     /etc/jaah/"
echo "                 secrets:  /etc/jaah/vm-secrets.env"
echo "                 SSH key:  /etc/jaah/keys/default.pub"
echo "                 fp:       ${KEY_FP}"
echo "  Logs:       /var/log/jaah-vm.log"
echo "  Completion: /etc/bash_completion.d/jaah-vm"
echo ""
echo "  Next steps:"
echo "    1. source /etc/bash_completion.d/jaah-vm"
echo "    2. jaah-vm types"
echo "    3. jaah-vm create --name test-01 --type tiny --dry-run"
echo "    4. jaah-vm create --name test-01 --type tiny --start --wait-ssh"
echo "══════════════════════════════════════════════════════════════════════"
