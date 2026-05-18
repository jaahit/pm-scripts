#!/bin/bash
# lib-common.sh — Shared functions for jaah-vm (sourced by dispatcher)
#
# Provides:
#   - Strict-mode setup + trap helpers
#   - Structured logging with sanitization
#   - Secrets file parsing (parse, never source)
#   - Ownership manifest (pmxcfs-replicated file existence as marker)
#   - Cluster-wide locking via pmxcfs atomic-mkdir
#   - is_managed + verify_ownership
#   - VMID allocator with anchored regex (no greedy-match data loss)
#
# Required env-vars set by dispatcher before sourcing:
#   JAAH_VM_VERSION    — semver string for VM Notes
#
# Strict mode notes: -E required for trap inheritance into functions.

# Don't fail if sourced multiple times
[ -n "${_JAAH_LIB_LOADED:-}" ] && return 0
_JAAH_LIB_LOADED=1

set -Eeuo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Paths (constants — overridable via env for tests)
# ────────────────────────────────────────────────────────────────────────────
JAAH_ETC="${JAAH_ETC:-/etc/jaah}"
JAAH_SECRETS="${JAAH_SECRETS:-${JAAH_ETC}/vm-secrets.env}"
JAAH_KEYS_DIR="${JAAH_KEYS_DIR:-${JAAH_ETC}/keys}"
JAAH_LOG="${JAAH_LOG:-/var/log/jaah-vm.log}"
JAAH_STATE="${JAAH_STATE:-/var/lib/jaah-vm}"
JAAH_RECIPES="${JAAH_RECIPES:-${JAAH_STATE}/recipes}"
JAAH_ORPHANS="${JAAH_ORPHANS:-${JAAH_STATE}/orphans}"
JAAH_RUN="${JAAH_RUN:-/run/jaah-vm}"
JAAH_LOCK="${JAAH_LOCK:-/etc/pve/jaah-vm.lock.d}"
JAAH_MANIFEST_DIR="${JAAH_MANIFEST_DIR:-/etc/pve/jaah-vm}"
JAAH_SNIPPETS_PATH="${JAAH_SNIPPETS_PATH:-/mnt/pve/iso-library/snippets/jaah-vm}"

# Cluster constants — keep aligned with infrastructure
readonly TEMPLATE_VMID=9000
readonly TEMPLATE_NAME="ubuntu-26.04-tmpl"
readonly TEMPLATE_STORAGE="iso-library"
readonly CLOUD_IMG="/mnt/pve/iso-library/template/iso/ubuntu-26.04-server-cloudimg-amd64.img"

# ────────────────────────────────────────────────────────────────────────────
# Logging + sanitization
# ────────────────────────────────────────────────────────────────────────────

# Argv positions whose values must be redacted in log lines.
# Whitelist approach: only redact known-secret flags by position (not keyword guess).
_REDACT_FLAGS='--cipassword|--password|--token|--secret'

# Redact secrets from a line by replacing the arg AFTER any flag in _REDACT_FLAGS.
sanitize_line() {
    awk -v R="^(${_REDACT_FLAGS})\$" '
    {
        out = ""
        for (i=1; i<=NF; i++) {
            if (i > 1 && prev ~ R) {
                out = out " ***"
            } else {
                out = out " " $i
            }
            prev = $i
        }
        sub(/^ /, "", out)
        print out
    }'
}

# Timestamped log writer; appends to JAAH_LOG and also stderr for live feedback.
_log_to() {
    local level="$1"; shift
    # If log isn't writable (dev env, tests), silently skip — never block.
    [ -w "$JAAH_LOG" ] 2>/dev/null || { [ ! -e "$JAAH_LOG" ] && touch "$JAAH_LOG" 2>/dev/null; }
    [ -w "$JAAH_LOG" ] 2>/dev/null || return 0
    local ts host msg
    ts=$(date -u +%FT%TZ)
    host=$(hostname -s)
    msg=$(printf '%s' "$*" | sanitize_line)
    printf '%s | %s | %-5s | %s\n' "$ts" "$host" "$level" "$msg" >> "$JAAH_LOG" 2>/dev/null || true
}

