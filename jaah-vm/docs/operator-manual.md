# `jaah-vm` — Operator Manual

**Version:** 0.3.0
**Audience:** "I haven't used this in 6 months and need a VM"
**Cluster scope:** `jaah-cluster` (pmx-01, pmx-02, pmx-06) — standalone nodes are not supported

This tool is a **mini EC2 Launch Instance Wizard** for our local Proxmox cluster. It clones a golden Ubuntu 26.04 LTS cloud-init template into a new VM in 10-30 seconds, with sensible defaults you can override.

---

## Cheat sheet

```bash
jaah-vm                                       # quick help
jaah-vm doctor                                # is everything healthy?

# Launch
jaah-vm create --name web-01                                    # SSH-key-only, type=small, no boot
jaah-vm create --name db-01  --type large --start --wait-ssh    # boot + wait until SSH works
jaah-vm create --name api-01 --env prod --start                 # tagged 'prod'

# Inspect
jaah-vm list                  # all managed VMs
jaah-vm status web-01         # IP, state, config
jaah-vm shell  web-01         # ssh in (multi-stage IP discovery)

# Lifecycle
jaah-vm rerun   web-01        # rebuild exactly from recorded recipe
jaah-vm destroy web-01        # manifest-verified, typed confirm
```

---

## Bootstrap (one-time per cluster node)

The first time we install this on a fresh cluster node, lay down the support files:

```bash
# 1. Layout /etc/jaah/
install -d -o root -g root -m 700 /etc/jaah
install -d -o root -g root -m 755 /etc/jaah/keys

# 2. SSH public key (the operator's key)
install -o root -g root -m 644 ~/.ssh/id_ed25519.pub /etc/jaah/keys/default.pub

# 3. Secrets file (ONLY VM_DEFAULT_PASSWORD matters for now)
install -o root -g root -m 600 /opt/pm-scripts/jaah-vm/vm-secrets.env.example /etc/jaah/vm-secrets.env
${EDITOR:-vim} /etc/jaah/vm-secrets.env      # set VM_DEFAULT_PASSWORD

# 4. Install the script + lib
install -o root -g root -m 755 jaah-vm /usr/local/bin/jaah-vm
install -d /usr/local/lib/jaah-vm
install -o root -g root -m 644 lib-common.sh /usr/local/lib/jaah-vm/

# 5. Completion + log rotation
install -o root -g root -m 644 completion.bash /etc/bash_completion.d/jaah-vm
install -o root -g root -m 644 logrotate.conf  /etc/logrotate.d/jaah-vm

# 6. Verify
jaah-vm doctor
```

Run `jaah-vm doctor` — all checks must be green before first `create`.

---

## How the security model works (in one paragraph)

Every VM created by `jaah-vm` writes an **ownership manifest** at `/etc/pve/jaah-vm/<vmid>.json` (pmxcfs-replicated across cluster). `destroy` refuses unless that file exists with valid JSON shape — this is the only ownership marker, the `managed-by-jaah-vm` tag is decorative. The threat model is single-operator (anyone with root could `qm destroy` directly anyway), so the manifest's job is to prevent accidents: a tag-only check would happily destroy VMs that just happen to share the tag. Manifest existence + typed-name confirmation is enough.

Passwords (when `--set-password` is used) are written into a cloud-init `user-data` file (mode 600) and attached via `qm set --cicustom`. They **never** appear on the `qm` command line and therefore never in `/proc/<pid>/cmdline` or `/var/log/pve/tasks/`.

Default flow is **SSH-key-only**, password locked. Use `--set-password` only when you need emergency console access.

---

## Subcommands

### `create`

The launch flow. See `jaah-vm create --help` for the visible flags; `--advanced` reveals the rest.

**Visible flags:**
| Flag | Default | Purpose |
|---|---|---|
| `--name <h>` | required | VM hostname (regex: `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`) |
| `--type <p>` | `small` | Instance preset (see `jaah-vm types`) |
| `--env <e>` | `<none>` | Tag-only: `dev`, `staging`, `prod` |
| `--snippet <path>` | base | Custom cloud-init user-data (validated) |
| `--snippet-allow-exec` | `false` | Permit `runcmd`/`bootcmd`/`write_files` in snippet |
| `--set-password` | `false` | Enable password auth (default: key-only) |
| `--start` | `false` | Boot after creation |
| `--wait-ssh` | `false` | Block until SSH succeeds (implies `--start`) |
| `--dry-run` | — | Print plan, no execution, no locks acquired |
| `--json` | — | Machine-readable output |
| `--replace` | — | Destroy existing same-name VM first (manifest-verified) |

