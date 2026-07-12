# HANDOFF — Crush Interactive Multi-Agent Orchestration

**Last updated:** 2026-07-12
**Repo:** https://github.com/enkiEng/crush-multi-agent-orchestration (public, Apache 2.0)
**Local path:** `~/AI-projects/AI-chatbots/crush-multi-agent-orchestration/` (nested repo; ignored by the parent AI-projects GitLab repo)

## Project goal

Add Claude Code-style parallel agent delegation to Charm's Crush CLI while
keeping its interactive workflow, backed by a self-hosted Kubernetes/vLLM
OpenAI-compatible endpoint. Requirements: interactive parent session,
parent-model-initiated spawning of unattended children, per-child isolation,
user review before merge.

## State as of 2026-07-12

- **Step 0 stage A: PASSED all three gates — fully closed**, including
  the user's own interactive gate-3 confirmation (see "Stage A results"
  below and the results block in the proposal's Plan section). Stage B
  (RHEL9 in-VPC) is the remaining gate before adoption.
- Proposal is at **Revision 8** (`Interactive_Multi-Agent_Crush_Proposal.md`):
  Herdr claims upgraded from vendor-documented to hands-on verified (rev 4),
  Herdr-supervised children documented as an alternative to `--yolo` (rev 4),
  the Crush-pane detection question answered (rev 5), a "Where Control
  Lives" section added — Herdr is mechanism, not controller (rev 6), and
  the deployment target recorded as a requirement: secure AWS GovCloud VPC,
  in-VPC k8s/vLLM, no data egress, RHEL9 driver; WS2022 rejected (rev 7),
  and stage A results + MCP-timeout gotcha + headless-yolo safety finding
  recorded (rev 8).
  The v1 original remains in iCloud
  (`~/Library/Mobile Documents/com~apple~CloudDocs/Interactive_Multi-Agent_Crush_Proposal.md`).
- Rev 2 fixed three v1 defects: the false "no `--yolo` needed" safety claim
  (children must auto-approve; worktrees are merge hygiene, not a security
  boundary), push-streaming progress (no implementation path into Crush's
  TUI — respecified as pull/polling), and concretized the agent commands as
  a stdio MCP server.
- Rev 3 integrated a deep-research options survey (109 agents, 26 sources,
  127 claims extracted, 25 triple-voter verified: 20 confirmed / 5 refuted)
  and **changed the primary recommendation** from "build custom MCP server"
  to "try Dagger container-use first, custom MCP server as fallback."

## Key verified facts (don't re-research these)

- **Crush upstream:** no user-configurable subagents. Cite issue **#431**
  (NOT #1320 — claims sourced from #1320 were refuted in verification).
  Maintainer meowgorithm confirmed 2025-12-17 subagents are planned;
  unshipped as of 2026-06. Crush has one hardcoded internal "task" subagent.
- **Crush extension points:** MCP over stdio/http/sse; `openai-compat`
  provider with `base_url` for vLLM. Known friction: #840 (container-use
  stdio broken pipe, closed not-planned), #1733 (MCP connected but not
  invoked), #2936 (vLLM tool-call regression, fixed).
- **container-use (Dagger):** Apache-2.0 stdio MCP server, official Charm
  Crush setup guide at container-use.com/agent-integrations. Parent model
  itself calls `environment_create`/`environment_open`. Isolation = fresh
  Docker/OCI container (Dagger engine/BuildKit on local Docker) + dedicated
  git branch per environment. Prereqs: Docker + Git. Experimental; last
  tagged release v0.4.2 (2025-08) though repo active through 2026-06.
- **Claude Code on vLLM needs NO proxy:** vLLM natively implements the
  Anthropic Messages API (docs.vllm.ai/en/stable/serving/integrations/claude_code/).
  Env vars only: `ANTHROPIC_BASE_URL`, dummy key/token,
  `ANTHROPIC_DEFAULT_*_MODEL`. vLLM needs `--enable-auto-tool-choice`,
  `--tool-call-parser`, `--served-model-name` (no `/`). Rust frontend
  doesn't serve `/v1/messages`.
- **Goose:** autonomous parallel subagents (default mode), but no documented
  worktree/container isolation or per-child model routing.
- **Vibe Kanban: avoid** — sunsetting (Bloop shut down 2026-04-10), never
  supported Crush.
