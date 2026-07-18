# HANDOFF — Crush Interactive Multi-Agent Orchestration

**Last updated:** 2026-07-18
**Repo:** https://github.com/enkiEng/crush-multi-agent-orchestration (public, Apache 2.0)
**Local path:** `~/AI-projects/AI-chatbots/crush-multi-agent-orchestration/` (nested repo; ignored by the parent AI-projects GitLab repo)

## Project goal

Add Claude Code-style parallel agent delegation to Charm's Crush CLI while
keeping its interactive workflow, backed by a self-hosted Kubernetes/vLLM
OpenAI-compatible endpoint. Requirements: interactive parent session,
parent-model-initiated spawning of unattended children, per-child isolation,
user review before merge.

## State as of 2026-07-18 — OPTION 2 BUILT AND VERIFIED (both stages)

After the remote-engine premise died (see the 🛑 block below), the user
chose **proposal option 2** as the RESGC path. It is now implemented and
gate-tested end-to-end; option 1 (container-use) remains proven but is
no longer the fleet direction — no Docker/Dagger anywhere.

- **Stack** (all in `fleet/`): `crush-agents.py` — single-file
  stdlib-only Python 3 stdio MCP server exposing `spawn_agent` /
  `agent_status` / `agent_verify` / `agent_cancel` / `agent_list`;
  `agent-sandbox.sh` (bwrap confinement); `sandbox-selftest.sh`
  (adversarial confinement checklist); `crush-init-agents.sh` (per-repo
  bootstrap); template + parent rules. README rewritten for option 2;
  tcp://-era files kept as historical.
- **Design facts:** per-child `file://` clone (never worktrees — their
  commits write into the parent `.git`); child HOME + scaffolding
  (TASK.md/RESULT.md/status.jsonl) at `~/.crush-agents/<slug>/<id>/home/`
  OUTSIDE the clone so children cannot commit it (a stage-A′ child
  `git add -f`-ed an excluded RESULT.md against instructions → add/add
  conflicts between siblings; physical separation fixed it);
  meta.json/child.log outside the sandbox bind (tamper-proof);
  `agent_verify` reruns tests itself (net off) with per-agent
  `verify_cmd` (stage-B′ finding: a repo-wide full-suite default
  correctly FAILs single-module branches); merges stay manual.
- **Stage A′ (Mac, sandbox=none, claude parent) PASSED** all three
  gates; session DB shows all calls through Crush's MCP client; child
  branches contain only task files; merged; host 6/6 green.
- **Stage B′ (cgg0001, real bwrap, crush-vpc mistral parent, devstral
  children) PASSED**: confinement selftest 12/12 (every escape blocked:
  real-HOME reads, env creds, outside writes, net in net=off);
  model-initiated spawns via Crush MCP client (session DB); children
  contained, honest RESULT.md with real test output; merged on host,
  6/6 green; post-run audit clean (writes only under ~/.crush-agents).
  Parent honestly reported the full-suite verify FAIL — good behavior,
  now avoidable via per-agent verify_cmd.
- **Gotcha fixed (carry to any host):** /etc/resolv.conf is a symlink
  into /run (NetworkManager) → dangles inside the sandbox → DNS falls
  back to [::1]:53 and children can't reach vLLM. agent-sandbox.sh now
  binds the dereferenced file at the symlink's target path.
- **Advantage benchmark (2026-07-18, `../benchmarks.md`):** vs a single
  plain session on identical work (3 modules/42 tests, devstral
  everywhere): delegation freed the user's session (1 s busy vs 140 s),
  was correct where the monolith shipped 2 test failures under a false
  rc=0 success (per-child focused context + agent_verify), used ~1.5×
  FEWER prompt tokens (350K vs 543K — no ever-growing agentic context),
  and ran 2.5× faster at 3-way parallelism (56 s vs 140 s). n=1 per
  condition; cleanly-decomposable tasks are the favorable case.
- **Fleet-size sweep (2026-07-18, `../benchmarks.md`):** N=1/3/6/9
  concurrent children, 19/19 verified green — no correctness knee.
  Throughput knee at ~6: **run up to 6 concurrent children per endpoint**
  for small-context tasks (2.6× wall speedup; median child stretches
  27 s→64 s from prefill queueing); keep 2–3 for 50K-token-class work.
  6→9 pays +50% workers for +18% throughput.
