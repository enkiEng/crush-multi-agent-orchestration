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

- Proposal is at **Revision 4** (`Interactive_Multi-Agent_Crush_Proposal.md`):
  Herdr claims upgraded from vendor-documented to hands-on verified, and
  Herdr-supervised children documented as an alternative to `--yolo`.
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
  Herdr-supervised children need not be `--yolo`. Gotcha: finished turns
  settle at `idle`, not `done`; wait on `idle` or a sentinel. Crush is
  still not a named integration (Crush-pane state detection untested).
- Unranked for lack of evidence (not inferiority): Claude Squad, Composio
  AO, Emdash, Crystal, uzi, gwq, Conductor, Bernstein, OpenCode/Qwen/Gemini
  CLI/Aider/Roo/Cline modes, tmux DIY, SDK frameworks.

## Next action: Step 0 smoke test (~half a day)

Answers the one gating unknown: does Crush + container-use work on current
versions despite #840?

1. Docker running; `brew install dagger/tap/container-use`;
   `container-use version`. (RHEL9/work machines: docs say Docker —
   Podman-socket compatibility is UNVERIFIED; test on the Mac first.)
2. In a test repo: add `container-use stdio` as a stdio MCP server in
   `.crush.json` (Crush guide at container-use.com/agent-integrations); add
   their recommended agent rules to `CRUSH.md` (without rules the model
   won't reach for the tools).
3. Keep the existing vLLM `openai-compat` provider config unchanged.
4. Interactive Crush session; give a task that splits into two independent
   subtasks ("use a separate environment for each"). Watch three gates:
   - **Gate 1 — transport stability:** stdio survives a full session with
     two concurrent environments (failure = #840 mode → fall back to
     custom MCP server, option 2 in the proposal).
   - **Gate 2 — model-initiated spawning:** the model actually calls
     `environment_create` twice unprompted (failure = model tool-calling
     weakness or #1733 → problem is the model, not plumbing; fix that
     before building anything).
   - **Gate 3 — review workflow:** `container-use list` / `log <id>` /
     `diff <id>` / `checkout <id>`, then `merge <id>` (keeps agent commits)
     or `apply <id>` (stage for own commit) feels workable.

**Pass →** adopt option 1; add task-spec/RESULT.md protocol via CRUSH.md;
optionally add Herdr as visibility layer.
**Fail gate 1/3 →** build option 2 (custom stdio MCP server over worktrees;
~1 day MVP; spec is in the proposal).

## After Step 0

- Benchmark before scaling (record in `../benchmarks.md`): parent-session
  latency + child throughput at 1/2/4 concurrent children with realistic
  ~50K-token contexts on the production model. This number sets fleet size.
- Watch crush#431 — native subagents would reduce/obsolete this layer.
- Open questions listed at the end of the proposal (Podman compat, Herdr
  state detection for Crush, Goose subrecipe routing, unverified
  orchestrators).

## Session log (2026-07-12)

1. Tested herdr 0.7.3 live from inside a pane (herdr-tests dir of the parent
   repo): two-agent orchestration (spawn/assign/wait/read) and blocked-state
   permission handling both verified; findings committed to the parent repo
   as `herdr-tests/FINDINGS.md`.
2. Wrote proposal rev 4: Herdr upgraded to hands-on-verified; added the
   Herdr-supervision alternative to `--yolo` in Isolation and Safety.

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