# All status output goes to stderr so functions can return values via stdout
# (e.g. `IP=$(_wait_for_ip ...)` without contaminating the captured value).
log()  { local m; m=$(printf '%s' "$*" | sanitize_line); printf '\033[1;36m[*]\033[0m %s\n' "$m" >&2; _log_to INFO  "$*"; }
ok()   { local m; m=$(printf '%s' "$*" | sanitize_line); printf '\033[1;32m[✓]\033[0m %s\n' "$m" >&2; _log_to OK    "$*"; }
warn() { local m; m=$(printf '%s' "$*" | sanitize_line); printf '\033[1;33m[!]\033[0m %s\n' "$m" >&2; _log_to WARN  "$*"; }
fail() { local m; m=$(printf '%s' "$*" | sanitize_line); printf '\033[1;31m[✗]\033[0m %s\n' "$m" >&2; _log_to ERROR "$*"; exit 1; }

# ────────────────────────────────────────────────────────────────────────────
# Secrets (parse, never source — secrets file must not be executed as code)
# ────────────────────────────────────────────────────────────────────────────

# check_secrets_safe — verify file ownership + perms before reading
check_secrets_safe() {
    [ -f "$JAAH_SECRETS" ] || fail "Missing secrets file: $JAAH_SECRETS"
    local s
    s=$(stat -c '%U:%a' "$JAAH_SECRETS" 2>/dev/null) || fail "Cannot stat $JAAH_SECRETS"
    [ "$s" = "root:600" ] || fail "Bad ownership/perms on $JAAH_SECRETS (got $s, want root:600)"
    s=$(stat -c '%U:%a' "$JAAH_ETC" 2>/dev/null) || fail "Cannot stat $JAAH_ETC"
    [ "$s" = "root:700" ] || fail "Bad ownership/perms on $JAAH_ETC (got $s, want root:700)"
}

# read_secret <KEY> — parses KEY=value line, strips surrounding quotes.
# Returns empty string if key missing; never returns code execution.
read_secret() {
    local key="$1"
    [ -r "$JAAH_SECRETS" ] || fail "Secrets unreadable: $JAAH_SECRETS"
    local line=""
    line=$(grep -E "^${key}=" "$JAAH_SECRETS" 2>/dev/null | head -1) || true
    [ -z "$line" ] && return 0
    printf '%s' "$line" | cut -d= -f2- | sed -E 's/^["'\'']//; s/["'\'']$//'
}

# ────────────────────────────────────────────────────────────────────────────
# Ownership marker (manifest file, pmxcfs-replicated)
# ────────────────────────────────────────────────────────────────────────────
# Single-operator cluster: ownership = manifest file existence.
# Threat model: anyone with root could `qm destroy` directly anyway, so adding
# crypto signatures would protect against a sceanrio that doesn't exist here.
# Protection comes from: manifest existence + typed-name confirmation.

# write_manifest <vmid> <name> — atomically create pmxcfs-replicated manifest.
write_manifest() {
    local vmid="$1" name="$2"
    local created
    created=$(date -u +%FT%TZ)
    mkdir -p "$JAAH_MANIFEST_DIR"
    local tmp="${JAAH_MANIFEST_DIR}/.${vmid}.json.tmp"
    cat > "$tmp" <<EOF
{"vmid":${vmid},"name":"${name}","created":"${created}","version":"${JAAH_VM_VERSION:-unknown}"}
EOF
    mv -f "$tmp" "${JAAH_MANIFEST_DIR}/${vmid}.json"
}

# verify_ownership <vmid> — fail unless manifest exists. Read-and-validate JSON shape.
verify_ownership() {
    local vmid="$1"
    local manifest="${JAAH_MANIFEST_DIR}/${vmid}.json"
    [ -f "$manifest" ] || fail "No ownership manifest for VMID $vmid — not managed by jaah-vm. Use 'qm destroy' if you own it."
    jq -e '.vmid and .name' "$manifest" >/dev/null 2>&1 \
        || fail "Bad manifest JSON: $manifest"
}

