# jaah-vm

A mini local equivalent of the AWS EC2 Launch Instance Wizard for the **jaah Proxmox cluster**. Clones a hardened Ubuntu 26.04 LTS cloud-init template into a new VM in 10-30 seconds.

**Version:** 0.6.0
**Status:** Production-ready, NOT yet deployed
**Scope:** Cluster nodes only (pmx-01, pmx-02, pmx-06)

## Quick start

```bash
jaah-vm wizard                                 # ★ interactive 5-step wizard
jaah-vm                                        # cheat-sheet
jaah-vm create --name web-01                   # non-interactive: SSH-key-only
jaah-vm create --name db-01 --type large --start --wait-ssh
jaah-vm list                                   # all managed VMs
jaah-vm shell web-01                           # ssh in
jaah-vm destroy web-01                         # manifest-verified, typed confirm
```

## Installation

### Default (use existing /root/.ssh/id_rsa.pub)

```bash
sudo bash install.sh
```

### Generate a fresh, exportable keypair (recommended for cross-device access)

```bash
sudo bash install.sh --generate-fresh-key
```

This creates a NEW ed25519 keypair dedicated to VM access:
- Public key is saved to `/etc/jaah/keys/default.pub`
- **Private key is printed to stdout ONCE** for you to copy
- Private key is then shredded — there is no second chance to retrieve it
- Save it to your laptop/phone/etc. and use from anywhere

Most modern clients (PuTTY 0.75+, WinSCP, VS Code Remote-SSH, MobaXterm) accept the OpenSSH format directly. For older PuTTY needing `.ppk`, run `puttygen <key> -O private -o <key>.ppk`.

### What the installer does

1. Installs dependencies (`jq`, `bats`, `openssl`, `python3-yaml`)
2. Installs the dispatcher + lib at `/usr/local/bin/jaah-vm` and `/usr/local/lib/jaah-vm/`
3. Installs bash completion and logrotate config
4. Bootstraps `/etc/jaah/`:
   - `vm-secrets.env` (mode 600) — opt-in password used only with `--set-password`
   - `keys/default.pub` — your SSH public key (or freshly generated)
5. Runs `jaah-vm doctor`
6. Prints a final installation summary

Run `install.sh` independently on each cluster node — no shared state to sync.

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
| `No ownership manifest for VMID N — not managed by jaah-vm` | The VM has no `/etc/pve/jaah-vm/<vmid>.json` — it wasn't created by jaah-vm. Use `qm destroy <vmid>` manually. |
| `VM started but SSH not yet reachable` | First-boot cloud-init may take 60-120s. Retry `jaah-vm shell` after a minute, or run `qm guest exec <vmid> -- cloud-init status --wait` |
| `No IPv4 found for ... (agent + ARP fallback both failed)` | Check FortiGate DHCP leases by MAC. If you set static IP, verify `qm config <vmid>` |

## Files

**On every cluster node (installed by `install.sh`):**

- `/usr/local/bin/jaah-vm` — dispatcher
- `/usr/local/lib/jaah-vm/lib-common.sh` — shared functions
- `/etc/jaah/vm-secrets.env` — `VM_DEFAULT_PASSWORD` (root:600, never on argv)
- `/etc/jaah/keys/default.pub` — SSH public key
- `/etc/bash_completion.d/jaah-vm` — TAB completion
- `/etc/logrotate.d/jaah-vm` — weekly rotation, keep 8

**Cluster-wide via pmxcfs (`/etc/pve/`):**

- `/etc/pve/jaah-vm/<vmid>.json` — ownership manifest (pmxcfs-replicated)
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

tests covering: log sanitizer, secrets parser, manifest ownership, anchored regex (no `vm-10` matching `vm-100`), name validation.

## Extended documentation

See [docs/operator-manual.md](docs/operator-manual.md) for the full operator reference.
