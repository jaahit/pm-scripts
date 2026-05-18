# pm-scripts

Proxmox automation scripts for the **jaah-cluster** infrastructure.

One tool per folder. Each is self-contained: source, installer, tests, docs.

## Available tools

| Tool | Purpose | Latest |
|---|---|---|
| [`jaah-vm/`](jaah-vm/) | Proxmox VM launcher for the cluster (Ubuntu 26.04 LTS cloud-init) | [`jaah-vm/v0.5.0`](https://github.com/jaahit/pm-scripts/tree/jaah-vm/v0.5.0/jaah-vm) |

---

## How to use — `jaah-vm`

### 1. Install (one-time per node, or whenever you want to update)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm
```

### 2. Launch a VM

```bash
jaah-vm wizard                       # interactive 5-step TUI (easiest)
jaah-vm create --name web-01         # non-interactive, all defaults (small)
```

### 3. Manage VMs

```bash
jaah-vm list                         # show all managed VMs
jaah-vm status   web-01              # IP, cloud-init, agent state
jaah-vm shell    web-01              # SSH into the VM
```

### 4. Lifecycle

```bash
jaah-vm start    web-01              # boot a stopped VM
jaah-vm stop     web-01              # graceful shutdown (--force = hard stop)
jaah-vm restart  web-01              # graceful reboot
jaah-vm snapshot web-01              # auto-name snap-YYYYMMDD-HHMMSS
jaah-vm rebuild  web-01              # replay recipe (works after destroy too)
jaah-vm destroy  web-01              # permanent remove (typed confirm)
jaah-vm doctor                       # health check (cluster, storage, template)
```

---

## Examples

### Smallest possible — smoke test

```bash
jaah-vm create --name test-01 --type tiny --start --wait-ssh
```

Creates a 1 vCPU / 1 GB / 10 GB Ubuntu 26.04 VM, boots it, waits until SSH is reachable, then prints connection info.

### Larger app server with environment tag

```bash
jaah-vm create --name api-01 --type large --env prod --start --wait-ssh
```

→ 4 vCPU, 8 GB RAM, 80 GB disk, tagged `prod` in PVE UI.

### Static IP

```bash
jaah-vm create --name dns-01 --ip 192.168.1.150/24 --gw 192.168.1.99 --start
```

### Custom cloud-init snippet (preinstall nginx, etc.)

```bash
cat > /tmp/web.yaml <<'EOF'
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

jaah-vm create --name web-01 \
    --type medium \
    --snippet /tmp/web.yaml \
    --snippet-allow-exec \
    --start --wait-ssh
```

### Rebuild a VM from its recorded recipe

```bash
jaah-vm rebuild web-01               # re-executes the original create command
```

Works whether the VM still exists (the recipe must include `--replace`) or is already destroyed — recipes are archived to `/var/lib/jaah-vm/history/` before destroy.

### Take a snapshot before risky changes

```bash
jaah-vm snapshot web-01 --name pre-upgrade --description "before kernel upgrade"
# manage from qm:
#   qm listsnapshot 102
#   qm rollback   102 pre-upgrade
#   qm delsnapshot 102 pre-upgrade
```

### Preview without acting

```bash
jaah-vm create --name plan-01 --dry-run
```

### Update jaah-vm

Re-run the install one-liner — it pulls latest from main and reinstalls.

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm
```

### Pin to a specific version (for production rollout)

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm --ref jaah-vm/v0.4.8
```

### Generate a fresh SSH keypair for the VMs

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm --generate-fresh-key
```

The private key prints to your terminal **once** — copy it to your laptop / phone. The public key is saved to `/etc/jaah/keys/default.pub` and injected into every new VM.

---

## Instance type presets

| Preset | Cores | RAM | Disk | Typical use |
|---|---|---|---|---|
| `tiny` | 1 | 1 GB | 10 GB | smoke tests, bots |
| `small` ⭐ | 2 | 2 GB | 20 GB | default — web/agent |
| `medium` | 2 | 4 GB | 40 GB | light apps |
| `large` | 4 | 8 GB | 80 GB | app servers |
| `xl` | 8 | 16 GB | 160 GB | heavy compute |
| `2xl` | 16 | 32 GB | 320 GB | very heavy compute |

Override individual fields with `--cores`, `--memory`, `--disk`.

---

## Subcommand reference (jaah-vm)

| Command | What it does |
|---|---|
| `jaah-vm wizard` | Interactive 5-step VM creation |
| `jaah-vm create --name <n>` | Non-interactive create (see `--help`) |
| `jaah-vm list` | List all managed VMs |
| `jaah-vm status <name>` | Show details for one VM |
| `jaah-vm shell <name>` | SSH into a VM |
| `jaah-vm start <name>` | Start a stopped VM |
| `jaah-vm stop <name> [--force]` | Graceful shutdown (or hard stop) |
| `jaah-vm restart <name>` | Graceful reboot (alias: `reboot`) |
| `jaah-vm snapshot <name> [--name X] [--description "..."]` | Create snapshot |
| `jaah-vm rebuild <name>` | Replay the exact recipe that built a VM |
| `jaah-vm destroy <name>` | Permanently remove (alias: `terminate`) |
| `jaah-vm types` | Show instance-type presets |
| `jaah-vm doctor` | Cluster + tool health check |
| `jaah-vm --version` | Print version + git SHA |
| `jaah-vm --help` | Cheat sheet |

Each subcommand has its own `--help` with full flags.

---

## Manual install (if you want to inspect first)

```bash
sudo git clone https://github.com/jaahit/pm-scripts.git /opt/pm-scripts
cd /opt/pm-scripts
git log --oneline                    # audit history before running
sudo bash jaah-vm/install.sh

# Update later:
sudo git -C /opt/pm-scripts pull && sudo bash /opt/pm-scripts/jaah-vm/install.sh
```

[`bootstrap.sh`](bootstrap.sh) is the **only** file intended to be piped to bash — < 80 lines, auditable, does NOT execute remote code at runtime. It `git clone`s the repo into `/opt/pm-scripts` and delegates to the tool's own `install.sh`.

---

## Cluster context

These tools target the **jaah Proxmox cluster**:

- **3 cluster members:** pmx-01, pmx-02, pmx-06
- **3 standalone nodes:** pmx-03, pmx-04, pmx-05 (some tools refuse these)
- **1 PBS:** pbs-01 (hosts shared resources like the iso-library via NFS)
- **Subnet:** 192.168.1.0/24
- **No HA, no Load-Balance** (cluster-wide policy)
- **Default VM CPU:** `x86-64-v2-AES` (migration-safe across Xeon generations)

---

## Design principles

- **Bash first.** Operators read it; bash is universal on PVE.
- **Safety over convenience.** No remote code execution at runtime. Secrets never in git, never on `qm` argv. Destructive ops gated by ownership manifest + typed confirm.
- **Discoverable.** Tools must be usable 6 months after last touch — every tool has `--help`, `--version`, a cheat sheet on no-args, and a per-tool `README.md`.
- **Tested.** bats coverage for any security-critical logic (sanitizers, regexes, validation, ownership).

---

## Versioning

Each tool versions independently. Tags are namespaced: `<tool>/v<X.Y.Z>` (e.g., `jaah-vm/v0.4.8`).

```bash
git ls-remote --tags https://github.com/jaahit/pm-scripts.git
```

---

## Adding a new tool

See [CONTRIBUTING.md](CONTRIBUTING.md) for the standard folder layout and code conventions.

## License

MIT — see [LICENSE](LICENSE).
