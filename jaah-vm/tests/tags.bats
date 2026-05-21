#!/usr/bin/env bats
# Tests for sanitize_tag + CSV splitting (regression for v0.6.7 bug
# where `--tags myapp,canary` only kept "myapp").

setup() {
    export JAAH_VM_VERSION="test"
    export JAAH_LOG=/tmp/jaah-vm-test.log
    export JAAH_ETC=/tmp/jaah-vm-test-etc
    export JAAH_SECRETS=/tmp/jaah-vm-test-etc/vm-secrets.env
    export JAAH_KEYS_DIR=/tmp/jaah-vm-test-etc/keys
    export JAAH_STATE=/tmp/jaah-vm-test-state
    export JAAH_LOCK=/tmp/jaah-vm-test-lock.d
    export JAAH_MANIFEST_DIR=/tmp/jaah-vm-test-manifests
    export JAAH_RUN=/tmp/jaah-vm-test-run
    . "$BATS_TEST_DIRNAME/../lib-common.sh"
}

# Helper: replicate the v0.6.7 CSV-split logic in isolation.
_split_tags_csv() {
    local input="$1"
    local out=""
    local _IFS_SAVE="$IFS"
    IFS=','
    local t s
    for t in $input; do
        [ -n "$t" ] || continue
        s=$(sanitize_tag "$t")
        [ -n "$s" ] && out="${out:+${out},}${s}"
    done
    IFS="$_IFS_SAVE"
    printf '%s' "$out"
}

@test "tags CSV: two-tag list keeps both" {
    result=$(_split_tags_csv "myapp,canary")
    [ "$result" = "myapp,canary" ]
}

@test "tags CSV: three-tag list keeps all three" {
    result=$(_split_tags_csv "a,b,c")
    [ "$result" = "a,b,c" ]
}

@test "tags CSV: single tag with no comma" {
    result=$(_split_tags_csv "solo")
    [ "$result" = "solo" ]
}

@test "tags CSV: empty input → empty output" {
    result=$(_split_tags_csv "")
    [ -z "$result" ]
}

@test "tags CSV: uppercase tags lowercased" {
    result=$(_split_tags_csv "Prod,Canary")
    [ "$result" = "prod,canary" ]
}

@test "tags CSV: dots replaced with dashes" {
    result=$(_split_tags_csv "v1.0,v2.0")
    [ "$result" = "v1-0,v2-0" ]
}

@test "tags CSV: empty fields skipped" {
    result=$(_split_tags_csv "a,,b")
    [ "$result" = "a,b" ]
}
