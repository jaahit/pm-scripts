# Contributing to pm-scripts

A new tool joins the repo as its own top-level folder, following the layout below.

## Folder layout

```
<tool-name>/
├── README.md                ← required: what, install, 3 examples, troubleshooting
├── <tool-name>              ← required: main executable (no .sh extension)
├── lib-*.sh                 ← optional: shared functions sourced by main
├── install.sh               ← required: bootstrap on a new node
├── uninstall.sh             ← required: clean removal
├── tests/*.bats             ← required: at least one bats test for security-critical logic
└── docs/                    ← optional: extended manuals for larger tools
```

## Code standards

- `#!/bin/bash`
- `set -Eeuo pipefail` (note `-E` so traps inherit into functions)
- shellcheck clean (`shellcheck <tool-name> lib-*.sh`)
- No `curl | bash` install patterns
- Secrets via files in `/etc/<tool>/`, **never** on argv (avoid `/proc/<pid>/cmdline` leaks)
- Every tool supports `--help` and `--version`

## Documentation

- `README.md` must include: 1-line description, Quick start, Installation, 3 example invocations, Troubleshooting, File reference.
- For tools >300 LOC, add `docs/operator-manual.md`.

## Testing

bats tests are mandatory for any logic touching:

- secrets parsing
- regex (especially around VMIDs / disk names — anchored patterns to avoid greedy matches)
- locking
- input validation (path traversal, command injection)

Run locally:
```bash
cd <tool-name> && bats tests/
```

## Pull request checklist

- [ ] Folder follows the layout above
- [ ] `shellcheck` passes on every `*.sh` and the main executable
- [ ] `bats tests/` all green
- [ ] `README.md` includes the required sections
- [ ] No real secrets, keys, or passwords committed
- [ ] `.gitignore` covers any new generated files

## Versioning

- Per-tool `--version` output (semver).
- Tag releases as `<tool>/v<X.Y.Z>` (e.g., `jaah-vm/v0.2.0`) so tools version independently.

## Security review

Before merging anything that handles secrets or destructive operations:

1. No `source <user-file>` — parse, don't execute.
2. No secrets on argv — write to mode-600 file, reference by path.
3. Destructive operations gated by ownership marker (tag + HMAC manifest, not tag alone).
4. Log lines sanitized — never `set -x` near secrets.
