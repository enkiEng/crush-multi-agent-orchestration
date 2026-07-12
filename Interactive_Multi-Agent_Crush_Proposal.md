# Proposal: Interactive Multi-Agent Orchestration for Crush

**Revision:** 5 (2026-07-12)
**Supersedes:** v4 (2026-07-12); v3 (2026-07-11); v2 (2026-07-11); v1
(iCloud original)
**Changes in this revision:** answered rev 4's remaining open question —
Herdr (0.7.3) **does detect Crush panes** (Crush v0.84.1) via built-in
detection: agent identification and `working` state work, but `blocked`
does **not** fire on Crush's permission dialogs (it does for Claude
Code), and Crush settles at `done` where Claude Code settles at `idle`.
Consequence: Herdr supervision of Crush children is viable but must use
output-matching (`wait output --match`) instead of the `blocked` state,
and completion-waits are agent-specific.

**Changes in revision 4:** upgraded the Herdr assessment from
vendor-documented to hands-on verified (herdr 0.7.3, Claude Code
parent/child test, 2026-07-12): socket-API orchestration, blocked-state
detection, and remote permission-prompt approval all work, with one
`done`-vs-`idle` wait gotcha. Consequence: Herdr-supervised children
need not run `--yolo` (see Isolation and Safety).

**Changes in revision 3:** integrated a deep-research survey of the options
landscape (109-agent research run, 26 sources, every claim below marked
"verified" survived 3-voter adversarial verification on 2026-07-11).
Corrected the Crush upstream citation (#431, not #1320). **Changed the primary
recommendation** from build-custom-MCP-server to adopt-container-use-first,
with the custom MCP server as fallback/complement. Added Claude Code-on-vLLM
(no proxy needed), Goose, and Herdr assessments; disqualified Vibe Kanban.

## Background

Current AI coding tools generally fall into two categories:

-   **Interactive CLI** (e.g., Crush), where the user remains in control
    and collaborates with a single agent.
-   **Autonomous multi-agent systems** (e.g., Claude Code), where a
    parent agent delegates work to multiple child agents.

I would like to preserve Crush's interactive workflow while gaining
Claude Code-style parallel delegation.

**Upstream status (verified):** Crush has no *user-configurable*
subagent feature. It does ship one hardcoded internal "task" subagent
that the coder agent can delegate exploratory work to (model-initiated,
temporary, for context isolation), but there is no way to define custom
subagents, per-subagent models, or parallel background children.
Feature request [charmbracelet/crush#431](https://github.com/charmbracelet/crush/issues/431)
(opened 2025-07-31) is open, and Charm maintainer meowgorithm confirmed
on 2025-12-17 that subagents and skills are **planned** — but nothing
had shipped as of 2026-06. External tooling is therefore required today,
and this proposal should be revisited when #431 ships (it may obsolete
most of it).

## Core Idea

Introduce a lightweight orchestration layer that allows the current
interactive Crush session to spawn background child agents. The user
continues interacting only with the parent session; the children run
unattended (batch).

                    User
                      |
                 Crush Session (interactive parent)
                      |
          -------------------------
          |           |           |
       Agent A     Agent B     Agent C
       (batch)     (batch)     (batch)

Crush's extension points support this without forking (verified):
MCP servers over stdio/http/sse, and OpenAI-compatible custom providers
(`openai-compat` + `base_url`) so a self-hosted vLLM endpoint serves all
inference. Known friction to retest on current versions: crush#840
(stdio broken pipe with container-use, closed not-planned), crush#1733
(MCP connected but sometimes not invoked), crush#2936 (vLLM tool-call
regression in v0.67.0, since fixed).

## Options Landscape (deep research, 2026-07-11)

Ranked for this environment (interactive Crush parent, self-hosted
vLLM/K8s, per-child isolation, review-before-merge):

### 1. Keep Crush + Dagger container-use MCP server — recommended first try

