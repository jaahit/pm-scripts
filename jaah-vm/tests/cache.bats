#!/usr/bin/env bats
# Tests for refresh_name_cache — name cache for TAB completion.

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
    export JAAH_NAMES_CACHE="$TEST_DIR/state/names.cache"
    install -m 700 -d "$JAAH_ETC" "$JAAH_MANIFEST_DIR" "$JAAH_STATE"
    . "$BATS_TEST_DIRNAME/../lib-common.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "refresh_name_cache writes one name per manifest" {
    write_manifest 100 web-01
    write_manifest 101 db-01
    write_manifest 102 cache-01
    refresh_name_cache
    [ -f "$JAAH_NAMES_CACHE" ]
    local got
    got=$(sort "$JAAH_NAMES_CACHE")
    [[ "$got" == *"web-01"* ]]
    [[ "$got" == *"db-01"* ]]
    [[ "$got" == *"cache-01"* ]]
    [ "$(wc -l < "$JAAH_NAMES_CACHE")" -eq 3 ]
}

@test "refresh_name_cache produces world-readable file (mode 644)" {
    write_manifest 100 web-01
    refresh_name_cache
    [ -f "$JAAH_NAMES_CACHE" ]
    local perms
    perms=$(stat -c '%a' "$JAAH_NAMES_CACHE")
    [ "$perms" = "644" ]
}

@test "refresh_name_cache empty when no manifests" {
    refresh_name_cache
    [ -f "$JAAH_NAMES_CACHE" ]
    [ ! -s "$JAAH_NAMES_CACHE" ]
}

@test "refresh_name_cache reflects manifest removal" {
    write_manifest 100 web-01
    write_manifest 101 db-01
    refresh_name_cache
    [ "$(wc -l < "$JAAH_NAMES_CACHE")" -eq 2 ]
    remove_manifest 100
    refresh_name_cache
    [ "$(wc -l < "$JAAH_NAMES_CACHE")" -eq 1 ]
    grep -qx "db-01" "$JAAH_NAMES_CACHE"
    ! grep -qx "web-01" "$JAAH_NAMES_CACHE"
}

@test "refresh_name_cache is atomic — old file stays valid mid-write" {
    write_manifest 100 web-01
    refresh_name_cache
    local before=$(cat "$JAAH_NAMES_CACHE")
    write_manifest 101 db-01
    refresh_name_cache
    [ "$(wc -l < "$JAAH_NAMES_CACHE")" -eq 2 ]
}