- **Herdr** (herdr.dev): agent-aware tmux alternative; panes with automatic
  blocked/working/done/idle state, socket API + CLI (`herdr workspace
  create`, `herdr pane split/run`) so agents can orchestrate it. No worktree
  or isolation management — complementary visibility layer only.
  **Hands-on verified 2026-07-12** (herdr 0.7.3, Claude Code parent+child;
  log in the parent repo's `herdr-tests/FINDINGS.md`): pane
  split/run/read/close, `wait agent-status`, and `wait output --match` all
  work from inside a pane; `blocked` fires on permission prompts and the
  parent can read the dialog and approve via `send-keys` — so
  Herdr-supervised children need not be `--yolo`.
  **Crush panes (v0.84.1) tested same day:** built-in detection identifies
  `agent: "crush"` and fires `working`/`done` — but `blocked` does NOT fire
  on Crush permission dialogs (watch dialog text via `wait output --match`
  instead), and completion states are per-agent: Claude Code settles at
  `idle`, Crush at `done`. A herdr-based supervisor needs an agent-specific
  wait-strategy table or output sentinels. No hook integration exists for
  Crush (and none were installed for these tests — all detection observed
  is built-in pattern matching).
- **Deployment target (requirement, 2026-07-12):** secure AWS GovCloud VPC,
  in-VPC k8s/vLLM endpoint, zero data egress, RHEL9 driving host. Mac =
  staging only. **WS2022 rejected:** container-use v0.4.0+ has native
  Windows *binaries*, but the Dagger engine needs a Linux container
  runtime → Docker Desktop (unsupported on Windows Server) or WSL2 →
  nested virtualization → not available on non-metal EC2.
- **Crush phone-home kill-switches (verified from README):**
  `CRUSH_DISABLE_METRICS=1` (pseudonymous metrics; `DO_NOT_TRACK=1` also
  honored) and `CRUSH_DISABLE_PROVIDER_AUTO_UPDATE=1` (Catwalk provider-db
  pings); offline providers via `crush update-providers <local-file>` or
  the embedded list. Only remaining network calls: the LLM provider itself.
- **Dagger on Podman (documented upstream):** requires rootful Podman,
  docker-compat socket (`DOCKER_HOST=unix:///run/podman/podman.sock`),
  raised pids limit (default 2048 too low). container-use over Podman
  specifically is UNVERIFIED. Docker CE is officially packaged for RHEL9
  and is the lower-friction stage B choice if policy allows.
- Unranked for lack of evidence (not inferiority): Claude Squad, Composio
  AO, Emdash, Crystal, uzi, gwq, Conductor, Bernstein, OpenCode/Qwen/Gemini
  CLI/Aider/Roo/Cline modes, tmux DIY, SDK frameworks.

## Stage A results (2026-07-12): PASSED — all three gates

Executed headlessly (`crush run`, model `anthropic/claude-sonnet-5`) in
the throwaway repo `~/AI-projects/AI-chatbots/cu-step0-test` (gitignored
in the parent AI-projects repo; official `.crush.json` from the Charm
Crush section of container-use's agent-integrations doc + `rules/agent.md`
as `CRUSH.md`; two missing Python modules with tests as the two-subtask
split). Versions: Crush v0.84.1, container-use v0.4.2, Dagger engine
v0.18.14, Docker Desktop 29.1.3.

- **Gate 1 (stdio stability): PASS** — full session, two concurrent
  environments, zero transport errors; #840 did not reproduce.
- **Gate 2 (model-initiated spawning): PASS** — session DB shows exactly
  two `mcp_container-use_environment_create` calls through Crush's MCP
  client; both envs ran tests to green (6/6); host tree untouched.
- **Gate 3 (review workflow): PASS** — `list`/`log` (full command
  transcript incl. pytest output)/`diff` all informative; `merge`
  landed one env keeping agent commits, `apply` staged the other;
  merged code re-verified green on the host. **User-confirmed
  interactively same day:** hand-driven Crush TUI session (fresh
  truncate + initials task) spawned envs `proven-raccoon` and
  `model-cheetah`; one trust/apply prompt at session start (project
  `.crush.json`), then unattended to completion (whitelisted tools);
  user ran `log`/`diff` review and judged the workflow workable.
  Those two envs were left un-merged in `cu-step0-test` on purpose —
  available for future merge/apply demos.
- **Gotcha (root-caused, fixed):** Crush's MCP connect timeout defaults
  to **15 s**; container-use's first-ever start takes ~90 s (Dagger
  engine image pull) → MCP init dies ("context canceled" in
  `.crush/logs/crush.log`) and tools are absent all session. Fix:
  `"timeout": 300` on the MCP entry. For stage B: pre-pull the engine
  image and warm with `container-use list` before the first session.
- **Safety finding:** in the failed-init run the model drove the MCP
  server via `bash` — headless `crush run` auto-approved `bash` despite
  an `allowed_tools` whitelist that did not include it.
  **Non-interactive mode is effectively `--yolo`;** the whitelist only
  governs interactive sessions. Child confinement = container boundary.
- Environments live inside the single Dagger engine container, not as
  separate top-level containers (one engine image to mirror for ECR).
- Also re-verified: the "Charm Crush" section still exists in
  container-use's `docs/agent-integrations.mdx` (it's just not in the
  first 200 lines of the rendered page).