- **Throughput benchmark (see `../benchmarks.md` 2026-07-18):** B1 serial 25 s;
  B2 3-concurrent 36 s, 3/3 contained, 3/3 verify PASS, **all 3
  branches intact — the container-use state race is structurally gone**
  (no shared state exists). Parent-endpoint probes at baseline
  (0.10–0.14 s) throughout. ~6× faster than the container-use B1.
  Caveat: 2–4K-token contexts; 50K-context prefill saturation numbers
  from 2026-07-12 still govern big-task sizing.
- **Host facts (cgg0001):** bubblewrap 0.6.3 (no --disable-userns —
  POC-accepted gap, wrapper warns), python 3.9.25, crush
  0.81.0-resgc-copilotfix, userns sysctl at vendor default (65536),
  no sqlite3 CLI (use python), global gpgsign=true (merge with
  -c commit.gpgsign=false). vLLM image pulls are ~50 GB ≈ 12 min on a
  cold autoscaled GPU node — budget wake time accordingly.
- **Artifacts on hosts:** cgg0001 `~/opt2/` (fleet/, stageb-test with
  merged result, bench-test, bench_opt2.py, child-crush.json, logs);
  Mac `~/AI-projects/AI-chatbots/opt2-step0-test` (merged, green).
  Both vLLM deployments (devstral + mistral) **left RUNNING**
  2026-07-18 per user decision.
- **Next (option 2):** nft/slirp per-child net allowlist before analyst
  rollout; seccomp/updated-bwrap for the userns gap; task-spec/RESULT.md
  protocol is built in — pilot with 2–3 analysts via `crush-init-agents.sh`;
  then TRM with adoption evidence (POC-first). Watch crush#431.

## State as of 2026-07-12 (option 1 era — superseded by option 2 above)

