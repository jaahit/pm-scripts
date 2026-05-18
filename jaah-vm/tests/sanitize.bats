#!/usr/bin/env bats
# Tests for sanitize_line — log sanitization

setup() {
    export JAAH_VM_VERSION="test"
    # Source lib in isolation; avoid touching real /etc paths
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

@test "sanitize_line redacts --cipassword" {
    result=$(echo "qm set 100 --cipassword SuperSecret123 --name foo" | sanitize_line)
    [[ "$result" == "qm set 100 --cipassword *** --name foo" ]]
}

@test "sanitize_line redacts --token" {
    result=$(echo "curl --token abc123 --url https://x" | sanitize_line)
    [[ "$result" == *"--token ***"* ]]
}

@test "sanitize_line leaves non-secret args alone" {
    result=$(echo "qm clone 9000 102 --name web-01 --full true" | sanitize_line)
    [[ "$result" == "qm clone 9000 102 --name web-01 --full true" ]]
}

@test "sanitize_line preserves --name" {
    # Defense: --name is NOT in redact set; should pass through
    result=$(echo "qm set 100 --name web-01" | sanitize_line)
    [[ "$result" == "qm set 100 --name web-01" ]]
}
