#!/bin/bash
# bootstrap.sh — One-line installer for any pm-scripts tool.
#
# This is the ONLY file in pm-scripts allowed to be fetched via curl|bash,
# because:
#   1. It's small (under 80 lines) — easy to audit before running.
#   2. It does NOT execute remote code at runtime — it git-clones the repo
#      into a known location, then delegates to the tool's install.sh.
#   3. It supports pinning to a tag or commit so you can audit the exact
#      version going onto the node.
#
# USAGE:
#   # Always-latest main:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- <tool>
#
#   # Pin to a specific version (recommended for production):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- <tool> --ref jaah-vm/v0.2.0
#
# EXAMPLES:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm --ref jaah-vm/v0.2.0

set -Eeuo pipefail

readonly REPO_URL="https://github.com/jaahit/pm-scripts.git"
readonly DEST="/opt/pm-scripts"

# ── Helpers ─────────────────────────────────────────────────────────────────
log()  { printf "\033[1;36m[bootstrap]\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m[bootstrap]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[bootstrap]\033[0m %s\n" "$*" >&2; }
fail() { printf "\033[1;31m[bootstrap]\033[0m %s\n" "$*" >&2; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
[ "$(id -u)" -eq 0 ] || fail "Run as root (sudo bash -c \"\$(curl ...)\" -- ...)"

# Parse args after the literal -- separator (or all positional args)
TOOL=""
REF=""
while [ $# -gt 0 ]; do
    case "$1" in
        --ref)  REF="$2"; shift 2;;
        --help|-h)
            sed -n '2,/^set -/p' "$0" | sed 's/^# \{0,1\}//; /^set -/d'
            exit 0;;
        *)      TOOL="$1"; shift;;
    esac
done

[ -n "$TOOL" ] || fail "Tool name required. Example: bootstrap.sh jaah-vm"

# Allow only known-good tool-name characters
[[ "$TOOL" =~ ^[a-z0-9][a-z0-9-]{0,30}$ ]] || fail "Invalid tool name: $TOOL"

# ── Dependencies ────────────────────────────────────────────────────────────
command -v git >/dev/null || {
    log "Installing git"
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git 2>&1 | tail -2
}

# ── Clone or update ─────────────────────────────────────────────────────────
if [ -d "$DEST/.git" ]; then
    log "Updating existing clone at $DEST"
    git -C "$DEST" fetch --tags --quiet
    if [ -n "$REF" ]; then
        git -C "$DEST" checkout -q "$REF"
    else
        git -C "$DEST" checkout -q main
        git -C "$DEST" reset --hard --quiet "origin/main"
    fi
else
    log "Cloning $REPO_URL → $DEST"
    git clone --quiet "$REPO_URL" "$DEST"
    if [ -n "$REF" ]; then
        git -C "$DEST" checkout -q "$REF"
    fi
fi

ok "At $(git -C "$DEST" rev-parse --short HEAD)  ($(git -C "$DEST" describe --tags --always 2>/dev/null || echo 'main'))"

# ── Verify tool dir + delegate to its install.sh ────────────────────────────
TOOL_DIR="$DEST/$TOOL"
[ -d "$TOOL_DIR" ] || fail "Tool '$TOOL' not found in repo (no directory $TOOL_DIR)"
[ -x "$TOOL_DIR/install.sh" ] || fail "Tool '$TOOL' has no install.sh"

log "Delegating to $TOOL_DIR/install.sh"
echo ""
bash "$TOOL_DIR/install.sh"
