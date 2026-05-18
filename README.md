# pm-scripts

Proxmox automation scripts for the **jaah-cluster** infrastructure.

One tool per folder. Each is self-contained: source, installer, tests, docs.

## Available tools

| Tool | Purpose | Latest |
|---|---|---|
| [`jaah-vm/`](jaah-vm/) | Mini AWS-EC2-style VM launcher for the cluster (Ubuntu 26.04 LTS cloud-init) | [`jaah-vm/v0.3.0`](https://github.com/jaahit/pm-scripts/tree/jaah-vm/v0.3.0/jaah-vm) |

## Installing a tool on a cluster node

### One-liner (recommended)

```bash
# Always-latest from main:
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm

# Pin to a specific version (production):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm --ref jaah-vm/v0.3.0
```

[`bootstrap.sh`](bootstrap.sh) is the **only** file in the repo intended to be piped to bash. Under 80 lines (auditable in seconds), does NOT execute remote code at runtime — it `git clone`s the repo into `/opt/pm-scripts` and delegates to the tool's `install.sh`. The actual tool code is then on disk, in git, version-pinned, and inspectable.

### Manual install (when you want to inspect first)

```bash
sudo git clone https://github.com/jaahit/pm-scripts.git /opt/pm-scripts
cd /opt/pm-scripts
git log --oneline                   # audit history before running
sudo bash jaah-vm/install.sh

# Updates later:
sudo git -C /opt/pm-scripts pull
```

## Adding a new tool

See [CONTRIBUTING.md](CONTRIBUTING.md) for the standard folder layout and code conventions.

## Design principles

- **Bash first.** Operators read it; bash is universal on PVE.
- **Safety over convenience.** No remote code execution at runtime. Secrets never in git, never on `qm` argv. Destructive ops gated by ownership manifest + typed confirm.
- **Discoverable.** Tools must be usable 6 months after last touch — every tool has `--help`, `--version`, a cheat sheet on no-args, and a per-tool `README.md`.
- **Tested.** bats coverage for any security-critical logic (sanitizers, regexes, validation, ownership). CI runs them on every push.

## Cluster context

These tools target the **jaah Proxmox cluster**:

- **3 cluster members:** pmx-01, pmx-02, pmx-06
- **3 standalone nodes:** pmx-03, pmx-04, pmx-05 (some tools refuse these)
- **1 PBS:** pbs-01 (hosts shared resources like the iso-library via NFS)
- **Subnet:** 192.168.1.0/24
- **No HA, no Load-Balance** (cluster-wide policy)
- **Default VM CPU:** `x86-64-v2-AES` (migration-safe across Xeon generations)

## Versioning

Each tool versions independently. Tags are namespaced: `<tool>/v<X.Y.Z>` (e.g., `jaah-vm/v0.3.0`).

```bash
# List all releases:
git ls-remote --tags https://github.com/jaahit/pm-scripts.git
```

## License

MIT — see [LICENSE](LICENSE).
