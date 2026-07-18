#!/usr/bin/env python3
"""crush-agents.py — stdio MCP server for sandboxed child agents (option 2).

Registered in .crush.json so the parent Crush *model* can delegate work:

    spawn_agent   per-child file:// clone + seeded sandbox HOME + detached
                  `crush run` confined by agent-sandbox.sh (bubblewrap)
    agent_status  observable state only (process, RESULT.md, log tail)
    agent_verify  actually run the tests — the mandatory external gate;
                  never trust a child's own success claim
    agent_cancel  SIGTERM the child's process group, keep ws for inspection
    agent_list    all agents with state

Stdlib only; runs on stock RHEL9 python3. No Docker, no daemon.
State lives in ~/.crush-agents/<repo-slug>/<agent-id>/ (outside the repo
so the parent session never watches it); the clone is at .../home/ws with
scaffolding (TASK.md, RESULT.md) in home/, physically outside the repo so
children cannot commit it. Merge flow is manual by design:
    git fetch ~/.crush-agents/<slug>/<id>/home/ws agent/<id>
then review RESULT.md + diff, agent_verify, merge locally.

Config (env, set in the .crush.json mcp entry):
    CRUSH_AGENTS_SANDBOX     bwrap (Linux default) | none (macOS default;
                             on Linux must be set explicitly — testing only)
    CRUSH_AGENTS_NET         vllm (default) | off  — net mode for children
    CRUSH_AGENTS_CRUSH_BIN   child crush binary (default: crush)
    CRUSH_AGENTS_VERIFY_CMD  default verification command (default: pytest -q)
    CRUSH_AGENTS_CHILD_CONFIG  path to a crush.json seeded into the child's
                             sandbox HOME (providers/model for endpoint B)
    CRUSH_AGENTS_CHILD_RULES   path to child CRUSH.md rules (default: embedded)
    CRUSH_AGENTS_STATE_DIR   default: ~/.crush-agents
"""

import hashlib
import json
import os
import shutil
import signal
import subprocess
import sys
import time
import uuid
from pathlib import Path

PROTOCOL_VERSION = "2024-11-05"
SERVER_NAME = "crush-agents"
SERVER_VERSION = "0.1.0"

HERE = Path(__file__).resolve().parent
SANDBOX_SH = HERE / "agent-sandbox.sh"
STATE_DIR = Path(os.environ.get("CRUSH_AGENTS_STATE_DIR", "~/.crush-agents")).expanduser()
CRUSH_BIN = os.environ.get("CRUSH_AGENTS_CRUSH_BIN", "crush")
DEFAULT_NET = os.environ.get("CRUSH_AGENTS_NET", "vllm")
DEFAULT_VERIFY_CMD = os.environ.get("CRUSH_AGENTS_VERIFY_CMD", "pytest -q")
CHILD_CONFIG = os.environ.get("CRUSH_AGENTS_CHILD_CONFIG", "")
CHILD_RULES_FILE = os.environ.get("CRUSH_AGENTS_CHILD_RULES", "")

DEFAULT_CHILD_RULES = """\
You are an UNATTENDED child agent working alone in this directory, which is
a disposable clone. Your parent reviews your work by branch + ../RESULT.md.

- Work ONLY inside this repository directory. The scaffolding files one
  level up (../TASK.md, ../RESULT.md, ../status.jsonl) are the ONLY
  exceptions; never touch anything else outside.
- Read ../TASK.md first; it defines objective, scope, and definition of done.
- Commit your work with git as you go; leave the tree fully committed.
  Commit ONLY task work. NEVER use `git add -f`: if git refuses a file,
  that is intentional.
- Do not install anything (pip/dnf/npm). If a needed tool is missing,
  record that in ../RESULT.md and stop.
- Before finishing, run the relevant tests yourself and paste their REAL
  output into ../RESULT.md. Never claim tests pass without running them in
  this session.
- If the same command fails twice with the same error, stop retrying and
  record the exact error in ../RESULT.md.
- Before exiting you MUST write ../RESULT.md: what was done, what was not,
  test output, open questions.
- Optionally append progress events to ../status.jsonl (one JSON object per
  line: {"ts": <unix>, "event": "..."}).
"""

CHILD_PROMPT = (
    "Read ../TASK.md (one directory above this repo) and complete the task "
    "it describes, following the rules in CRUSH.md exactly. Commit your "
    "work in this repo. Before exiting, write ../RESULT.md as ../TASK.md "
    "requires."
)


