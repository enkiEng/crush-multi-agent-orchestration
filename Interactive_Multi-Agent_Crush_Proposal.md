# Proposal: Interactive Multi-Agent Orchestration for Crush

**Revision:** 2 (2026-07-11)
**Supersedes:** v1 (`~/Library/Mobile Documents/com~apple~CloudDocs/Interactive_Multi-Agent_Crush_Proposal.md`)
**Changes in this revision:** corrected the `--yolo` safety claim; respecified progress reporting as file-based polling; concretized the agent commands as an MCP server; added a prior-art evaluation step; added a risks section; added an MVP plan and benchmark criteria.

## Background

Current AI coding tools generally fall into two categories:

-   **Interactive CLI** (e.g., Crush), where the user remains in control
    and collaborates with a single agent.
-   **Autonomous multi-agent systems** (e.g., Claude Code), where a
    parent agent delegates work to multiple child agents.

I would like to preserve Crush's interactive workflow while gaining
Claude Code-style parallel delegation.

Crush has no built-in subagent capability. A feature request for
exactly this ([charmbracelet/crush#1320](https://github.com/charmbracelet/crush/issues/1320))
is open with no maintainer response as of 2026-07. Building an external
orchestration layer avoids maintaining a fork; if upstream ships
orchestration natively later, little is lost.

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

Each child agent:

-   Runs as a headless Crush process: `crush run --yolo --quiet --cwd <worktree> "<task spec>"`.
    (`crush run` non-interactive mode, `--quiet`, `--cwd`, and `--yolo`
    are documented Crush behavior.)
-   Runs in its own Git worktree, on its own branch.
-   Connects to the same Kubernetes-hosted vLLM endpoint via Crush's
    `openai-compat` provider type (documented).
-   Has an independent context window.
-   Writes status to a per-agent JSONL file that the parent polls.
-   Writes a structured result file that the parent reviews before merge.

## Isolation and Safety (corrected from v1)

v1 claimed "no requirement for `--yolo`" as a benefit. That was wrong:
child agents **must** run with `--yolo` (or an exhaustive
`allowed_tools` list) because nobody is watching them to approve
permission prompts. What this design actually delivers is that the
*user's* session stays interactive while the *children* are batch.

Git worktrees isolate the git working copy **only**. A `--yolo` child
retains full filesystem access outside its worktree, plus the user's
environment variables, credentials, and network access. Worktrees are a
merge-hygiene mechanism, not a security boundary.

Two isolation postures, chosen per deployment:

| Posture | Mechanism | Protects against | Cost |
|---------|-----------|-----------------|------|
| Trust-the-model | Worktree only | Merge conflicts, dirty-tree collisions | None |
| Container isolation | One pod per agent on the existing k8s cluster (worktree mounted in), or Dagger `container-use` MCP server | Destructive shell commands, credential exposure, unwanted network egress | Pod startup latency, image maintenance |

For any environment where a runaway `rm -rf` or a call to a production
endpoint is unacceptable, use container isolation. The k8s cluster is
already present, so this is incremental effort, not new infrastructure.

## Progress Reporting (respecified from v1)

v1 said children "stream progress back to the parent session." Crush is
a Bubble Tea TUI with no documented API for injecting external async
events into a live session, so push-streaming has no implementation
path today. Respecified as **pull**:

-   Each child appends status events to `<state-dir>/<agent-id>/status.jsonl`
    (started, tool-use summary, tokens consumed, done/failed).
-   The parent model calls an `agent_status` MCP tool on demand — e.g.
    when the user asks "how are the agents doing?"
-   Optional: run children in tmux panes beside the parent for
    real-time human-visible output. This is display only; the merge
    workflow still goes through result files.

## Implementation: an MCP Server (concretized from v1)

The agent-management commands are implemented as a small stdio MCP
server registered in `crush.json` (Crush supports stdio/http/sse MCP
servers — documented). This makes the tools callable by the parent
*model*, so the parent can propose a decomposition and the user
approves via Crush's normal permission prompt — exactly the example
workflow below.

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

1.  Creates Git worktrees and writes task-spec files.
2.  Launches headless child Crush processes.
3.  Remains interactive.
4.  Reports child progress when polled.
5.  Presents `RESULT.md` + diff for review before merging.

Note the hidden dependency in this example: B (prototype) benefits from
A's findings. A dependency-aware variant runs A first, then feeds A's
`RESULT.md` into B and C's task specs. Truly parallel tasks are rarer
than they look — see Risks.

## Step 0: Evaluate Prior Art First

Worktree-per-agent orchestration is now a commodity pattern. Before
building, spend an hour confirming none of these already fits, since
several drive arbitrary CLI agents including Crush:

-   [Composio agent-orchestrator](https://github.com/ComposioHQ/agent-orchestrator)
-   Claude Squad, Vibe Kanban, and others catalogued in
    [awesome-multi-agent-orchestrators](https://github.com/Agent-Analytics/awesome-multi-agent-orchestrators)
    and [this survey](https://www.augmentcode.com/tools/open-source-agent-orchestrators)
-   [Dagger container-use](https://github.com/dagger/container-use) —
    MCP server giving each agent a containerized environment; directly
    addresses the isolation gap

The custom MCP server remains justified if the requirement is
specifically *parent-model-initiated* delegation from inside the Crush
session, which the kanban-style orchestrators do not provide. But that
should be a conscious choice, not a default.

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

## Risks and Failure Modes (new in v2)

-   **Task decomposition is the actual hard problem.** Genuinely
    parallel *write* tasks need disjoint file sets, or `agent_merge`
    becomes conflict-resolution hell. Heuristic: read-only
    research/analysis tasks parallelize well; concurrent implementation
    tasks on one subsystem usually don't. The parent's decomposition
    step is the highest-skill task in the system.
-   **Children can't ask clarifying questions.** Mitigated (not
    eliminated) by the task-spec/RESULT.md protocol above.
-   **Concurrency degrades the interactive parent.** N children with
    50–100K-token agentic contexts compete for vLLM KV-cache and
    prefill; the observable symptom will be latency spikes in the
    interactive session. vLLM supports priority scheduling — run the
    parent at higher priority. How many concurrent children the GPUs
    sustain is a hypothesis until benchmarked (see below).
-   **Model capability is the ceiling.** Multi-agent compounds per-step
    error rates, and decomposition/synthesis is the hardest step. The
    open-weight model served by vLLM will bound results far more than
    the orchestration plumbing.
-   **`--yolo` children are unsandboxed by default.** See Isolation and
    Safety; choose a posture explicitly per deployment.

## MVP Plan (new in v2)

Roughly a day of work, all on documented Crush behavior:

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

## Benefits (revised)

-   The user's workflow stays interactive; delegation is proposed by
    the parent and approved per-spawn via Crush's permission prompt.
-   Parallel exploration of alternative solutions, with review of
    `RESULT.md` + diff before any merge.
-   Git worktrees prevent working-tree collisions and keep each
    agent's work on its own branch (merge hygiene, not security).
-   Optional container isolation using infrastructure already in place.
-   Natural fit for self-hosted Kubernetes/vLLM: marginal agent cost is
    GPU time, not API dollars.
-   No Crush fork; upstream compatibility preserved.