# is_managed <vmid> — silent yes/no via exit code (0=managed, 1=not).
is_managed() {
    local vmid="$1"
    local manifest="${JAAH_MANIFEST_DIR}/${vmid}.json"
    [ -f "$manifest" ] || return 1
    jq -e '.vmid and .name' "$manifest" >/dev/null 2>&1
}

# remove_manifest <vmid> — clean up after destroy.
remove_manifest() {
    rm -f "${JAAH_MANIFEST_DIR}/${1}.json"
}

# ────────────────────────────────────────────────────────────────────────────
# Cluster-wide locking via pmxcfs atomic mkdir
# ────────────────────────────────────────────────────────────────────────────
# mkdir on pmxcfs is atomic and propagates as a single transaction across the
# cluster. flock(2) is NOT cluster-safe on FUSE; this is the correct pattern.

with_cluster_lock() {
    local now me tries=0 age=0
    now=$(date +%s)
    me="$(hostname -s)-$$"

    while ! mkdir "$JAAH_LOCK" 2>/dev/null; do
        # Stale-lock detection: if owner file > 90s old, break it.
        if [ -f "${JAAH_LOCK}/owner" ]; then
            age=$(( now - $(stat -c %Y "${JAAH_LOCK}/owner" 2>/dev/null || printf '%d' "$now") ))
            if [ "$age" -gt 90 ]; then
                warn "Breaking stale cluster lock (age ${age}s)"
                rm -rf "$JAAH_LOCK"
                continue
            fi
        fi
        tries=$((tries + 1))
        if [ "$tries" -gt 120 ]; then
            fail "Cluster lock contention — 60s timeout exceeded"
        fi
        sleep 0.5
        now=$(date +%s)
    done

    # We hold the lock. Record owner and ensure release on any exit path.
    echo "$me $(date -u +%FT%TZ)" > "${JAAH_LOCK}/owner"

    # Capture caller's traps so we restore them — but we MUST always rm -rf the lock.
    local rc=0
    _release_lock() { rm -rf "$JAAH_LOCK" 2>/dev/null || true; }

    # Run the wrapped command. Use || rc=$? so set -e doesn't swallow it.
    "$@" || rc=$?

    _release_lock
    return "$rc"
}

# ────────────────────────────────────────────────────────────────────────────
# VMID allocator — strict anchored-regex probing (no greedy-match data loss)
# ────────────────────────────────────────────────────────────────────────────

# _vmid_in_use <id> — returns 0 if any artifact for this VMID exists.
# Uses anchored regex so VMID=10 does NOT match vm-100-disk-0.
_vmid_in_use() {
    local id="$1"
    [ -f "/etc/pve/qemu-server/${id}.conf" ] && return 0
    [ -f "/etc/pve/lxc/${id}.conf" ] && return 0
    # LVM logical volumes — anchored boundaries
    if lvs --noheadings -o lv_name 2>/dev/null \
        | awk -v id="$id" '$1 ~ "^vm-"id"-disk-[0-9]+$" {found=1} END {exit !found}'; then
        return 0
    fi
    # ZFS datasets — anchored numeric suffix to avoid vm-10 matching vm-100
    if zfs list -H -o name 2>/dev/null \
        | grep -qE "/vm-${id}-disk-[0-9]+\$"; then
        return 0
    fi
    return 1
}

# allocate_vmid — cluster-aware next-id, with conflict probing.
# MUST be called inside with_cluster_lock.
allocate_vmid() {
    local id
    id=$(pvesh get /cluster/nextid 2>/dev/null) || fail "pvesh nextid failed"
    while _vmid_in_use "$id"; do
        id=$((id + 1))
    done
    printf '%s' "$id"
}

# ────────────────────────────────────────────────────────────────────────────
# Cluster + environment guards
# ────────────────────────────────────────────────────────────────────────────

require_root() {
    [ "$(id -u)" -eq 0 ] || fail "Must run as root"
}

require_cluster_member() {
    # We only support cluster nodes — refuse on standalone (pmx-03/04/05).
    command -v pvecm >/dev/null || fail "pvecm not found — is this a PVE node?"
    local rc=0
    pvecm status >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 0 ] || fail "Not in a Proxmox cluster — jaah-vm requires a cluster member (pmx-01/02/06)"
}

