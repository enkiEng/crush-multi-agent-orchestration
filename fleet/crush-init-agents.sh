#!/usr/bin/env bash
# crush-init-agents.sh — enable sandboxed child-agent mode (option 2:
# crush-agents.py + bubblewrap) for the current git repo.
#
# Requires NO Docker, NO daemon, NO privileges. It only:
#   1. writes .crush.json (crush-agents MCP server entry)
#   2. writes/appends CRUSH.md (parent delegation rules)
#   3. checks client prerequisites (git, python3, bwrap on Linux)
#
# Usage: crush-init-agents.sh [--child-config <crush.json for children>]
#        [--verify-cmd '<test command>'] [--force]
#
# --child-config: crush config seeded into each child's sandbox HOME —
#   point children at their OWN endpoint (endpoint split keeps the
#   parent session responsive). Omit to let children inherit nothing
#   (fine only where the default provider config is ambient).
# --verify-cmd: repo test command run by agent_verify (default: pytest -q)

set -euo pipefail

CHILD_CONFIG="${CRUSH_AGENTS_CHILD_CONFIG:-}"
VERIFY_CMD="${CRUSH_AGENTS_VERIFY_CMD:-pytest -q}"
FORCE=0
FLEET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --child-config) CHILD_CONFIG="$2"; shift 2 ;;
    --verify-cmd)   VERIFY_CMD="$2"; shift 2 ;;
    --force)        FORCE=1; shift ;;
    -h|--help)      grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "ERROR: $*" >&2; exit 1; }

command -v git     >/dev/null || fail "git not found"
command -v python3 >/dev/null || fail "python3 not found"
[ -f "$FLEET_DIR/crush-agents.py" ]   || fail "crush-agents.py not next to this script"
[ -x "$FLEET_DIR/agent-sandbox.sh" ]  || fail "agent-sandbox.sh not executable next to this script"
case "$(uname -s)" in
  Linux)
    command -v bwrap >/dev/null || fail "bwrap not found (install bubblewrap) — children are sandbox-confined on Linux"
    bwrap --help 2>&1 | grep -q -- --disable-userns \
      || echo "WARNING: bwrap < 0.8.0 (no --disable-userns); nested-userns hardening will be disabled" >&2
    ;;
  Darwin)
    echo "NOTE: macOS = staging only; children run UNSANDBOXED here" >&2
    ;;
esac
if [ -n "$CHILD_CONFIG" ]; then
  [ -f "$CHILD_CONFIG" ] || fail "child config not found: $CHILD_CONFIG"
  CHILD_CONFIG="$(cd "$(dirname "$CHILD_CONFIG")" && pwd)/$(basename "$CHILD_CONFIG")"
fi

git rev-parse --show-toplevel >/dev/null 2>&1 || fail "run this inside a git repository"
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
git rev-parse HEAD >/dev/null 2>&1 || fail "repository has no commits yet (children clone from HEAD)"

# refuse to clobber existing config unless --force
if [ -e .crush.json ] && [ "$FORCE" -ne 1 ]; then
  fail ".crush.json already exists (use --force to overwrite; a backup will be kept)"
fi
[ -e .crush.json ] && cp .crush.json ".crush.json.bak-$(date +%Y%m%d%H%M%S)"

# 1. .crush.json from the template
sed -e "s|{{FLEET_DIR}}|$FLEET_DIR|" \
    -e "s|{{CHILD_CONFIG}}|$CHILD_CONFIG|" \
    -e "s|{{VERIFY_CMD}}|$VERIFY_CMD|" \
    "$FLEET_DIR/crush.json.option2.template" > .crush.json
python3 -c "import json; json.load(open('.crush.json'))" \
  || fail "generated .crush.json is not valid JSON (check --verify-cmd quoting)"

# 2. CRUSH.md parent rules (append if one exists, install otherwise)
if [ -e CRUSH.md ]; then
  if ! grep -q "crush-agents" CRUSH.md; then
    printf '\n' >> CRUSH.md
    cat "$FLEET_DIR/CRUSH-rules-option2.md" >> CRUSH.md
    echo "appended delegation rules to existing CRUSH.md"
  fi
else
  cp "$FLEET_DIR/CRUSH-rules-option2.md" CRUSH.md
fi

cat <<EOF
child-agent mode enabled for $REPO_ROOT
  server:       $FLEET_DIR/crush-agents.py
  child config: ${CHILD_CONFIG:-'(none — children inherit no provider config)'}
  verify cmd:   $VERIFY_CMD

Start crush normally. The parent model delegates via spawn_agent.
Review a child's work:
  agent_status <id>                     # in-session
  agent_verify <id>                     # REAL test run — always before merge
  git fetch ~/.crush-agents/<repo-slug>/<id>/home/ws <branch>:<branch>
  git diff HEAD...<branch>              # then merge locally if good

Commit .crush.json and CRUSH.md so teammates get the same setup.
EOF
