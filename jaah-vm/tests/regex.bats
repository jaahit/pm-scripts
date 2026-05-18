#!/usr/bin/env bats
# Critical-data-loss test: anchored ZFS regex must NOT match vm-100 against VMID=10.

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

@test "ZFS regex does not match prefix collisions" {
    # Simulate zfs list output containing both vm-10-disk and vm-100-disk
    local input="rpool/data/vm-10-disk-0
rpool/data/vm-100-disk-0
rpool/data/vm-101-disk-0
rpool/data/vm-1-disk-0
rpool/data/vm-10-disk-1"
    # The regex used in rollback / allocator
    local vmid=10
    local matched
    matched=$(echo "$input" | grep -E "/vm-${vmid}-disk-[0-9]+\$")
    # Expect only vm-10-disk-0 and vm-10-disk-1
    [[ $(echo "$matched" | wc -l) -eq 2 ]]
    [[ "$matched" == *"vm-10-disk-0"* ]]
    [[ "$matched" == *"vm-10-disk-1"* ]]
    [[ "$matched" != *"vm-100-disk-0"* ]]
    [[ "$matched" != *"vm-101-disk-0"* ]]
    [[ "$matched" != *"vm-1-disk-0"* ]]
}

@test "ZFS regex matches multi-digit VMIDs" {
    local input="rpool/data/vm-100-disk-0
rpool/data/vm-1000-disk-0
rpool/data/vm-100-disk-3"
    local vmid=100
    local matched
    matched=$(echo "$input" | grep -E "/vm-${vmid}-disk-[0-9]+\$")
    [[ $(echo "$matched" | wc -l) -eq 2 ]]
    [[ "$matched" == *"vm-100-disk-0"* ]]
    [[ "$matched" == *"vm-100-disk-3"* ]]
    [[ "$matched" != *"vm-1000-disk-0"* ]]
}

@test "validate_name accepts valid names" {
    run validate_name "web-01"
    [ "$status" -eq 0 ]
    run validate_name "db1"
    [ "$status" -eq 0 ]
    run validate_name "a"
    [ "$status" -eq 0 ]
}

@test "validate_name rejects invalid names" {
    run validate_name "Web-01"
    [ "$status" -ne 0 ]
    run validate_name "-web"
    [ "$status" -ne 0 ]
    run validate_name "web-"
    [ "$status" -ne 0 ]
    run validate_name "web 01"
    [ "$status" -ne 0 ]
    run validate_name ""
    [ "$status" -ne 0 ]
    run validate_name "../web"
    [ "$status" -ne 0 ]
}

@test "sanitize_tag normalizes uppercase and dots" {
    result=$(sanitize_tag "Web-01.PROD")
    [[ "$result" == "web-01-prod" ]]
}

@test "sanitize_tag strips disallowed chars" {
    result=$(sanitize_tag "foo bar/baz!")
    [[ "$result" == "foobarbaz" ]]
}