def log(msg):
    print(f"[{SERVER_NAME}] {msg}", file=sys.stderr, flush=True)


def run(cmd, cwd=None, timeout=120, env=None):
    """Run a command, return (rc, combined-output)."""
    try:
        p = subprocess.run(
            cmd, cwd=cwd, timeout=timeout, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except subprocess.TimeoutExpired:
        return 124, f"timed out after {timeout}s: {' '.join(map(str, cmd))}"
    except OSError as e:
        return 127, str(e)


def repo_root():
    rc, out = run(["git", "rev-parse", "--show-toplevel"])
    if rc != 0:
        raise RuntimeError(f"not inside a git repository: {out.strip()}")
    return Path(out.strip())


def repo_slug(root: Path):
    h = hashlib.sha1(str(root).encode()).hexdigest()[:8]
    return f"{root.name}-{h}"


def sandbox_mode():
    mode = os.environ.get("CRUSH_AGENTS_SANDBOX", "").strip()
    if mode:
        if mode not in ("bwrap", "none"):
            raise RuntimeError(f"CRUSH_AGENTS_SANDBOX must be bwrap|none, got {mode!r}")
        if mode == "none" and sys.platform.startswith("linux"):
            log("WARNING: sandbox=none on Linux — children run UNCONFINED (testing only)")
        return mode
    if sys.platform == "darwin":
        log("macOS: no bubblewrap; running children unsandboxed (staging/plumbing mode)")
        return "none"
    return "bwrap"


# Per-agent layout — scaffolding lives OUTSIDE the clone so a child
# cannot commit it (two children committing RESULT.md conflict at merge;
# hit in stage A', including via `git add -f` against instructions):
#   <adir>/meta.json, child.log      outside the sandbox bind (tamper-proof)
#   <adir>/home/                     the bwrap bind + child HOME:
#     TASK.md, RESULT.md, status.jsonl, .gitconfig, .config/crush/
#     ws/                            the file:// clone; child cwd
def agent_dir(root: Path, agent_id: str) -> Path:
    return STATE_DIR / repo_slug(root) / agent_id


def home_dir(root: Path, agent_id: str) -> Path:
    return agent_dir(root, agent_id) / "home"


def ws_dir(root: Path, agent_id: str) -> Path:
    return home_dir(root, agent_id) / "ws"


def load_meta(root: Path, agent_id: str):
    meta_path = agent_dir(root, agent_id) / "meta.json"
    if not meta_path.exists():
        raise RuntimeError(f"unknown agent id: {agent_id}")
    return json.loads(meta_path.read_text())


def save_meta(root: Path, meta):
    (agent_dir(root, meta["id"]) / "meta.json").write_text(json.dumps(meta, indent=2))


# Children spawned by THIS server process must be reaped via poll() or
# they linger as zombies (and os.kill(pid, 0) would report them alive
# forever). Children from a previous server instance are orphans reparented
# to init, so the plain kill-probe is correct for them.
CHILDREN = {}  # pid -> subprocess.Popen


def alive(pid: int) -> bool:
    proc = CHILDREN.get(pid)
    if proc is not None:
        return proc.poll() is None
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def tail(path: Path, max_chars=2000):
    if not path.exists():
        return None
    data = path.read_text(errors="replace")
    return data[-max_chars:] if len(data) > max_chars else data


# ---------------------------------------------------------------- tools

def tool_spawn_agent(args):
    task = (args.get("task") or "").strip()
    if not task:
        raise RuntimeError("task is required")
    root = repo_root()
    rc, out = run(["git", "rev-parse", "HEAD"], cwd=root)
    if rc != 0:
        raise RuntimeError("repository has no commits; children clone from HEAD")
    base_commit = out.strip()

    mode = sandbox_mode()
    if mode == "bwrap":
        if not SANDBOX_SH.exists():
            raise RuntimeError(f"sandbox wrapper missing: {SANDBOX_SH}")
        if not shutil.which("bwrap"):
            raise RuntimeError("bwrap not found on PATH (install bubblewrap)")

    agent_id = "a-" + uuid.uuid4().hex[:8]
    branch = (args.get("branch") or f"agent/{agent_id}").strip()
    adir = agent_dir(root, agent_id)
    home = home_dir(root, agent_id)
    ws = ws_dir(root, agent_id)
    home.mkdir(parents=True, exist_ok=False)

    rc, out = run(["git", "clone", "--quiet", f"file://{root}", str(ws)], timeout=300)
    if rc != 0:
        raise RuntimeError(f"clone failed: {out}")
    rc, out = run(["git", "switch", "-c", branch], cwd=ws)
    if rc != 0:
        raise RuntimeError(f"branch creation failed: {out}")

    # Defensive excludes for crush's own droppings inside the clone.
    exclude = ws / ".git" / "info" / "exclude"
    exclude.parent.mkdir(parents=True, exist_ok=True)
    with open(exclude, "a") as f:
        f.write("\n.crush/\nCRUSH.md\n")

    # sandbox HOME seeding (home/ IS the child's HOME under agent-sandbox.sh)
    (home / ".gitconfig").write_text(
        "[user]\n"
        f"\tname = crush-agent {agent_id}\n"
        f"\temail = {agent_id}@crush-agents.local\n"
        "[commit]\n\tgpgsign = false\n"
        "[advice]\n\tdetachedHead = false\n"
    )
    if CHILD_CONFIG:
        src = Path(CHILD_CONFIG).expanduser()
        if not src.exists():
            raise RuntimeError(f"CRUSH_AGENTS_CHILD_CONFIG not found: {src}")
        dst = home / ".config" / "crush"
        dst.mkdir(parents=True, exist_ok=True)
        shutil.copy(src, dst / "crush.json")
    rules = DEFAULT_CHILD_RULES
    if CHILD_RULES_FILE:
        rules = Path(CHILD_RULES_FILE).expanduser().read_text()
    (ws / "CRUSH.md").write_text(rules)
    # If the repo TRACKS a CRUSH.md (parent delegation rules), info/exclude
    # won't stop the child committing our overwrite back over it —
    # skip-worktree does. No-op when CRUSH.md is untracked.
    run(["git", "update-index", "--skip-worktree", "CRUSH.md"], cwd=ws)

    spec = [f"# TASK for agent {agent_id}", "", "## Objective", task]
    if args.get("files_in_scope"):
        fis = args["files_in_scope"]
        fis = fis if isinstance(fis, str) else "\n".join(f"- {f}" for f in fis)
        spec += ["", "## Files in scope (do not modify others)", fis]
    if args.get("definition_of_done"):
        spec += ["", "## Definition of done", args["definition_of_done"]]
    spec += [
        "",
        "## Required protocol",
        "- Commit all work on this branch; leave the tree committed.",
        "- Run the relevant tests and paste their REAL output into ../RESULT.md.",
        "- If a command fails twice with the same error, stop and record it.",
        "- Write ../RESULT.md before exiting: done / not done / test output / "
        "open questions.",
        "",
    ]
    (home / "TASK.md").write_text("\n".join(spec))

    net = args.get("net") or DEFAULT_NET
    if net not in ("vllm", "off"):
        raise RuntimeError("net must be vllm|off")
    # No --yolo: `crush run` has no such flag (v0.84.1) and headless runs
    # auto-approve all tools anyway (verified 2026-07-12, the headless-yolo
    # finding) — confinement is the sandbox, not permissions.
    child_cmd = [CRUSH_BIN, "run", "--quiet", CHILD_PROMPT]
    env = dict(os.environ)
    if mode == "bwrap":
        # bind home/ (scaffolding + clone), start the agent inside the clone
        cmd = [str(SANDBOX_SH), str(home), net] + child_cmd
        env["AGENT_SANDBOX_CHDIR"] = str(ws)
    else:
        cmd = child_cmd

    child_log = adir / "child.log"
    with open(child_log, "wb") as lf:
        proc = subprocess.Popen(
            cmd, cwd=str(ws), stdin=subprocess.DEVNULL,
            stdout=lf, stderr=subprocess.STDOUT,
            start_new_session=True, env=env,
        )
    CHILDREN[proc.pid] = proc

    meta = {
        "id": agent_id, "branch": branch, "pid": proc.pid,
        "created": time.time(), "net": net, "sandbox": mode,
        "base_commit": base_commit, "repo_root": str(root),
        "task_digest": task[:200], "cancelled": False,
        "verify_cmd": (args.get("verify_cmd") or "").strip(),
    }
    save_meta(root, meta)
    log(f"spawned {agent_id} pid={proc.pid} sandbox={mode} net={net} branch={branch}")
    return (
        f"Spawned agent {agent_id} (pid {proc.pid}, sandbox={mode}, net={net}) "
        f"on branch {branch} from {base_commit[:10]}.\n"
        f"Workspace: {ws}\n"
        f"Poll with agent_status; gate with agent_verify before believing any "
        f"result. Review/merge manually:\n"
        f"  git fetch {ws} {branch}:{branch} && git diff HEAD...{branch}"
    )


def tool_agent_status(args):
    agent_id = args.get("agent_id") or ""
    root = repo_root()
    meta = load_meta(root, agent_id)
    adir = agent_dir(root, agent_id)
    home = home_dir(root, agent_id)
    ws = ws_dir(root, agent_id)
    running = alive(meta["pid"]) and not meta.get("cancelled")

    parts = [
        f"agent {agent_id}: {'RUNNING' if running else 'EXITED'}"
        + (" (cancelled)" if meta.get("cancelled") else ""),
        f"branch {meta['branch']}, spawned {int(time.time() - meta['created'])}s ago, "
        f"sandbox={meta['sandbox']} net={meta['net']}",
    ]
    rc, out = run(["git", "log", "--oneline", f"{meta['base_commit']}..HEAD"], cwd=ws)
    commits = out.strip().splitlines() if rc == 0 and out.strip() else []
    parts.append(f"commits beyond base: {len(commits)}"
                 + (f"\n  " + "\n  ".join(commits[:10]) if commits else ""))

    status_tail = tail(home / "status.jsonl", 800)
    if status_tail:
        parts.append("status.jsonl (tail):\n" + status_tail)
    result = tail(home / "RESULT.md", 3000)
    if result:
        parts.append("RESULT.md present (UNVERIFIED — run agent_verify):\n" + result)
    else:
        parts.append("RESULT.md: not written yet")
    log_tail = tail(adir / "child.log", 1500)
    if log_tail:
        parts.append("child.log (tail):\n" + log_tail)
    return "\n\n".join(parts)


def tool_agent_verify(args):
    agent_id = args.get("agent_id") or ""
    root = repo_root()
    meta = load_meta(root, agent_id)
    # precedence: explicit cmd > the agent's own verify_cmd > repo default.
    # A repo-wide default that runs the FULL suite correctly fails a child
    # whose branch lacks its siblings' work (stage B' finding) — per-agent
    # scoping is usually what you want at review time.
    cmd_str = (args.get("cmd") or meta.get("verify_cmd") or DEFAULT_VERIFY_CMD).strip()
    home = home_dir(root, agent_id)
    ws = ws_dir(root, agent_id)
    note = ""
    if alive(meta["pid"]) and not meta.get("cancelled"):
        note = "NOTE: child still RUNNING — results may be mid-flight.\n"

    if meta["sandbox"] == "bwrap":
        cmd = [str(SANDBOX_SH), str(home), "off", "sh", "-c", cmd_str]
        env = dict(os.environ, AGENT_SANDBOX_CHDIR=str(ws))
    else:
        cmd = ["sh", "-c", cmd_str]
        env = dict(os.environ)
    rc, out = run(cmd, cwd=str(ws), timeout=600, env=env)
    verdict = "PASS" if rc == 0 else f"FAIL (exit {rc})"
    out = out[-4000:] if len(out) > 4000 else out
    return f"{note}verification `{cmd_str}` in {ws}: {verdict}\n\n{out}"


def tool_agent_cancel(args):
    agent_id = args.get("agent_id") or ""
    root = repo_root()
    meta = load_meta(root, agent_id)
    if meta.get("cancelled"):
        return f"agent {agent_id} already cancelled"
    try:
        os.killpg(meta["pid"], signal.SIGTERM)
        outcome = "SIGTERM sent to process group"
    except ProcessLookupError:
        outcome = "process already gone"
    meta["cancelled"] = True
    save_meta(root, meta)
    return (f"agent {agent_id}: {outcome}. Workspace kept for inspection: "
            f"{ws_dir(root, agent_id)}")


def tool_agent_list(args):
    root = repo_root()
    base = STATE_DIR / repo_slug(root)
    if not base.exists():
        return "no agents yet for this repository"
    lines = []
    for d in sorted(base.iterdir()):
        mp = d / "meta.json"
        if not mp.exists():
            continue
        m = json.loads(mp.read_text())
        state = ("cancelled" if m.get("cancelled")
                 else "running" if alive(m["pid"]) else "exited")
        has_result = (d / "home" / "RESULT.md").exists()
        lines.append(
            f"{m['id']}  {state:9}  branch={m['branch']}  "
            f"age={int(time.time() - m['created'])}s  "
            f"RESULT.md={'yes' if has_result else 'no'}"
        )
    return "\n".join(lines) if lines else "no agents yet for this repository"


TOOLS = {
    "spawn_agent": {
        "fn": tool_spawn_agent,
        "description": (
            "Spawn an unattended child agent in an isolated sandboxed clone of "
            "this repository (own branch; cannot touch the host or this repo). "
            "The child works headlessly and writes RESULT.md. Use for tasks that "
            "can run without clarifying questions; write the task as a full spec."
        ),
        "schema": {
            "type": "object",
            "properties": {
                "task": {"type": "string", "description":
                         "Complete task spec: objective, constraints, expected output."},
                "files_in_scope": {"type": "array", "items": {"type": "string"},
                                   "description": "Files the child may modify."},
                "definition_of_done": {"type": "string"},
                "branch": {"type": "string", "description":
                           "Branch name (default agent/<id>)."},
                "net": {"type": "string", "enum": ["vllm", "off"]},
                "verify_cmd": {"type": "string", "description":
                               "Verification command scoped to THIS child's "
                               "deliverable (e.g. its own test file); used as "
                               "agent_verify's default for this agent."},
            },
            "required": ["task"],
        },
    },
    "agent_status": {
        "fn": tool_agent_status,
        "description": ("Observable state of a child agent: process, commits, "
                        "RESULT.md, log tail. Reports facts only — a RESULT.md "
                        "claim is NOT verification; use agent_verify."),
        "schema": {"type": "object",
                   "properties": {"agent_id": {"type": "string"}},
                   "required": ["agent_id"]},
    },
    "agent_verify": {
        "fn": tool_agent_verify,
        "description": ("Run the verification/test command inside the child's "
                        "workspace (network off) and return the REAL exit code "
                        "and output. Mandatory before trusting or merging any "
                        "child result."),
        "schema": {"type": "object",
                   "properties": {"agent_id": {"type": "string"},
                                  "cmd": {"type": "string", "description":
                                          "Override the default verify command."}},
                   "required": ["agent_id"]},
    },
    "agent_cancel": {
        "fn": tool_agent_cancel,
        "description": "Stop a child agent (SIGTERM to its process group); its workspace is kept for inspection.",
        "schema": {"type": "object",
                   "properties": {"agent_id": {"type": "string"}},
                   "required": ["agent_id"]},
    },
    "agent_list": {
        "fn": tool_agent_list,
        "description": "List all child agents for this repository with their states.",
        "schema": {"type": "object", "properties": {}},
    },
}


# ------------------------------------------------------- MCP plumbing

def reply(msg_id, result=None, error=None):
    msg = {"jsonrpc": "2.0", "id": msg_id}
    if error is not None:
        msg["error"] = error
    else:
        msg["result"] = result
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def handle(msg):
    method = msg.get("method")
    msg_id = msg.get("id")
    params = msg.get("params") or {}

    if method == "initialize":
        reply(msg_id, {
            "protocolVersion": params.get("protocolVersion", PROTOCOL_VERSION),
            "capabilities": {"tools": {}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION},
        })
    elif method == "notifications/initialized":
        pass
    elif method == "ping":
        reply(msg_id, {})
    elif method == "tools/list":
        reply(msg_id, {"tools": [
            {"name": name, "description": t["description"],
             "inputSchema": t["schema"]}
            for name, t in TOOLS.items()
        ]})
    elif method == "tools/call":
        name = params.get("name")
        tool = TOOLS.get(name)
        if tool is None:
            reply(msg_id, error={"code": -32602, "message": f"unknown tool: {name}"})
            return
        try:
            text = tool["fn"](params.get("arguments") or {})
            reply(msg_id, {"content": [{"type": "text", "text": text}],
                           "isError": False})
        except Exception as e:  # tool errors go back in-band per MCP
            log(f"tool {name} error: {e}")
            reply(msg_id, {"content": [{"type": "text", "text": f"ERROR: {e}"}],
                           "isError": True})
    elif msg_id is not None:
        reply(msg_id, error={"code": -32601, "message": f"method not found: {method}"})


def main():
    log(f"starting (state dir {STATE_DIR})")
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError as e:
            log(f"bad JSON on stdin: {e}")
            continue
        try:
            handle(msg)
        except Exception as e:
            log(f"handler crash: {e}")
            if msg.get("id") is not None:
                reply(msg["id"], error={"code": -32603, "message": str(e)})


if __name__ == "__main__":
    main()