**Advanced flags** (cores/memory/disk overrides, network, CPU type, VLAN, etc.) — see `jaah-vm create --advanced --help`.

**What happens, step by step:**
1. Validation (`--name`, `--env`, `--vlan`, etc.)
2. Pre-flight: cluster quorum, secrets perms, SSH key, storage free, ZFS health
3. Template auto-build if missing (one-time, ~30s)
4. Cluster-wide lock (`mkdir /etc/pve/jaah-vm.lock.d`) — releases on every exit path
5. VMID allocation (anchored-regex probing — won't collide vm-10 with vm-100)
6. `qm clone` from VMID 9000 (`ubuntu-26.04-tmpl`)
7. Apply resources, network, cloud-init (file-based; password never on argv)
8. Write manifest at `/etc/pve/jaah-vm/<vmid>.json`
9. Record recipe at `/var/lib/jaah-vm/recipes/<vmid>.cmd` (used by `rerun`)
10. Optional `--start` + `--wait-ssh` (multi-stage: agent → ARP → SSH probe)

**On error at any step:** ERR trap fires, rollback destroys the half-built VMID + ZFS dataset + manifest. Orphans (rollback partial-failure) get logged to `/var/lib/jaah-vm/orphans` and surfaced by `jaah-vm doctor`.

### `rerun`

Replay the exact recipe that built a VM. Useful when an upgrade went wrong or you want a fresh instance of the same configuration.

```bash
jaah-vm rerun web-01
# Recorded recipe for web-01:
#   jaah-vm create --name web-01 --type small --env prod
# Re-run this command? Type 'yes' to confirm:
```

Recipe lives at `/var/lib/jaah-vm/recipes/<vmid>.cmd` and is also embedded in VM Notes.

### `list`

Shows VMs whose manifest matches. `--json` for piping.

```
VMID    NAME                      STATUS      CREATED
102     web-01                    running     2026-05-18T16:42:00Z
103     db-01                     stopped     2026-05-18T16:55:01Z
```

### `status <name|vmid>`

Config snapshot + current IP (via qemu-guest-agent).

### `shell <name|vmid>`

Multi-stage IP discovery, then `ssh -o StrictHostKeyChecking=accept-new`:
1. qemu-guest-agent (5-30s)
2. ARP table on bridge (MAC match) — fallback
3. (Else) hint: check FortiGate DHCP leases

Specify `--user <name>` to override `ibra`.

### `destroy <name|vmid> [--force]`

Verifies manifest ownership; without `--force` asks for typed VM-name confirmation. Cleans up VM, ZFS datasets (anchored-regex, no collisions), recipe file, snippet file, manifest.

### `doctor [--rebuild-template]`

Health checks:
- Cluster reachable + quorate
- Secrets file mode + owner (root:600)
- SSH key present
- Storages active (iso-library, vm-fast)
- Cloud image present
- Template VMID 9000 valid (multi-attribute check)
- Orphan VMIDs/disks pending cleanup
- Managed VMs with `cpu=host` (migration-incompatible warning)
- PVE task logs free of legacy `--cipassword` references

With `--rebuild-template`: forces rebuild of the golden template.

### `types`

Lists the 6 instance-type presets.

### `--version`

Prints `jaah-vm v0.3.0 (git <sha>)`.

---

## Live migration: per-node ZFS caveat

The default CPU type is `x86-64-v2-AES`, which is **migration-compatible across all Xeon generations** in our cluster (Skylake-SP, Broadwell, Ivy Bridge, Kaby Lake).

**But** our `vm-fast` storage is **per-node ZFS**, not shared. Online migration therefore requires one of:

```bash
# Slow path: copy the disk during migration (1-5 min per VM)
qm migrate <vmid> pmx-02 --online --with-local-disks --targetstorage vm-fast

# Fast path: pre-configure ZFS replication separately (out of jaah-vm scope)
pvesr create-local-job <vmid>-0 pmx-02 --schedule '*/5'
qm migrate <vmid> pmx-02 --online
```

`jaah-vm doctor` warns if a managed VM uses local storage without replication configured.

---

## Custom cloud-init snippets

```bash
# Write your snippet
cat > /tmp/nginx-user.yaml <<'EOF'
#cloud-config
users:
  - name: ibra
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
      - <YOUR-KEY>
package_update: true
packages:
  - nginx
runcmd:
  - systemctl enable --now nginx
EOF

# Validate + apply
jaah-vm create --name web-01 --snippet /tmp/nginx-user.yaml --snippet-allow-exec --start --wait-ssh
```

**Validation:** YAML safe-parse, by default rejects `runcmd`/`bootcmd`/`write_files` (RCE risk) — opt-in with `--snippet-allow-exec`. Snippet is copied to `/mnt/pve/iso-library/snippets/jaah-vm/<vmid>-<sha256>-...yaml` (mode 600).

**Replaces, not extends:** the snippet replaces the base user-data. Always include `ssh_authorized_keys` or you'll lock yourself out.

---

## Troubleshooting

### "Cluster not quorate"
Run `pvecm status` on pmx-01. Need 2/3 votes minimum.

### "Cluster lock contention — 60s timeout"
Another `jaah-vm create` is running somewhere. Wait. Stale lock auto-breaks after 90s.

### "Storage 'vm-fast' has N MB free, need M MB"
Pick `--storage vm-main` or another available pool. Run `pvesm status` to see options.

### "No ownership manifest for VMID N — not managed by jaah-vm"
The VM has no `/etc/pve/jaah-vm/<vmid>.json` — it wasn't created by jaah-vm. Use `qm destroy <vmid>` directly if you intend to remove it.

### "VM started but SSH not yet reachable"
Cloud-init may still be running on first boot. Try:
```bash
qm guest exec <vmid> -- cloud-init status --wait
jaah-vm shell <vmid>      # retry after a minute
```

### "No IPv4 found for ... (agent + ARP fallback both failed)"
Check FortiGate DHCP leases for the VM's MAC. If you set a static IP, verify `qm config <vmid> | grep ipconfig0`.

---

## Files reference

**On every cluster node:**
- `/usr/local/bin/jaah-vm` — the dispatcher
- `/usr/local/lib/jaah-vm/lib-common.sh` — shared functions
- `/etc/jaah/vm-secrets.env` — `VM_DEFAULT_PASSWORD` (root:600)
- `/etc/jaah/keys/default.pub` — operator's SSH public key
- `/etc/bash_completion.d/jaah-vm` — TAB completion
- `/etc/logrotate.d/jaah-vm` — weekly rotation, keep 8

**Cluster-wide via pmxcfs (`/etc/pve/`):**
- `/etc/pve/jaah-vm/<vmid>.json` — ownership manifest (pmxcfs-replicated)
- `/etc/pve/jaah-vm.lock.d/` — cluster-wide mkdir-based lock

**Per-node state:**
- `/var/log/jaah-vm.log` — structured, sanitized
- `/var/lib/jaah-vm/recipes/<vmid>.cmd` — recipe for `rerun`
- `/var/lib/jaah-vm/orphans` — failed-rollback survivors (surfaced by `doctor`)

**Shared NFS (iso-library on pbs-01):**
- `/mnt/pve/iso-library/template/iso/ubuntu-26.04-server-cloudimg-amd64.img` — cloud image
- `/mnt/pve/iso-library/snippets/jaah-vm/*.yaml` — custom cloud-init snippets

---

## What jaah-vm does NOT do (and why)

| Skipped | Reason |
|---|---|
| Multi-OS | User scope: Ubuntu 26.04 LTS only |
| YAML batch | User scope: CLI flags only — use a `for` loop |
| Linked clones | Full clones complete in 10-30s; linked clones tie VM lifecycle to template forever |
| Multi-disk | YAGNI — add `--data-disk` when a real workload needs it |
| FortiGate API integration | Separate concern; out of scope |
| Standalone-node support | User scope: cluster nodes only |
| HA / Load Balance | User-disabled cluster-wide |
| Password as default | Security: SSH-key-only by default, password is `--set-password` opt-in |
