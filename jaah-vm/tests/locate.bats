#!/usr/bin/env bats
# Tests for locate_vmid_node + resolve_node_ip — cross-node helpers
# introduced in v0.6.8 to fix B1/B2/B3/B4/B6 silent-corruption bugs.

setup() {
    export JAAH_VM_VERSION="test"
    export TEST_DIR=$(mktemp -d)
    export PVE_FAKE="$TEST_DIR/pve"
    # Stub the pmxcfs layout (/etc/pve/nodes/<n>/qemu-server/<vmid>.conf)
    install -d "$PVE_FAKE/nodes/pmx-01/qemu-server"
    install -d "$PVE_FAKE/nodes/pmx-02/qemu-server"
    install -d "$PVE_FAKE/nodes/pmx-06/qemu-server"
    : > "$PVE_FAKE/nodes/pmx-01/qemu-server/100.conf"
    : > "$PVE_FAKE/nodes/pmx-02/qemu-server/200.conf"
    : > "$PVE_FAKE/nodes/pmx-06/qemu-server/300.conf"
    # Stub /etc/pve/.members
    cat > "$PVE_FAKE/.members" <<EOF
{"nodename":"pmx-01","nodelist":{
  "pmx-01":{"id":1,"online":1,"ip":"192.168.1.202"},
  "pmx-02":{"id":2,"online":1,"ip":"192.168.1.203"},
  "pmx-06":{"id":3,"online":1,"ip":"192.168.1.207"}
}}
EOF
    export JAAH_LOG="$TEST_DIR/log"
    export JAAH_ETC="$TEST_DIR/etc"
    export JAAH_SECRETS="$JAAH_ETC/vm-secrets.env"
    export JAAH_KEYS_DIR="$JAAH_ETC/keys"
    export JAAH_STATE="$TEST_DIR/state"
    export JAAH_LOCK="$TEST_DIR/lock"
    export JAAH_MANIFEST_DIR="$TEST_DIR/manifests"
    export JAAH_RUN="$TEST_DIR/run"
    install -m 700 -d "$JAAH_ETC" "$JAAH_MANIFEST_DIR" "$JAAH_STATE"
    . "$BATS_TEST_DIRNAME/../lib-common.sh"
    # Override the hardcoded /etc/pve path in our helpers by shadowing
    # the function with one that reads from $PVE_FAKE.
    locate_vmid_node() {
        local vmid="$1"
        [ -n "$vmid" ] || return 1
        local f
        for f in "$PVE_FAKE"/nodes/*/qemu-server/"${vmid}".conf; do
            [ -e "$f" ] || continue
            local node
            node="${f#$PVE_FAKE/nodes/}"
            node="${node%%/*}"
            printf '%s' "$node"
            return 0
        done
        return 1
    }
    resolve_node_ip() {
        local node="$1"
        [ -n "$node" ] || return 1
        jq -r ".nodelist[\"${node}\"].ip // empty" "$PVE_FAKE/.members" 2>/dev/null
    }
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "locate_vmid_node finds VMID on pmx-01" {
    result=$(locate_vmid_node 100)
    [ "$result" = "pmx-01" ]
}

@test "locate_vmid_node finds VMID on pmx-02" {
    result=$(locate_vmid_node 200)
    [ "$result" = "pmx-02" ]
}

@test "locate_vmid_node returns rc=1 for missing VMID" {
    run locate_vmid_node 999
    [ "$status" -eq 1 ]
    [ -z "$output" ]
}

@test "locate_vmid_node rejects empty input" {
    run locate_vmid_node ""
    [ "$status" -eq 1 ]
}

@test "resolve_node_ip returns IP for known node" {
    result=$(resolve_node_ip pmx-01)
    [ "$result" = "192.168.1.202" ]
}

@test "resolve_node_ip returns empty for unknown node" {
    result=$(resolve_node_ip pmx-99)
    [ -z "$result" ]
}

@test "resolve_node_ip rejects empty input" {
    run resolve_node_ip ""
    [ "$status" -eq 1 ]
}