require_quorum() {
    local rc=0
    pvecm status 2>/dev/null | grep -q '^Quorate:.*Yes' || rc=$?
    [ "$rc" -eq 0 ] || fail "Cluster not quorate — refusing to operate"
}

# feature_detect — verify PVE version + binary deps.
# We rely on virtio-scsi-single + iothread (both stable since PVE 5.x), so the
# PVE >= 8.0 floor is the real check. `qm --help` doesn't always advertise
# these flags in its short help (PVE 9.x dropped enum lists), so we don't grep.
feature_detect() {
    local pve_ver pve_major
    pve_ver=$(pveversion 2>/dev/null | awk -F'[/-]' '/pve-manager/{print $2}' | head -1)
    if [ -z "$pve_ver" ]; then
        pve_ver=$(pveversion 2>/dev/null | head -1 | awk -F'/' '{print $2}' | awk -F- '{print $1}')
    fi
    pve_major=$(printf '%s' "$pve_ver" | awk -F. '{print $1}')
    if [ -z "$pve_major" ] || [ "$pve_major" -lt 8 ] 2>/dev/null; then
        fail "PVE too old: need 8.0+ (detected '$pve_ver')"
    fi
    command -v openssl >/dev/null || fail "Missing dependency: openssl"
    command -v jq >/dev/null || fail "Missing dependency: jq"
}

# ────────────────────────────────────────────────────────────────────────────
# Storage helpers
# ────────────────────────────────────────────────────────────────────────────

# storage_type <name> — returns nfs|dir|cifs|btrfs|zfspool|lvm|lvmthin|...
storage_type() {
    pvesm status -storage "$1" 2>/dev/null | awk 'NR>1{print $2}'
}

# storage_free_mb <name> — returns AVAILABLE space, not used. (column 6 from pvesm)
storage_free_mb() {
    local kb
    kb=$(pvesm status -storage "$1" 2>/dev/null | awk 'NR>1{print $6}')
    echo $(( ${kb:-0} / 1024 ))
}

# storage_supports <name> — does storage exist and is it active?
storage_active() {
    pvesm status -storage "$1" 2>/dev/null | awk 'NR>1{print $3}' | grep -q '^active$'
}

# ────────────────────────────────────────────────────────────────────────────
# String validation
# ────────────────────────────────────────────────────────────────────────────

validate_name() {
    local n="$1"
    [[ "$n" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] \
        || fail "Invalid name '$n' (must be lowercase a-z0-9- and 1-63 chars, no leading/trailing dash)"
}

# sanitize_tag — Proxmox tags accept [a-z0-9_-] only.
sanitize_tag() {
    printf '%s' "$1" | tr 'A-Z.' 'a-z-' | tr -cd 'a-z0-9_-'
}

# ────────────────────────────────────────────────────────────────────────────
# State directories — created on first use
# ────────────────────────────────────────────────────────────────────────────

ensure_state_dirs() {
    install -m 700 -d "$JAAH_STATE" "$JAAH_RECIPES" "$JAAH_RUN" 2>/dev/null || true
    install -m 755 -d "$JAAH_MANIFEST_DIR" 2>/dev/null || true
    touch "$JAAH_LOG" 2>/dev/null || true
    chmod 640 "$JAAH_LOG" 2>/dev/null || true
}

# ────────────────────────────────────────────────────────────────────────────
# Find VMID by name (among managed VMs only)
# ────────────────────────────────────────────────────────────────────────────

resolve_target() {
    local arg="$1"
    if [[ "$arg" =~ ^[0-9]+$ ]]; then
        printf '%s' "$arg"
        return 0
    fi
    # Search ownership manifests for matching name
    local m
    for m in "$JAAH_MANIFEST_DIR"/*.json; do
        [ -e "$m" ] || continue
        local name vmid
        name=$(jq -r '.name' "$m" 2>/dev/null)
        vmid=$(jq -r '.vmid' "$m" 2>/dev/null)
        if [ "$name" = "$arg" ]; then
            printf '%s' "$vmid"
            return 0
        fi
    done
    return 1
}
