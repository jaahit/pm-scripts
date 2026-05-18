# jaah-vm

A mini local equivalent of the AWS EC2 Launch Instance Wizard for the **jaah Proxmox cluster**. Clones a hardened Ubuntu 26.04 LTS cloud-init template into a new VM in 10-30 seconds.

**Version:** 0.2.0
**Status:** Production-ready, NOT yet deployed
**Scope:** Cluster nodes only (pmx-01, pmx-02, pmx-06)

## Quick start

```bash
jaah-vm                                        # cheat-sheet
jaah-vm create --name web-01                   # smallest defaults, SSH-key-only
jaah-vm create --name db-01 --type large --start --wait-ssh
jaah-vm list                                   # all managed VMs
jaah-vm shell web-01                           # ssh in
jaah-vm destroy web-01                         # tag+HMAC verified, typed confirm
```

## Installation

```bash
sudo bash install.sh
```

The installer:

1. Installs dependencies (`jq`, `bats`, `openssl` — `python3` for snippet validation)
2. Installs the dispatcher + lib at `/usr/local/bin/jaah-vm` and `/usr/local/lib/jaah-vm/`
3. Installs bash completion and logrotate config
4. Bootstraps `/etc/jaah/`:
   - `vm-secrets.env` (mode 600) — opt-in password used only with `--set-password`
   - `keys/default.pub` — your SSH public key
   - `hmac.key` — 32 random bytes, **must be identical on every cluster node**
5. Runs `jaah-vm doctor`

After install on the first cluster node, copy `/etc/jaah/hmac.key` to every other cluster node:
```bash
scp /etc/jaah/hmac.key root@pmx-02:/etc/jaah/
scp /etc/jaah/hmac.key root@pmx-06:/etc/jaah/
```

Then re-run `install.sh` on those nodes (it detects an existing HMAC key and keeps it).

## Examples

```bash
# 1) Smallest VM (1 vCPU, 1 GB, 10 GB)
jaah-vm create --name test-01 --type tiny --start --wait-ssh

# 2) Larger, with environment tag
jaah-vm create --name api-01 --type large --env prod --start --wait-ssh

# 3) Custom cloud-init (e.g. nginx pre-installed)
jaah-vm create --name web-01 \
    --snippet ~/nginx-user.yaml \
    --snippet-allow-exec \
    --start --wait-ssh

# 4) Static IP example
jaah-vm create --name fixed-01 --ip 192.168.1.150/24 --gw 192.168.1.99 --start

# 5) Replay the exact recipe of an existing VM
jaah-vm rerun web-01

# 6) Preview without acting
jaah-vm create --name plan-01 --dry-run
```

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| `Cluster not quorate` | `pvecm status` — need 2/3 votes minimum |
| `Cluster lock contention — 60s timeout` | Another `jaah-vm` running. Stale locks auto-break after 90s. |
| `Storage 'vm-fast' has N MB free, need M MB` | Use `--storage vm-main` or another active pool |
| `Ownership HMAC mismatch — refusing destroy` | The VM was tampered with, or the HMAC key differs from when it was created. Use `qm destroy <vmid>` manually after verifying it's the right VM. |
| `VM started but SSH not yet reachable` | First-boot cloud-init may take 60-120s. Retry `jaah-vm shell` after a minute, or run `qm guest exec <vmid> -- cloud-init status --wait` |
| `No IPv4 found for ... (agent + ARP fallback both failed)` | Check FortiGate DHCP leases by MAC. If you set static IP, verify `qm config <vmid>` |

## Files

**On every cluster node (installed by `install.sh`):**

- `/usr/local/bin/jaah-vm` — dispatcher
- `/usr/local/lib/jaah-vm/lib-common.sh` — shared functions
- `/etc/jaah/vm-secrets.env` — `VM_DEFAULT_PASSWORD` (root:600, never on argv)
- `/etc/jaah/hmac.key` — 32 random bytes, identical across nodes (root:600)
- `/etc/jaah/keys/default.pub` — SSH public key
- `/etc/bash_completion.d/jaah-vm` — TAB completion
- `/etc/logrotate.d/jaah-vm` — weekly rotation, keep 8

**Cluster-wide via pmxcfs (`/etc/pve/`):**

- `/etc/pve/jaah-vm/<vmid>.json` — HMAC-signed ownership manifest
- `/etc/pve/jaah-vm.lock.d/` — atomic-mkdir cluster lock

**Per-node state:**

- `/var/log/jaah-vm.log` — sanitized log (rotated weekly)
- `/var/lib/jaah-vm/recipes/<vmid>.cmd` — replay recipe (used by `rerun`)
- `/var/lib/jaah-vm/orphans` — failed-rollback survivors, surfaced by `doctor`

**Shared NFS (iso-library on pbs-01):**

- `/mnt/pve/iso-library/template/iso/ubuntu-26.04-server-cloudimg-amd64.img`
- `/mnt/pve/iso-library/snippets/jaah-vm/*.yaml` — validated custom snippets

## Tests

```bash
cd tests/ && bats .
```

22 tests covering: log sanitizer, secrets parser, HMAC ownership, anchored regex (no `vm-10` matching `vm-100`), name validation.

## Extended documentation

See [docs/operator-manual.md](docs/operator-manual.md) for the full operator reference.
