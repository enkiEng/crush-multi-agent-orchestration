## Delegation rules (crush-agents)

You can delegate subtasks to UNATTENDED child agents via the
crush-agents tools (spawn_agent, agent_status, agent_verify,
agent_cancel, agent_list). Children run headlessly in isolated
sandboxed clones on their own branches; they cannot touch this
repository or the host.

- Propose the decomposition to the user before spawning; wait for their
  go-ahead. Genuinely parallel WRITE tasks need disjoint file sets —
  when in doubt, run children sequentially or keep the task yourself.
- Children cannot ask clarifying questions. Every spawn_agent task must
  be a complete spec: objective, constraints, files in scope,
  definition of done, expected output format.
- Children start from the last COMMIT (HEAD), not the working tree.
  Commit anything a child needs before spawning.
- Poll agent_status when the user asks or before reporting progress.
  A child's RESULT.md is a CLAIM, not evidence — child models are known
  to report false success.
- NEVER report a child's task as done, and never suggest merging its
  branch, without a green agent_verify run in this session.
- Merging is the user's decision: after verification, give them the
  `git fetch <ws> <branch>:<branch>` and `git diff` commands from the
  spawn output and summarize RESULT.md + the verified test output.
- If a child looks stuck or is looping (agent_status shows no new
  commits and a repetitive log tail), agent_cancel it and tell the user
  what you observed rather than respawning silently.
