#!/usr/bin/env bats
# Tests for HMAC ownership

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
    install -m 700 -d "$JAAH_ETC" "$JAAH_MANIFEST_DIR"
    # generate test HMAC key
    openssl rand 32 > "$JAAH_HMAC_KEY"
    chmod 600 "$JAAH_HMAC_KEY"
    . "$BATS_TEST_DIRNAME/../lib-common.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "compute_hmac is deterministic" {
    h1=$(compute_hmac 100 web-01 2026-05-18T16:00:00Z)
    h2=$(compute_hmac 100 web-01 2026-05-18T16:00:00Z)
    [[ "$h1" == "$h2" ]]
    [[ -n "$h1" ]]
    [[ "${#h1}" -eq 64 ]]   # sha256 hex = 64 chars
}

@test "compute_hmac differs by VMID" {
    h1=$(compute_hmac 100 web-01 2026-05-18T16:00:00Z)
    h2=$(compute_hmac 101 web-01 2026-05-18T16:00:00Z)
    [[ "$h1" != "$h2" ]]
}

@test "compute_hmac differs by name" {
    h1=$(compute_hmac 100 web-01 2026-05-18T16:00:00Z)
    h2=$(compute_hmac 100 web-02 2026-05-18T16:00:00Z)
    [[ "$h1" != "$h2" ]]
}

@test "write_manifest + is_managed round-trip" {
    write_manifest 100 web-01
    run is_managed 100
    [ "$status" -eq 0 ]
}

@test "is_managed rejects forged manifest (HMAC mismatch)" {
    # Forge a manifest with wrong HMAC
    cat > "$JAAH_MANIFEST_DIR/200.json" <<EOF
{"vmid":200,"name":"forged","created":"2026-05-18T16:00:00Z","hmac":"0000000000000000000000000000000000000000000000000000000000000000","version":"test"}
EOF
    run is_managed 200
    [ "$status" -ne 0 ]
}

@test "verify_ownership exits on tampered manifest" {
    write_manifest 300 real-vm
    # Tamper name AFTER manifest written → HMAC stops matching
    sed -i 's/real-vm/tampered/' "$JAAH_MANIFEST_DIR/300.json"
    run verify_ownership 300
    [ "$status" -ne 0 ]
}

@test "is_managed false for missing manifest" {
    run is_managed 999
    [ "$status" -ne 0 ]
}