[container-use](https://github.com/dagger/container-use) (Apache-2.0,
Dagger) is a stdio MCP server that works with any MCP-capable agent and
has an [official Charm Crush setup guide](https://container-use.com/agent-integrations)
(config in `.crush.json`, rules in `CRUSH.md`) among 18+ agents
(verified). It satisfies four requirements at once:

-   **Parent-model-initiated spawning:** the agent itself calls
    `environment_create` / `environment_open` MCP tools (verified).
-   **Dual-layer isolation:** each agent/task gets a fresh container
    backed by its own Git branch, orchestrated by the Dagger engine
    (verified) — stronger than the worktree-only posture in earlier
    revisions of this proposal.
-   **Zero Crush replacement cost**, and the vLLM `openai-compat`
    config is unchanged.
-   **Review-before-merge:** structurally supported by
    branch-per-environment (review UX not independently verified).

Caveats (verified): the project self-labels experimental; last
confirmed tagged release v0.4.2 (2025-08) though repo pushes continued
through 2026-06; crush#840 reported a stdio broken pipe with
container-use 0.4.1 and was closed not-planned. **A hands-on smoke test
on current versions is mandatory before committing.** Requires a
container runtime on the host.

### 2. Custom stdio MCP server over git worktrees — fallback/complement

The v2 design (below) remains fully feasible per Crush's documented MCP
support and uses the exact integration mechanism container-use proves
out. Build it if the container-use smoke test fails, if the Docker/
Dagger dependency is unwanted, or if worktree-level isolation plus the
task-spec/RESULT.md protocol is a better fit. Roughly a day for the MVP.

### 3. Claude Code pointed directly at vLLM — cheaper than assumed, replaces Crush UX

vLLM's default frontend **natively implements the Anthropic Messages
API** — no LiteLLM, no claude-code-router (verified via
[official vLLM docs](https://docs.vllm.ai/en/stable/serving/integrations/claude_code/)).
Setup is env vars only: `ANTHROPIC_BASE_URL` to the vLLM server, dummy
`ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN`, and
`ANTHROPIC_DEFAULT_OPUS/SONNET/HAIKU_MODEL` overrides. This brings
Claude Code's mature native Task/subagent orchestration to self-hosted
inference. Qualifiers (verified): vLLM must run with
`--enable-auto-tool-choice`, `--tool-call-parser`, and
`--served-model-name` (no `/` in the name); the served model needs
strong tool-calling; the experimental Rust frontend does not serve
`/v1/messages`. Cost: abandons the Crush interface.

### 4. Goose (Agentic AI Foundation, ex-Block) — autonomous subagents, weak isolation

Goose's main agent **autonomously decides** to spawn subagents in its
default autonomous mode, and tasks execute in parallel (~10 concurrent,
verified). But its subagents docs describe no worktree or container
isolation and no per-subagent model routing — two of five requirements
undocumented. Possibly closable via subrecipe `goose_provider`/
`goose_model` overrides (unverified). Weaker than options 1–2 here.

### Complementary: Herdr — visibility layer, not an orchestrator

[Herdr](https://herdr.dev/) (Rust, ~10MB single binary, ~12k stars by
2026-06) is an *agent-aware* terminal multiplexer: tmux-style
panes/persistence/SSH plus automatic per-pane agent state detection
(blocked / working / done / idle) with notifications. It is
programmatically drivable — `herdr workspace create`, `herdr pane
split`, `herdr pane run`, and a socket API; "agents can orchestrate
it." Any terminal agent runs in it; Crush is not a named integration,
so rich state detection for Crush children is unconfirmed. Herdr does
**not** manage worktrees or isolation (its own comparison page defers
that to worktree tools) — so it complements options 1–2 as the
process-visibility layer rather than competing with them.

**Hands-on verification (2026-07-12, herdr 0.7.3, Claude Code
parent and child):** the socket API works as documented, driven
entirely from inside a pane. A parent agent spawned a child pane
(`pane split --no-focus`), launched a second agent with its task
preloaded (`pane run`), and synchronized on state transitions with
`wait agent-status` — `working` fired at startup and, critically,
`blocked` fired the moment the child hit a permission prompt. The
parent then read the exact dialog with `pane read` (command, rationale,
options), approved it remotely with `pane send-keys enter`, and the
child completed the task. New prompts can also be injected into a
child's live session (`pane send-text` + `send-keys enter`).

**Crush-pane verification (same day, Crush v0.84.1):** Herdr's
*built-in* detection covers Crush — no hook integration exists for it
(nor were any installed for the tests above; even Claude Code detection
was pattern-based). `pane get` identifies `agent: "crush"` within
seconds, and `working` fires when a task starts. Two asymmetries vs
Claude Code: Crush's permission dialogs (Allow / Allow for Session /
Deny) do **not** trigger `blocked` — the pane stays `working`, so
supervision must watch for the dialog with `wait output --match` — and
a finished Crush turn settles at `done` where Claude Code settles at
`idle`. Remote driving of the Crush TUI works (`send-keys enter`
approves the dialog; `tab` toggles editor/chat focus and `enter` only
submits with the editor focused). Net: completion- and blocked-waits
are **agent-specific**; a supervisor needs a per-agent wait-strategy
table or output sentinels rather than one state machine. Full log:
`herdr-tests/FINDINGS.md` in the (private) AI-projects GitLab repo.

### Disqualified and unranked

-   **Vibe Kanban — avoid** (verified): sunsetting after Bloop's
    2026-04-10 shutdown (last release v0.1.44, 2026-04-24), and it
    never supported Crush (hardcoded executors; zero Crush references
    in the codebase).
-   **Unranked for lack of verified evidence** (not assessed
    inferiority): Claude Squad, Composio agent-orchestrator, Emdash,
    Crystal, uzi, gwq, Conductor, Agent Kanban, Bernstein, OpenCode
    subagents, Qwen Code, Gemini CLI, Aider, Roo Code/Cline orchestrator
    modes, raw tmux DIY, and framework builds (Claude Agent SDK, OpenAI
    Agents SDK, LangGraph). The heavier framework path is unjustified
    while options 1–2 exist.

## Isolation and Safety

v1 claimed "no requirement for `--yolo`" as a benefit. That was wrong:
child agents **must** run with `--yolo` (or an exhaustive
`allowed_tools` list) because nobody is watching them to approve
permission prompts. What this design actually delivers is that the
*user's* session stays interactive while the *children* are batch.

The 2026-07-12 Herdr verification adds a third option: children running
in Herdr panes *do* have a watcher. The parent can block on
`wait agent-status --status blocked`, inspect the child's permission
dialog with `pane read`, and approve or deny with `pane send-keys` —
verified end-to-end with a Claude Code child. This is supervision, not
isolation: each privileged command is gated on parent review instead of
blanket trust, and it composes with either isolation posture below. For
Crush children specifically, the `blocked` signal does not fire on
permission dialogs (verified 2026-07-12), so the parent must detect
them with `wait output --match` on the dialog text instead — workable,
but less robust than the event-driven Claude Code path. Either way the
parent must genuinely review the dialog — auto-Enter on every prompt is
`--yolo` with extra steps.

Git worktrees isolate the git working copy **only**. A `--yolo` child
retains full filesystem access outside its worktree, plus the user's
environment variables, credentials, and network access. Worktrees are a
merge-hygiene mechanism, not a security boundary.

Isolation postures, in increasing strength:

| Posture | Mechanism | Protects against | Cost |
|---------|-----------|-----------------|------|
| Trust-the-model | Worktree only (option 2 MVP) | Merge conflicts, dirty-tree collisions | None |
| Container per agent | container-use (option 1), or one pod per agent on the existing k8s cluster | Destructive shell commands, credential exposure, unwanted network egress | Container runtime, image maintenance |

Option 1 makes the stronger posture the default rather than an upgrade,
which is a further argument for trying it first.

## Progress Reporting

v1 said children "stream progress back to the parent session." Crush is
a Bubble Tea TUI with no documented API for injecting external async
events into a live session, so push-streaming has no implementation
path today. Respecified as **pull**, with two implementations:

-   **Option 1 path:** container-use environments are inspectable via
    its own tooling and git branches; the parent model queries via MCP.
-   **Option 2 path:** each child appends status events to
    `<state-dir>/<agent-id>/status.jsonl`; the parent model calls an
    `agent_status` MCP tool on demand.
-   **Either path + Herdr:** run children in Herdr panes for
    human-visible live output with automatic blocked/working/done/idle
    state and notifications — machine-readable via Herdr's socket API.
    This supersedes the plain-tmux suggestion from v2. State detection,
    blocking waits, and remote prompt handling verified hands-on
    2026-07-12 for both Claude Code and Crush panes (see the Herdr
    section) — with per-agent asymmetries: completion settles at `idle`
    for Claude Code but `done` for Crush, and Crush permission dialogs
    don't raise `blocked`.

## Implementation: an MCP Server (option 2 detail)

The agent-management commands are implemented as a small stdio MCP
server registered in `crush.json`. This makes the tools callable by the
parent *model*, so the parent can propose a decomposition and the user
approves via Crush's normal permission prompt.

Tools:

    spawn_agent(worktree, branch, task_spec)   # git worktree add + crush run, detached
    agent_status(agent_id)                     # read status.jsonl, summarize
    agent_cancel(agent_id)                     # kill process, leave worktree for inspection
    agent_merge(agent_id)                      # present result file + diff; merge on approval
    agent_list()                               # all agents, states, branches

Task handoff protocol (mitigates the no-clarifying-questions failure
mode — an unattended child with a vague prompt burns GPU time
off-spec):

-   The parent writes a structured task-spec file into the worktree:
    objective, constraints, files in scope, definition of done, output
    format.
-   The child's prompt requires it to write `RESULT.md` (what was done,
    what was not, open questions) before exiting.
-   `agent_merge` reviews `RESULT.md` plus the diff, never a bare diff.

The same protocol applies under option 1, with container-use
environments in place of bare worktrees.

## Example Workflow

User:

> Redesign this subsystem.

Parent:

> This task can be parallelized.
>
> Would you like me to:
>
> -   Agent A: Investigate the existing architecture
> -   Agent B: Prototype a new implementation
> -   Agent C: Analyze testing impacts

User:

> Yes.

The parent (via MCP tools, each spawn surfaced through Crush's
permission prompt):

1.  Creates isolated environments (containers or worktrees) and writes
    task-spec files.
2.  Launches headless child agents.
3.  Remains interactive.
4.  Reports child progress when polled.
5.  Presents `RESULT.md` + diff for review before merging.

Note the hidden dependency in this example: B (prototype) benefits from
A's findings. A dependency-aware variant runs A first, then feeds A's
`RESULT.md` into B and C's task specs. Truly parallel tasks are rarer
than they look — see Risks.

## Why This Fits My Environment

My environment already includes:

-   Kubernetes
-   vLLM
-   OpenAI-compatible endpoints
-   Crush as the interactive coding interface

Because inference is hosted internally, additional agents simply become
additional clients of the existing vLLM service. The main constraints
become GPU throughput, concurrency, and context length rather than API
costs.

## Risks and Failure Modes

-   **Task decomposition is the actual hard problem.** Genuinely
    parallel *write* tasks need disjoint file sets, or merging becomes
    conflict-resolution hell. Heuristic: read-only research/analysis
    tasks parallelize well; concurrent implementation tasks on one
    subsystem usually don't. The parent's decomposition step is the
    highest-skill task in the system.
-   **Children can't ask clarifying questions.** Mitigated (not
    eliminated) by the task-spec/RESULT.md protocol.