- **STEP 0 COMPLETE — both stages PASSED all three gates → option 1
  (container-use) is ADOPTED.** Stage A closed on the Mac (incl. the
  user's interactive gate-3 confirmation); stage B closed on RHEL 9.8
  in the GovCloud VPC (see "Stage B results" below and the results
  blocks in the proposal's Plan section).
- Proposal is at **Revision 10** (`Interactive_Multi-Agent_Crush_Proposal.md`):
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

## Stage B results (2026-07-12): PASSED — all three gates

Host `ravlymp-ls-000` (RHEL 9.8, GovCloud VPC; reached via
`ssh mac2 'ssh rhelLS-ts ...'` — Tailscale, config on mac2). Already
present: Docker CE 29.6.1, Crush 0.81.0-resgc-copilotfix (launch via
`crush-vpc`, a Bedrock-credential-blocking wrapper), kubectl + AWS
admin, providers configured (`resgc-devstral` openai-compat →
`http://devstral.llm.resgc.internal:8000/v1`, model `devstral-small-2`).
Installed for the test: container-use v0.4.2 (checksum-verified binary
transfer). Test repo `~/stageb/stageb-test` on the host; engine runs as
container `dagger-engine-cu` (bridge network, restart=always, volume
`dagger-engine-cu2`).

Gate results: stdio stable (19 MCP calls, 3 concurrent envs, zero
transport errors); model-initiated `environment_create` through Crush's
MCP client (separate env per subtask + a combined one it invented,
pytest green in all); `list/log/diff/merge/apply` all work, merged code
re-verified 6/6 on the host.

**RHEL9/VPC gotchas (all fixed — carry these to any new host):**

1. Engine crash-loop: legacy iptables vs nftables-only RHEL9 →
   `modprobe iptable_nat` + `modprobe iptable_filter` (one module per
   call). **NOT yet persisted — add /etc/modules-load.d/ entry or a
   reboot re-breaks the engine.**
2. Global `commit.gpgsign=true` breaks container-use's internal
   commits (pinentry, no TTY) → `GIT_CONFIG_COUNT/KEY_0/VALUE_0`
   scoped in the MCP `env` in `.crush.json`.
3. Host hardening `ip_forward=0`: containers have NO general egress.
   DNS works via the bridge-gateway listener (10.87.0.1); same-subnet
   VPC endpoints ARE reachable → engine pulls from ECR
   (`468501357939.dkr.ecr.us-gov-east-1.amazonaws.com/cu-base:latest`
   = ubuntu:24.04 + python3 + pytest, built `--network=host`).
   **User decision: keep hardening; environments run offline** —
   prebake everything into the base image; set via
   `container-use config base-image set <ECR URI>` (committed in the
   test repo).
4. `"timeout": 300` on the MCP entry honored by the 0.81 build.
5. Headless-yolo reproduces on 0.81: `edit`/`bash` auto-approved
   despite the whitelist.

**Model caveat (devstral-small-2):** drives the tools but is not
robust unattended — false "tools unavailable" surrender, a 62-call
create-retry loop ending in a false "Task completed", host-file edits
against instructions (one of which was, ironically, the correct
base-image fix). Prompts must grant env permission explicitly, avoid
escape hatches, cap retries. Benchmark should compare
`mistral-small-24b` as parent.

**Ops notes:** vLLM scales to 0 on weekends
(`kubectl scale deploy vllm-devstral-24b -n llm-inference --replicas=1`
to wake; ~6 min to ready incl. GPU node autoscale). Left RUNNING after
the test per user instruction. Host reaches docker.io directly
(allowlisted egress) — the strict transfer posture wasn't needed here.
Tailscale hop ≈ 1 MB/s; use S3-via-VPC-endpoint for bulk on truly
closed hosts. Un-merged demo env on the host: `normal-lionfish`.

## Fleet deployment architecture (direction set 2026-07-12): dedicated container-host

> Client bootstrap artifacts are drafted in `fleet/` (README, bash +
> PowerShell init scripts, `.crush.json` template, agent rules) —
> reviewable attachments for the TRM/host proposal.
>
> 🛑 **BLOCKING — VERIFIED NEGATIVE (2026-07-13): the remote-engine
> premise below DOES NOT WORK as drafted.** Tested a genuine clean
> client (home Mac, Docker quit → no local engine) against the LIVE
> rhelLS engine exposed over TCP (socat bridge of buildkitd.sock and
> engine.sock, tunneled via mac2, TCP reachability confirmed).
> `_EXPERIMENTAL_DAGGER_RUNNER_HOST=tcp://host:port` HUNG with no
> connection — both via container-use stdio AND the raw dagger CLI,
> both socket types. Root cause: the working `docker-container://`
> driver runs `buildctl dial-stdio` INSIDE the engine container; a raw
> TCP bridge doesn't replicate that. **A Docker-less client (esp.
> WS2022) cannot be pointed at a remote engine over tcp://.** Not
> proven strictly impossible (Dagger may have a TLS/broker remote mode
> we didn't configure), but it is NOT the one-env-var model this design
> assumed. **The thin-client architecture in this section must be
> reworked before any host is stood up.** Fallbacks (pick at
> prod-planning): (1) run container-use ON the host, each user gets a
> restricted shell/RDP session to it; (2) build proposal option 2
> (custom worktree MCP server — no Dagger coupling, ~1-day MVP);
> (3) research a supported Dagger remote-engine mode that works
> air-gapped. Full test writeup: k8s-llm
> `docs/SYSTEM-ASSESSMENT-2026-07.md` §4.

Decision from the fleet-rollout discussion: do NOT put Docker/Dagger on
every RESGC workstation, and get the engine OFF the license server
(ravlymp-ls-000 — it hosted all Step 0/benchmark work and its disk is
at 91%). Instead, one **dedicated container-services host** (plain EC2,
RHEL9, no GPU; CPU + RAM + generous disk for the layer cache):

    RHEL9 workstations ─┐
    WS2022 instances  ──┼── tcp:// ──> dedicated container host
    Mac (staging)     ──┘              ├─ Dagger engine (TCP listener;
                                       │   all environments run here)
                                       ├─ Docker CE (hosts the engine)
                                       └─ GitHub self-hosted runner
                                           (also moving off the LS)

Key facts supporting this design (verified today unless noted):

- Clients select a remote engine via `_EXPERIMENTAL_DAGGER_RUNNER_HOST`
  — ⚠ but see the BLOCKING MUST-VERIFY above: in 2026-07-13 tests
  container-use v0.4.2 IGNORED this var entirely (used its local engine
  regardless of ssh:// or docker-container:// values). The `tcp://`
  remote-runner form is Dagger-documented but UNVERIFIED with
  container-use, and there is now positive evidence cu may not honor
  it. Note: in stage B we never actually depended on this var — cu
  auto-discovered the local `dagger-engine-cu` container. Remote use is
  the untested leap.
- **WS2022 gets sandboxing back**: the rev 7 rejection only blocked
  running the ENGINE on Windows (WSL2/nested-virt). As a thin client —
  Crush + container-use.exe (native Windows binaries exist, v0.4.0+) +
  the tcp:// env var — Windows never needs a container runtime. The
  full Windows→tcp-engine chain is UNVERIFIED; half-day smoke test
  (same three gates) once the host exists.
- Repo stays on the client; the Dagger client uploads context to the
  engine (docker-build-style), review commands run locally.
- **TRM story shrinks**: one approved container-host + an unprivileged
  client binary everywhere, instead of Docker-per-workstation. Also
  makes the Podman question less urgent (the one host runs proven
  Docker CE; rootful-Podman test remains open but non-blocking).
- **Security caveat:** the engine's TCP port has NO auth — reaching it
  ≈ root on the container host. Lock the security group to exactly the
  client instances; treat port access as a granted privilege.
- Place the host in a subnet with same-subnet ECR VPC endpoints so the
  offline-base-image pattern keeps working (that's how ravlymp-ls-000
  pulls cu-base with ip_forward=0).
- **k8s-hosted engine considered and rejected** for now: Dagger has a
  Helm chart, but the engine pod needs `privileged: true` — root-grade
  workload on the accredited production inference EKS cluster, plus
  k8s adds little for a stateful cache singleton and complicates
  host-level debugging (today's modprobe/DNS fixes). Graduation path
  if one host ever saturates: dedicated TAINTED node group running the
  Dagger Helm chart, engines never co-scheduled with production.
  (Precedent: GitHub's own hosted runners are VM-per-job, not k8s;
  ARC/k8s is only their self-hosted option.)
- **Apptainer is NOT a path for container-use/Dagger** (no Docker API,
  engine can't run unprivileged/nested). If TRM rejects both Docker
  and Podman everywhere INCLUDING the dedicated host, the fallback is
  proposal option 2 (custom worktree MCP server, ~1-day MVP) with
  children wrapped in `apptainer exec --contain` — loses container-use
  review niceties, keeps containment; unprivileged Apptainer cannot
  block network (less critical on no-egress hosts).

## Next actions (option 1 adopted)

0. **POC-first (owner principle, 2026-07-13): NO TRM submission yet.**
   RESGC runs as an extended POC; TRM is for production. Stand up the
   dedicated container-host as an ordinary POC EC2 (RHEL9, no GPU, big
   disk, same-subnet ECR endpoints, SG locked to client instances);
   migrate the engine off ravlymp-ls-000; smoke-test the remote tcp://
   chain from a RHEL9 workstation AND a WS2022 instance (Windows chain
   is the novel/unverified part); get it into a few analysts' hands via
   `fleet/`. IF the sandbox workflow proves itself in use, THEN take
   the already-drafted package to TRM with adoption evidence attached.
   Podman remains the fallback runtime (still unverified with
   container-use).
1. Persist the iptables modules on rhelLS (`/etc/modules-load.d/`).
2. ~~Benchmark~~ **DONE 2026-07-12 — see `../benchmarks.md`. Verdict:
   with devstral-small-2 the practical fleet is 1 (serial).** B1
   (serial, 1 env, 3 modules) = 2m28s, 9/9 green, contained. B2 (3
   concurrent children in clones) = 39m50s, 0/3 contained:
   `environment_create` fails in clones with local-path origin remotes
   ("invalid endpoint"), all children fell back to host writes
   (headless-yolo), one looped bash 1,092 times. Endpoint at 50K ctx:
   prefill ~30s, serializes, starves interactive traffic (probe 0.12s
   idle → 45s at 4 streams; no chunked prefill configured); prefix
   caching works. Before re-attempting parallel children: fix the child
   working-copy pattern (real git URL origin / same repo dir /
   container-use worktrees), compare mistral-small-24b, tune vLLM
   chunked-prefill/priority. devstral-small-2 as unattended child:
   NOT robust (3 pathologies observed in one day).
   **Mistral comparison + fixed-clone addendum (same day, see
   `../benchmarks.md`):** `file://` origin URLs fix the clone
   "invalid endpoint" bug → children then create envs cleanly. With
   working clones: devstral B2 = 110s wall, 3/3 contained, 2/3 done;
   mistral B2 = 100s, 3/3 contained, no loops — but **container-use's
   per-repo state races under concurrent children**: env index
   scrambled (both models), one devstral child killed, ALL THREE
   mistral result envs lost. That concurrency bug is now the dominant
   parallel blocker (fix: per-child distinct repos, or upstream).
   mistral-small-3.2-24b: calmer under parallelism, but shipped an
   8/9 result under a false "all passing" claim serially. Both models
   emit false completion claims → external test-verification gate is
   mandatory. Crush 0.81 `-m` flag breaks on project-defined providers
   ("found in multiple providers: X and X") — use a project `models`
   override instead. Both vLLM deployments left RUNNING (devstral +
   mistral) — user to decide scale-down.
   **Cheap-fix tests (same day, benchmarks.md addendum 2):**
   (a) per-child sandbox `HOME`s (XDG ignored; HOME honored; seed
   .gitconfig + .docker/config.json + .config/crush) eliminate
   cross-child env loss — 2/3 children's envs fully reviewable in
   their own state; residual single-process container-use bug
   ("failed to load state: unexpected end of JSON input" after a
   successful create) hit 1 child, which honestly stopped (retry-cap
   prompt worked). (b) Parent/child endpoint split is a COMPLETE
   success: parent probes on mistral held 0.17–0.19s (= baseline)
   while devstral was saturated by two 50K prefills (same probe on
   devstral: 60s). **Recipe for a 2–3 child fleet NOW:** parent →
   one endpoint; children → the other, each with sandbox HOME +
   file:// clone + robust prompt + external test verification.
3. Task-spec/RESULT.md protocol via CRUSH.md rules.
4. Optional: Herdr as visibility layer (audit its update pings first).
5. Watch crush#431 (native subagents would obsolete parts of this).

## After Step 0

- Benchmark before scaling (record in `../benchmarks.md`): parent-session
  latency + child throughput at 1/2/4 concurrent children with realistic
  ~50K-token contexts on the production model. This number sets fleet size.
- Watch crush#431 — native subagents would reduce/obsolete this layer.
- Open questions listed at the end of the proposal (Podman compat, Goose
  subrecipe routing, unverified orchestrators; Herdr-detection-for-Crush
  was answered 2026-07-12).

## Session log (2026-07-12, session 3 — stage B execution)

1. Recon: found the VPC path in ssh configs (this Mac → mac2 →
   `rhelLS-ts` over Tailscale); fixed the mac2 host entry (chest-homelab
   key). Discovered Docker CE, Crush-resgc, kubectl/AWS admin already
   on the host; located the vLLM services and the `crush-vpc` wrapper.
2. Transferred container-use v0.4.2 + test repo; aborted a 650 MB
   engine-image transfer after catching an arm64/amd64 mixup — direct
   docker pull on the host worked anyway (allowlisted egress).
3. Weekend surprise: vLLM scaled to 0 (user warned). User chose to
   scale up (4-GPU node autoscaled, ~6 min); user later said leave it
   up after the test.
4. Debugged four failures in sequence: engine iptables crash-loop
   (modprobe fix), gpgsign (GIT_CONFIG_* in MCP env), model
   false-surrender (prompt fix), engine DNS/egress (ip_forward=0
   hardening → user chose offline envs; built+pushed cu-base to ECR;
   engine pulls via same-subnet ECR VPC endpoint — a detour through a
   local-registry idea proved unnecessary).
5. Run 6 passed all gates; merge/apply verified 6/6 on host; wrote
   proposal rev 10 + this handoff.

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
