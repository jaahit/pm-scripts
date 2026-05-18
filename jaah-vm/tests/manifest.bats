#!/usr/bin/env bats
# Tests for the ownership manifest (manifest-file-only, no HMAC).

setup() {
    export JAAH_VM_VERSION="test"
    export TEST_DIR=$(mktemp -d)
    export JAAH_ETC="$TEST_DIR/etc"
    export JAAH_SECRETS="$JAAH_ETC/vm-secrets.env"
    export JAAH_KEYS_DIR="$JAAH_ETC/keys"
    export JAAH_LOG="$TEST_DIR/log"
    export JAAH_STATE="$TEST_DIR/state"
    export JAAH_LOCK="$TEST_DIR/lock"
    export JAAH_MANIFEST_DIR="$TEST_DIR/manifests"
    export JAAH_RUN="$TEST_DIR/run"
    install -m 700 -d "$JAAH_ETC" "$JAAH_MANIFEST_DIR"
    . "$BATS_TEST_DIRNAME/../lib-common.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "write_manifest creates valid JSON file" {
    write_manifest 100 web-01
    [ -f "$JAAH_MANIFEST_DIR/100.json" ]
    jq -e '.vmid == 100' "$JAAH_MANIFEST_DIR/100.json"
    jq -e '.name == "web-01"' "$JAAH_MANIFEST_DIR/100.json"
    jq -e '.created' "$JAAH_MANIFEST_DIR/100.json"
    jq -e '.version == "test"' "$JAAH_MANIFEST_DIR/100.json"
}

@test "is_managed returns 0 for valid manifest" {
    write_manifest 100 web-01
    run is_managed 100
    [ "$status" -eq 0 ]
}

@test "is_managed returns non-zero for missing manifest" {
    run is_managed 999
    [ "$status" -ne 0 ]
}

@test "is_managed returns non-zero for malformed manifest JSON" {
    echo "not json" > "$JAAH_MANIFEST_DIR/200.json"
    run is_managed 200
    [ "$status" -ne 0 ]
}

@test "is_managed returns non-zero for manifest missing required fields" {
    echo '{}' > "$JAAH_MANIFEST_DIR/201.json"
    run is_managed 201
    [ "$status" -ne 0 ]
}

@test "verify_ownership succeeds for valid manifest" {
    write_manifest 300 my-vm
    run verify_ownership 300
    [ "$status" -eq 0 ]
}

@test "verify_ownership fails for missing manifest" {
    run verify_ownership 998
    [ "$status" -ne 0 ]
}

@test "verify_ownership fails for malformed manifest" {
    echo "garbage" > "$JAAH_MANIFEST_DIR/202.json"
    run verify_ownership 202
    [ "$status" -ne 0 ]
}

@test "remove_manifest removes the file" {
    write_manifest 400 ephemeral
    [ -f "$JAAH_MANIFEST_DIR/400.json" ]
    remove_manifest 400
    [ ! -f "$JAAH_MANIFEST_DIR/400.json" ]
}