## Next action: Step 0 stage B (RHEL9 in-VPC — the real gate)

Repeat stage A on RHEL9 inside the GovCloud VPC against the in-VPC vLLM
endpoint with the no-egress checklist (proposal Plan section): mirror
`registry.dagger.io/engine:v0.18.14` + base images into GovCloud ECR,
install from transferred binaries, set `CRUSH_DISABLE_METRICS=1` +
`CRUSH_DISABLE_PROVIDER_AUTO_UPDATE=1`, providers from a local file;
Docker CE if policy allows, else rootful Podman (docker-compat socket,
raised pids limit — container-use-over-Podman is itself a stage B gate).
Carry over the stage A fixes: `"timeout": 300` on the MCP entry and
pre-warm the engine before the first session.

**Stage B pass →** adopt option 1; add task-spec/RESULT.md protocol via
CRUSH.md; optionally add Herdr as visibility layer (audit its update
pings first for in-VPC use — unverified).
**Fail gate 1/3 →** build option 2 (custom stdio MCP server over
worktrees; ~1 day MVP; spec is in the proposal).

## After Step 0

- Benchmark before scaling (record in `../benchmarks.md`): parent-session
  latency + child throughput at 1/2/4 concurrent children with realistic
  ~50K-token contexts on the production model. This number sets fleet size.
- Watch crush#431 — native subagents would reduce/obsolete this layer.
- Open questions listed at the end of the proposal (Podman compat, Goose
  subrecipe routing, unverified orchestrators; Herdr-detection-for-Crush
  was answered 2026-07-12).

## Session log (2026-07-12, session 2 — stage A execution)

1. Installed container-use v0.4.2 (brew), started Docker Desktop; verified
   the Charm Crush guide still exists in container-use's docs.
2. Built the `cu-step0-test` repo (official `.crush.json` + `CRUSH.md`
   rules + two-module task); gitignored it in the parent AI-projects repo.
3. Run 1 (headless, claude-sonnet-5): MCP init died at exactly 15 s
   (default timeout) during the ~90 s cold Dagger-engine pull; the model
   improvised by driving the MCP server via bash — work still done in
   containers, exposing the headless-yolo behavior.
4. Root-caused via `.crush/logs/crush.log` + the crush.json schema
   (MCPConfig `timeout`, default 15); set `"timeout": 300`.
5. Run 2: clean pass through Crush's MCP client — all three gates green
   (verified via session DB tool-call names, container-use log/diff,
   merge + apply, host re-test 6/6).
6. Wrote proposal rev 8 (stage A results, timeout gotcha, headless-yolo
   safety finding, open question half-answered) and updated this handoff.
7. Seeded a round-2 task (truncate + initials) in `cu-step0-test`; user
   ran the interactive Crush session and the `log`/`diff` review by hand
   and confirmed gate 3 first-hand (one trust prompt at start, then
   unattended). Recorded as rev 9.

## Session log (2026-07-12, session 1)

1. Tested herdr 0.7.3 live from inside a pane (herdr-tests dir of the parent
   repo): two-agent orchestration (spawn/assign/wait/read) and blocked-state
   permission handling both verified; findings committed to the parent repo
   as `herdr-tests/FINDINGS.md`.
2. Wrote proposal rev 4: Herdr upgraded to hands-on-verified; added the
   Herdr-supervision alternative to `--yolo` in Isolation and Safety.
3. Installed Crush v0.84.1 on the Mac (brew) and tested Herdr detection of
   Crush panes; answered the open question (rev 5). Findings appended to
   `herdr-tests/FINDINGS.md` (test 4) in the parent repo.
4. Added "Where Control Lives" section (rev 6): user = strategic control,
   parent Crush model = tactical control, Herdr = passive switchboard.
5. Recorded deployment target (rev 7): GovCloud VPC + in-VPC vLLM +
   RHEL9, no egress; researched and rejected WS2022 (WSL2 needs nested
   virt, absent on non-metal EC2); split Step 0 into Mac stage A +
   in-VPC RHEL9 stage B with a no-egress checklist; verified Crush
   kill-switch env vars and Dagger-on-Podman requirements.

## Session log (2026-07-11)

1. Read AI-chatbots folder context; evaluated v1 proposal from iCloud.
2. Wrote rev 2 (fixed yolo claim, progress model, MCP concretization).
3. Created this repo; published to github.com/enkiEng (public, Apache 2.0).
4. Added nested-repo ignore to parent AI-projects `.gitignore`; pushed to
   GitLab (rebased over incoming /boot-initramfs commits).
5. Ran deep-research workflow on the options landscape; researched Herdr
   separately at user request.
6. Wrote rev 3 with changed recommendation; pushed.
7. Explained container-use container model + Step 0; wrote this handoff.
