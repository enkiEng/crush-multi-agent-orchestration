# Fleet artifacts — sandboxed child agents for RESGC workstations (option 2)

Parent Crush sessions delegate subtasks to unattended child agents via
`crush-agents.py`, a single-file stdio MCP server. Each child runs a
detached `crush run` inside a **bubblewrap sandbox** on the same
workstation: OS-level confinement, per-child `file://` clone, own git
branch, scaffolding (TASK.md / RESULT.md) held outside the repo.

**No Docker. No daemon. No privileged engine. No shared host.** This
replaced the container-use/Dagger fleet design after the remote-engine
premise was verified negative 2026-07-13 (see `../HANDOFF.md`).

## What a client needs (all unprivileged)

1. Crush (already in the RESGC distribution; launch via `crush-vpc`)
2. `python3` (stock RHEL9)
3. `bwrap` (bubblewrap; stock RHEL9 — 0.6.3 works, ≥ 0.8.0 adds
   nested-userns hardening via `--disable-userns`)
4. Git
5. This `fleet/` directory on disk

**WS2022 is OUT OF SCOPE for option 2**: bubblewrap is Linux-only, so
there is no sandbox story for native Windows children. Windows users
ssh to a RHEL9 host and work there.

## Files

| File | Purpose |
|---|---|
| `crush-agents.py` | The MCP server: `spawn_agent` / `agent_status` / `agent_verify` / `agent_cancel` / `agent_list` |
| `agent-sandbox.sh` | bwrap confinement wrapper (workspace-only writes, env scrubbed, optional net cut) |
| `sandbox-selftest.sh` | Adversarial confinement checklist — run on every new host before trusting children |
| `crush-init-agents.sh` | Per-repo bootstrap: writes `.crush.json` + `CRUSH.md`, checks prerequisites |
| `crush.json.option2.template` | The `.crush.json` the bootstrap installs |
| `CRUSH-rules-option2.md` | Parent delegation rules (child rules are embedded in the server) |

Historical (rejected tcp://-remote-engine design, kept as documentation
of why it died — HANDOFF "Fleet deployment architecture"):
`crush-init-sandbox.sh`, `crush-init-sandbox.ps1`, `crush.json.template`,
`CRUSH-rules.md`.

## Usage

    cd /path/to/your/git/repo
    /path/to/fleet/crush-init-agents.sh \
        --child-config ~/opt2/child-crush.json \
        --verify-cmd 'python3 -m unittest discover -s tests -t . -q'

Then start `crush-vpc` normally and ask the parent to delegate. Review:

    # in-session: agent_status <id>, then agent_verify <id>  (mandatory)
    git fetch ~/.crush-agents/<repo-slug>/<id>/home/ws <branch>:<branch>
    git diff HEAD...<branch>
    git merge <branch>          # your call, after the diff + verify

`--child-config` should point children at a DIFFERENT vLLM endpoint
than the parent (endpoint split): benchmarks showed child prefills
saturate an endpoint while a split parent stays at baseline latency.

## Why it looks the way it does (verified findings baked in)

- **Sandbox is the only control for children.** Headless `crush run`
  auto-approves every tool regardless of `allowed_tools` (verified on
  0.84 and 0.81). Children are therefore always wrapped in
  `agent-sandbox.sh`: writes confined to the workspace, parent env
  (incl. AWS creds) scrubbed, real HOME invisible.
- **`file://` clones, not worktrees.** A linked worktree commits into
  the parent repo's `.git` — a write hole through the sandbox. Clones
  also dodge the "invalid endpoint" bare-path bug hit in benchmarks.
- **Scaffolding lives OUTSIDE the repo** (`home/TASK.md`,
  `home/RESULT.md`, clone at `home/ws/`). Stage A′ showed a child will
  `git add -f` an excluded RESULT.md against instructions, giving
  sibling merges add/add conflicts. Files git can't reach can't be
  committed.
- **`agent_verify` is mandatory before any merge.** Both in-VPC 24B
  models shipped false "all tests pass" claims in benchmarks. The
  parent rules forbid reporting child success without a green
  `agent_verify` (which reruns the tests itself, network off).
- **Per-child HOME** doubles as crush state isolation — the same fix
  that eliminated cross-child state loss in benchmark addendum 2.
- **`timeout: 300`** on the MCP entry (Crush default is 15 s).

## Hardening still open (before analyst rollout, not POC-blocking)

- `net=vllm` currently means "whatever the host can reach" (bounded by
  host no-egress). TODO: per-child netns + nft allowlist to only the
  vLLM endpoint.
- Hosts with bwrap < 0.8.0 lack `--disable-userns` (nested-userns LPE
  hardening). Update bubblewrap or add a seccomp filter.
- `agent_merge` tool deliberately deferred — merges stay manual until
  the review workflow has been used in anger.
