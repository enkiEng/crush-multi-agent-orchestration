#!/usr/bin/env bash
# crush-init-sandbox.sh — enable sandboxed-agent mode for the current
# git repo, against the dedicated RESGC container-host.
#
# Requires NO local Docker and NO privileges. It only:
#   1. writes .crush.json (container-use MCP over the remote engine)
#   2. writes CRUSH.md (agent rules)
#   3. pins the environment base image to the ECR cu-base mirror
#   4. verifies the remote engine is reachable
#
# Usage: crush-init-sandbox.sh --engine tcp://cu-host.resgc.internal:8080
#        [--base-image <ECR URI>] [--force]

set -euo pipefail

ENGINE="${CU_ENGINE:-}"
BASE_IMAGE="${CU_BASE_IMAGE:-468501357939.dkr.ecr.us-gov-east-1.amazonaws.com/cu-base:latest}"
FORCE=0
TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --engine)     ENGINE="$2"; shift 2 ;;
    --base-image) BASE_IMAGE="$2"; shift 2 ;;
    --force)      FORCE=1; shift ;;
    -h|--help)    grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

[ -n "$ENGINE" ] || fail "no engine given: pass --engine tcp://<host>:<port> or set CU_ENGINE"
case "$ENGINE" in tcp://*|unix://*|docker-container://*) ;; *) fail "engine must be tcp:// (fleet default), got: $ENGINE" ;; esac

command -v container-use >/dev/null || fail "container-use not on PATH (install the fleet client package)"
command -v git >/dev/null           || fail "git not found"
git rev-parse --show-toplevel >/dev/null 2>&1 || fail "run this inside a git repository"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# refuse to clobber existing config unless --force
if [ -e .crush.json ] && [ "$FORCE" -ne 1 ]; then
  fail ".crush.json already exists (use --force to overwrite; a backup will be kept)"
fi
[ -e .crush.json ] && cp .crush.json ".crush.json.bak-$(date +%Y%m%d%H%M%S)"

# 1. .crush.json from the template
sed "s|{{ENGINE}}|$ENGINE|" "$TEMPLATE_DIR/crush.json.template" > .crush.json

# 2. CRUSH.md agent rules (append if one exists, install otherwise)
if [ -e CRUSH.md ]; then
  if ! grep -q "ONLY Environments" CRUSH.md; then
    printf '\n' >> CRUSH.md
    cat "$TEMPLATE_DIR/CRUSH-rules.md" >> CRUSH.md
    echo "appended sandbox rules to existing CRUSH.md"
  fi
else
  cp "$TEMPLATE_DIR/CRUSH-rules.md" CRUSH.md
fi

# 3. pin the offline base image
export _EXPERIMENTAL_DAGGER_RUNNER_HOST="$ENGINE"
container-use config base-image set "$BASE_IMAGE" >/dev/null

# 4. end-to-end probe of the remote engine
if ! container-use list >/dev/null 2>&1; then
  fail "cannot reach the engine at $ENGINE — check the security-group grant and that the container host is up"
fi

cat <<EOF
sandbox mode enabled for $REPO_ROOT
  engine:     $ENGINE
  base image: $BASE_IMAGE

Start crush-vpc normally. Review agent work with:
  container-use list             # environments
  container-use log  <id>        # full command transcript
  container-use diff <id>        # the patch
  container-use merge <id>       # land it (keeps agent commits)
  container-use apply <id>       # stage it for your own commit

Commit .crush.json and CRUSH.md so teammates get the same setup.
EOF
