#!/bin/bash
# agent-sandbox.sh — run an untrusted agent command confined to one
# workspace, using bubblewrap (OS-level sandbox; NO Docker, NO daemon,
# NO privileged engine). This is the isolation core for proposal
# option 2's spawn_agent = per-child file:// clone + this wrapper +
# detached `crush run` (see fleet/crush-agents.py).
#
# The workspace must be a STANDALONE clone, not a linked `git worktree`:
# a worktree's commits write into the parent repo's .git (shared object
# store), which would punch a write hole through the sandbox boundary.
# A standalone clone needs no binds beyond the workspace itself.
#
# PROVEN 2026-07-14 on ravlympcgg0001 (standard RESGC RHEL9): runs fully
# UNPRIVILEGED with zero hardening change (userns at RHEL9 vendor
# default). On hosts hardened with user.max_user_namespaces=0 (e.g.
# rhelLS), either set that sysctl >0 or make bwrap setuid.
#
# Verified confinement: child may write ONLY the workspace; cannot read
# the real HOME (~/.aws, ~/.ssh) or write outside; parent env (incl.
# AWS_* creds) is scrubbed; network is unshared. Child's git commits
# land in the workspace for review/merge. Host is untouched.
#
# Usage: agent-sandbox.sh <workspace-dir> <net:off|vllm> <command...>
#   AGENT_SANDBOX_CHDIR (env, optional): start dir inside the sandbox
#             (must be under the workspace; default = workspace root).
#             Used to start the agent in a repo subdir while HOME +
#             scaffolding live at the workspace root.
#   net=off   full network cut (--unshare-net)
#   net=vllm  keep network (child reaches in-VPC only, bounded by the
#             host's no-egress). TODO: add an nft/slirp allowlist so the
#             child can reach ONLY the vLLM endpoint, not other in-VPC
#             services (kubectl API, peer hosts). Until then, "vllm"
#             == "in-VPC-wide" — acceptable only where that is tolerable.

set -euo pipefail
WS="${1:?workspace dir required}"; NET="${2:?net mode required}"; shift 2
[ $# -ge 1 ] || { echo "no command given" >&2; exit 2; }
WS="$(cd "$WS" && pwd)"   # absolutise
CHDIR="${AGENT_SANDBOX_CHDIR:-$WS}"
case "$CHDIR" in "$WS"|"$WS"/*) ;; *) echo "AGENT_SANDBOX_CHDIR must be under the workspace" >&2; exit 2 ;; esac

case "$NET" in
  off)  NETFLAG=(--unshare-net) ;;
  vllm) NETFLAG=() ;;   # keep net; see TODO above about filtering
  *) echo "net must be off|vllm" >&2; exit 2 ;;
esac

# Block nested user namespaces (the main unprivileged-LPE vector) where
# bubblewrap supports it (>= 0.8.0). On older bwrap, warn and proceed:
# POC-accepted gap — fs/env/net confinement still holds; close before
# analyst rollout.
USERNS_FLAG=()
if bwrap --help 2>&1 | grep -q -- --disable-userns; then
  USERNS_FLAG=(--disable-userns)
else
  echo "agent-sandbox: WARNING: this bwrap lacks --disable-userns (need >= 0.8.0); nested-userns hardening disabled" >&2
fi

exec bwrap \
  --clearenv \
  --setenv HOME "$WS" \
  --setenv PATH /usr/local/bin:/usr/bin:/bin \
  --setenv TERM "${TERM:-dumb}" \
  --ro-bind /usr /usr \
  --ro-bind /bin /bin \
  --ro-bind /lib /lib \
  --ro-bind /lib64 /lib64 \
  --ro-bind /etc /etc \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --bind "$WS" "$WS" \
  --chdir "$CHDIR" \
  --unshare-user \
  "${USERNS_FLAG[@]}" \
  --unshare-pid \
  --unshare-ipc \
  --unshare-uts \
  --unshare-cgroup \
  "${NETFLAG[@]}" \
  --die-with-parent \
  --new-session \
  -- "$@"

# Hardening TODO before production:
#   old-bwrap hosts : where bwrap < 0.8.0 (no --disable-userns), either
#                     update bubblewrap or add a libseccomp-built filter
#                     blocking namespace-creation syscalls.
#   net=vllm filter : per-child net namespace + nft allowlist to the
#                     vLLM endpoint only.
