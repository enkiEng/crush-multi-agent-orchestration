#!/bin/bash
# agent-sandbox.sh — run an untrusted agent command confined to one
# workspace, using bubblewrap (OS-level sandbox; NO Docker, NO daemon,
# NO privileged engine). This is the isolation core for proposal
# option 2's spawn_agent = `git worktree add` + this wrapper + detached
# `crush run`.
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

case "$NET" in
  off)  NETFLAG=(--unshare-net) ;;
  vllm) NETFLAG=() ;;   # keep net; see TODO above about filtering
  *) echo "net must be off|vllm" >&2; exit 2 ;;
esac

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
  --chdir "$WS" \
  --unshare-user \
  --unshare-pid \
  --unshare-ipc \
  --unshare-uts \
  --unshare-cgroup \
  "${NETFLAG[@]}" \
  --die-with-parent \
  --new-session \
  -- "$@"

# Hardening TODO before production:
#   --seccomp <fd>  : block namespace-creation + LPE-vector syscalls so
#                     the child can't reach userns-LPE code paths.
#   worktree mode   : for `git worktree add` children, also --ro-bind the
#                     parent repo's .git (the linked worktree's gitdir
#                     points back to it). A standalone clone needs no
#                     extra bind.
#   net=vllm filter : per-child net namespace + nft allowlist to the
#                     vLLM endpoint only.
