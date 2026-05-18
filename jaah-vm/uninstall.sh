#!/bin/bash
# jaah-vm/uninstall.sh — Cleanly remove jaah-vm from a node.
#
# By default, preserves /etc/jaah/ (secrets + keys) and
# /var/lib/jaah-vm/ (recipes) in case you reinstall later.
# Pass --purge to wipe those too.

set -Eeuo pipefail

log()  { printf "\033[1;36m[*]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[✓]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[!]\033[0m %s\n" "$*"; }
fail() { printf "\033[1;31m[✗]\033[0m %s\n" "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "Run as root"

PURGE="no"
[ "${1:-}" = "--purge" ] && PURGE="yes"

log "Removing jaah-vm installed files"

rm -f /usr/local/bin/jaah-vm                              && ok "rm /usr/local/bin/jaah-vm" || true
rm -rf /usr/local/lib/jaah-vm                             && ok "rm /usr/local/lib/jaah-vm" || true
rm -f /etc/bash_completion.d/jaah-vm                      && ok "rm /etc/bash_completion.d/jaah-vm" || true
rm -f /etc/logrotate.d/jaah-vm                            && ok "rm /etc/logrotate.d/jaah-vm" || true

if [ "$PURGE" = "yes" ]; then
    warn "Purging /etc/jaah/ (secrets, SSH key)"
    warn "Purging /var/lib/jaah-vm/ (recipes, orphans log)"
    read -rp "Confirm by typing 'PURGE': " confirm
    [ "$confirm" = "PURGE" ] || fail "Aborted"
    rm -rf /etc/jaah /var/lib/jaah-vm /run/jaah-vm /var/log/jaah-vm.log
    # cluster-wide pmxcfs state (will replicate the removal)
    rm -rf /etc/pve/jaah-vm /etc/pve/jaah-vm.lock.d 2>/dev/null || true
    ok "Purged"
else
    log "Preserved /etc/jaah/ and /var/lib/jaah-vm/ (pass --purge to wipe)"
fi

ok "Uninstall complete"
