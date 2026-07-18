#!/bin/bash
# sandbox-selftest.sh — adversarial confinement checklist for
# agent-sandbox.sh. Run on the Linux host BEFORE trusting real children.
# Every escape attempt must FAIL; the script exits nonzero otherwise.
#
# Checks: real-HOME reads, env scrubbing, writes outside the workspace,
# network in net=off, nested-userns creation, plus a bwrap version report.
#
# Usage: sandbox-selftest.sh   (no args; uses a throwaway workspace)

set -u
[ "$(uname -s)" = Linux ] || { echo "Linux only (bwrap)"; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SB="$HERE/agent-sandbox.sh"
[ -x "$SB" ] || { echo "agent-sandbox.sh not executable at $SB"; exit 2; }

REAL_HOME="$HOME"
WS="$(mktemp -d "${TMPDIR:-/tmp}/sbx-selftest.XXXXXX")"
trap 'rm -rf "$WS"' EXIT
export CANARY_SECRET="leak-me-$$"

PASS=0; FAILED=0
note()   { printf '%-52s %s\n' "$1" "$2"; }
# expect_blocked <name> <cmd...>: PASS iff the command FAILS inside the sandbox
expect_blocked() {
  local name="$1"; shift
  if out=$(timeout 15 "$SB" "$WS" "$NETMODE" "$@" 2>&1); then
    note "$name" "FAIL (succeeded; output: ${out:0:80})"; FAILED=$((FAILED+1))
  else
    note "$name" "PASS (blocked)"; PASS=$((PASS+1))
  fi
}
NETMODE=off

echo "== bwrap version =="
bwrap --version 2>/dev/null || echo "bwrap --version unsupported"
if bwrap --help 2>&1 | grep -q -- --disable-userns; then
  echo "--disable-userns: SUPPORTED (nested-userns hardening active)"
else
  echo "--disable-userns: ABSENT (bwrap < 0.8.0) — POC-accepted gap, close before rollout"
fi
echo

echo "== escape attempts (all must be blocked) =="
expect_blocked "read real ~/.ssh"          sh -c "ls '$REAL_HOME/.ssh'"
expect_blocked "read real ~/.aws"          sh -c "ls '$REAL_HOME/.aws' || cat '$REAL_HOME/.aws/credentials'"
expect_blocked "read any file in real HOME" sh -c "ls '$REAL_HOME' >/dev/null"
expect_blocked "env canary leak"           sh -c 'env | grep -q CANARY_SECRET'
expect_blocked "env AWS_* leak"            sh -c 'env | grep -q "^AWS_"'
expect_blocked "write /usr"                sh -c 'touch /usr/sbx-pwned'
expect_blocked "write real HOME"           sh -c "touch '$REAL_HOME/sbx-pwned'"
expect_blocked "write /etc"                sh -c 'touch /etc/sbx-pwned'
expect_blocked "network in net=off"        sh -c 'echo x > /dev/tcp/127.0.0.1/22'
if bwrap --help 2>&1 | grep -q -- --disable-userns; then
  expect_blocked "nested userns (unshare -U)" unshare -U true
  expect_blocked "nested userns (bwrap)"      bwrap --unshare-user --dev-bind / / true
else
  note "nested userns" "SKIPPED (no --disable-userns on this bwrap)"
fi
echo

echo "== positive controls (sandbox must still WORK) =="
if timeout 15 "$SB" "$WS" off sh -c "touch '$WS/ok' && test -f '$WS/ok'"; then
  note "write inside workspace" "PASS"; PASS=$((PASS+1))
else
  note "write inside workspace" "FAIL (sandbox broken)"; FAILED=$((FAILED+1))
fi
if [ "$(timeout 15 "$SB" "$WS" off sh -c 'echo "$HOME"')" = "$WS" ]; then
  note "HOME == workspace" "PASS"; PASS=$((PASS+1))
else
  note "HOME == workspace" "FAIL"; FAILED=$((FAILED+1))
fi
if timeout 15 "$SB" "$WS" off git --version >/dev/null 2>&1; then
  note "git usable inside" "PASS"; PASS=$((PASS+1))
else
  note "git usable inside" "FAIL"; FAILED=$((FAILED+1))
fi

echo
echo "result: $PASS passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