-   **Concurrency degrades the interactive parent.** N children with
    50–100K-token agentic contexts compete for vLLM KV-cache and
    prefill; the observable symptom will be latency spikes in the
    interactive session. vLLM supports priority scheduling — run the
    parent at higher priority. How many concurrent children the GPUs
    sustain is a hypothesis until benchmarked (see below).
-   **Model capability is the ceiling.** Multi-agent compounds per-step
    error rates, and decomposition/synthesis is the hardest step. The
    open-weight model served by vLLM will bound results far more than
    the orchestration plumbing. (This also gates option 3: Claude
    Code-on-vLLM inherits the same model's tool-calling strength.)
-   **`--yolo` children are unsandboxed by default** under option 2's
    MVP posture. See Isolation and Safety.
-   **Integration bit-rot.** The Crush+container-use broken-pipe report
    (crush#840) was closed not-planned; both projects move fast. The
    smoke test below is the gate, and it should be re-run on upgrades.

## Plan (revised)

**Step 0 — smoke test option 1 (half a day):** install container-use on
current versions, wire it into `.crush.json` per the official guide,
and run a two-child parallel task against the vLLM endpoint. Gate on:
stdio stability (the #840 failure mode), model-initiated
`environment_create` actually firing, and branch-per-environment review
working.

**If the smoke test passes:** adopt option 1. Add the task-spec/
RESULT.md protocol via `CRUSH.md` rules. Optionally add Herdr as the
visibility layer for child sessions.

**If it fails:** build option 2 — the MVP is roughly a day:

1.  Stdio MCP server exposing `spawn_agent` / `agent_status` /
    `agent_cancel` / `agent_list` (defer `agent_merge` — do the first
    merges manually to learn what review needs).
2.  `spawn_agent` = `git worktree add` + task-spec file + detached
    `crush run --yolo --quiet --cwd <worktree>`.
3.  Status via JSONL files; results via required `RESULT.md`.
4.  Trust-the-model isolation for the MVP; container isolation before
    any use on systems with credentials or production access.

**Benchmark before scaling** (record in `benchmarks.md`): with the
production model and realistic ~50K-token agentic contexts, measure
parent-session latency and child throughput at 1, 2, 4 concurrent
children. That number — not the orchestrator — determines the practical
fleet size.

**Watch upstream:** subscribe to crush#431. Native subagents are
officially planned and would reduce or eliminate the need for this
layer.

## Open Questions

-   Does Crush + container-use work reliably on current (mid-2026)
    versions, given #840 was closed not-planned? (Step 0 answers this.)
-   Real capability of the unverified orchestrators (Claude Squad, uzi,
    gwq, Crystal, Emdash, Conductor, Composio AO) for Crush /
    parent-model-initiated spawning — no verified evidence either way.
-   When will crush#431 ship, and will it include parallel background
    execution and per-subagent isolation?
-   Can Goose achieve per-child model routing and real isolation via
    subrecipes/extensions?
-   ~~Does Herdr's state detection work for Crush panes without a named
    integration?~~ **Answered 2026-07-12:** yes for agent identification
    and `working`/`done`; no for `blocked` on permission dialogs (use
    `wait output --match` instead). See the Herdr section.

## Benefits

-   The user's workflow stays interactive; delegation is proposed by
    the parent and approved per-spawn via Crush's permission prompt.
-   Parallel exploration of alternative solutions, with review of
    `RESULT.md` + diff before any merge.
-   Container-plus-branch isolation by default under option 1;
    worktree merge-hygiene at minimum under option 2.
-   Natural fit for self-hosted Kubernetes/vLLM: marginal agent cost is
    GPU time, not API dollars.
-   No Crush fork; upstream compatibility preserved, with a clear
    migration path if crush#431 ships native subagents.

## Research Provenance

Options landscape verified 2026-07-11 by a fan-out deep-research run:
6 search angles, 26 sources fetched, 127 claims extracted, 25
adversarially verified by three independent voters each (20 confirmed,
5 refuted, 0 unverified). Refuted claims — including two sourced from
crush#1320 and one mischaracterizing Vibe Kanban's spawning model —
were excluded above. Primary sources: [crush README](https://github.com/charmbracelet/crush),
[crush#431](https://github.com/charmbracelet/crush/issues/431),
[container-use](https://github.com/dagger/container-use) and its
[agent-integrations docs](https://container-use.com/agent-integrations),
[Dagger blog](https://dagger.io/blog/agent-container-use/),
[vLLM Claude Code integration docs](https://docs.vllm.ai/en/stable/serving/integrations/claude_code/),
[Goose subagents docs](https://goose-docs.ai/docs/guides/context-engineering/subagents/),
[vibe-kanban](https://github.com/BloopAI/vibe-kanban),
[herdr.dev](https://herdr.dev/).

Herdr claims upgraded to hands-on verified on 2026-07-12: two-agent
orchestration and blocked-state handling tested live on herdr 0.7.3
with Claude Code as parent and child, and Crush v0.84.1 pane detection
tested the same day (test log: `herdr-tests/FINDINGS.md` in the private
AI-projects GitLab repo).
