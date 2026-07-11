# Interactive Multi-Agent Orchestration for Crush

A design proposal for adding Claude Code-style parallel agent delegation
to [Crush](https://github.com/charmbracelet/crush) while keeping its
interactive workflow: an external orchestration layer (stdio MCP server)
that spawns headless `crush run` children in isolated Git worktrees
against a self-hosted Kubernetes/vLLM inference backend.

See [Interactive_Multi-Agent_Crush_Proposal.md](Interactive_Multi-Agent_Crush_Proposal.md)
for the full proposal, including isolation postures, failure modes, and
an MVP plan.

## License

[Apache 2.0](LICENSE)
