#!/usr/bin/env bats
# Tests for read_secret — KV file parsing, never sources code

setup() {
    export JAAH_VM_VERSION="test"
    export TEST_DIR=$(mktemp -d)
    export JAAH_ETC="$TEST_DIR/etc"
    export JAAH_SECRETS="$JAAH_ETC/vm-secrets.env"
    export JAAH_HMAC_KEY="$JAAH_ETC/hmac.key"
    export JAAH_KEYS_DIR="$JAAH_ETC/keys"
    export JAAH_LOG="$TEST_DIR/log"
    export JAAH_STATE="$TEST_DIR/state"
    export JAAH_LOCK="$TEST_DIR/lock"
    export JAAH_MANIFEST_DIR="$TEST_DIR/manifests"
    export JAAH_RUN="$TEST_DIR/run"
    install -m 700 -d "$JAAH_ETC"
    . "$BATS_TEST_DIRNAME/../lib-common.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "read_secret parses simple KV" {
    cat > "$JAAH_SECRETS" <<EOF
VM_DEFAULT_PASSWORD=hello123
EOF
    chmod 600 "$JAAH_SECRETS"
    result=$(read_secret VM_DEFAULT_PASSWORD)
    [[ "$result" == "hello123" ]]
}

@test "read_secret strips single quotes" {
    cat > "$JAAH_SECRETS" <<'EOF'
VM_DEFAULT_PASSWORD='quoted-value!'
EOF
    chmod 600 "$JAAH_SECRETS"
    result=$(read_secret VM_DEFAULT_PASSWORD)
    [[ "$result" == "quoted-value!" ]]
}

@test "read_secret strips double quotes" {
    cat > "$JAAH_SECRETS" <<'EOF'
VM_DEFAULT_PASSWORD="dquoted-value"
EOF
    chmod 600 "$JAAH_SECRETS"
    result=$(read_secret VM_DEFAULT_PASSWORD)
    [[ "$result" == "dquoted-value" ]]
}

@test "read_secret returns empty for missing key" {
    cat > "$JAAH_SECRETS" <<EOF
OTHER_KEY=foo
EOF
    chmod 600 "$JAAH_SECRETS"
    result=$(read_secret VM_DEFAULT_PASSWORD)
    [[ -z "$result" ]]
}

@test "read_secret does NOT execute code in value" {
    # Critical safety test: source-mode would execute `rm -rf /`; parse-mode must not.
    cat > "$JAAH_SECRETS" <<'EOF'
VM_DEFAULT_PASSWORD=$(touch /tmp/INSECURE-jaah-test-pwn)
EOF
    chmod 600 "$JAAH_SECRETS"
    rm -f /tmp/INSECURE-jaah-test-pwn
    result=$(read_secret VM_DEFAULT_PASSWORD)
    [[ ! -e /tmp/INSECURE-jaah-test-pwn ]]
    [[ "$result" == '$(touch /tmp/INSECURE-jaah-test-pwn)' ]]
}
