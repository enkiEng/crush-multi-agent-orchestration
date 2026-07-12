# Fleet artifacts — sandboxed-agent mode for RESGC workstations

Client-side bootstrap for the **dedicated container-host architecture**
(see `../HANDOFF.md`, "Fleet deployment architecture"): every
environment executes on one approved container-services host running
the Dagger engine; workstations are thin clients.

## What the client needs (no privileges, no local Docker)

1. `container-use` binary on PATH (single unprivileged file; Linux and
   Windows builds from dagger/container-use v0.4.2+, checksum-verified)
2. Crush (already in the RESGC distribution; launch via `crush-vpc`)
3. Network reachability to the container-host engine port
   (security-group grant — treat as a privilege)
4. Git

## Files

| File | Purpose |
|---|---|
| `crush-init-sandbox.sh` | Per-project bootstrap, RHEL9/macOS clients |
| `crush-init-sandbox.ps1` | Per-project bootstrap, WS2022 clients |
| `crush.json.template` | The `.crush.json` the scripts install (placeholders `{{ENGINE}}`) |
| `CRUSH-rules.md` | Agent rules installed as the project `CRUSH.md` |

## Usage

    cd /path/to/your/git/repo
    crush-init-sandbox.sh --engine tcp://cu-host.resgc.internal:8080

Then start `crush-vpc` normally. The agent's file/shell work happens in
container-use environments on the container host; review with
`container-use list / log <id> / diff <id>`, land with `merge <id>`
(keeps agent commits) or `apply <id>` (stage for your own commit).

## Baked-in fixes (why the template looks the way it does)

- `"timeout": 300` — Crush's MCP connect timeout defaults to 15 s;
  container-use's first-ever start can exceed it (verified 2026-07-12).
- `GIT_CONFIG_*` env — global `commit.gpgsign=true` breaks
  container-use's internal commits (no TTY for pinentry); this scopes
  `commit.gpgsign=false` to the MCP server process only.
- `_EXPERIMENTAL_DAGGER_RUNNER_HOST=tcp://…` — selects the remote
  engine; the `tcp://` form needs no local Docker CLI.
- 12-tool `allowed_tools` whitelist — unattended container-use calls in
  interactive sessions. NOTE (verified 2026-07-12): headless
  `crush run` auto-approves ALL tools regardless of this whitelist;
  the container boundary, not the whitelist, is the control for
  unattended runs.
- Base image pinned to the ECR `cu-base` mirror — environments are
  offline (no egress from the engine's build containers); everything
  needed must be prebaked into the base image.

## Known-unverified

The `tcp://` remote-engine chain (esp. from Windows) has not yet been
smoke-tested end-to-end — run the three-gate test (transport stability,
model-initiated `environment_create`, review workflow) from one RHEL9
and one WS2022 client as the first act after the container host exists.
