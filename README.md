# pm-scripts

Proxmox automation scripts for the **jaah-cluster** infrastructure.

One tool per folder. Each is self-contained: source, installer, tests, docs.

## Available tools

| Tool | Purpose | Status |
|---|---|---|
| [`jaah-vm/`](jaah-vm/) | Mini AWS-EC2-style VM launcher for the cluster | v0.2.0 ✅ |

## Installing a tool on a cluster node

### One-liner (recommended)

```bash
# Always-latest from main:
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm

# Pin to a specific version (production):
bash -c "$(curl -fsSL https://raw.githubusercontent.com/jaahit/pm-scripts/main/bootstrap.sh)" -- jaah-vm --ref jaah-vm/v0.2.0
```

[`bootstrap.sh`](bootstrap.sh) is the **only** file in the repo allowed to be piped to bash. It's under 80 lines (auditable in seconds), does NOT fetch remote code at runtime — it `git clone`s the repo into `/opt/pm-scripts` and delegates to the tool's `install.sh`.

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
- **Safety over convenience.** No `curl | bash`. Secrets never in git.
- **Discoverable.** Tools must be usable 6 months after last touch.
- **Tested.** bats coverage for security-critical logic.

## Cluster context

These tools target the **jaah Proxmox cluster**:

- **3 cluster members:** pmx-01, pmx-02, pmx-06
- **3 standalone nodes:** pmx-03, pmx-04, pmx-05 (some tools refuse these)
- **1 PBS:** pbs-01 (hosts shared resources like the iso-library via NFS)
- **Subnet:** 192.168.1.0/24
- **No HA, no Load-Balance** (cluster-wide policy)

## License

MIT — see [LICENSE](LICENSE).
