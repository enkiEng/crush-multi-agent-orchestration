# crush-init-sandbox.ps1 -- enable sandboxed-agent mode for the current
# git repo, against the dedicated RESGC container-host (WS2022 clients).
#
# Requires NO local Docker and NO elevation. Mirrors crush-init-sandbox.sh:
#   1. writes .crush.json (container-use MCP over the remote engine)
#   2. writes CRUSH.md (agent rules)
#   3. pins the environment base image to the ECR cu-base mirror
#   4. verifies the remote engine is reachable
#
# Usage: .\crush-init-sandbox.ps1 -Engine tcp://cu-host.resgc.internal:8080
#        [-BaseImage <ECR URI>] [-Force]

param(
    [Parameter(Mandatory = $true)][string]$Engine,
    [string]$BaseImage = "468501357939.dkr.ecr.us-gov-east-1.amazonaws.com/cu-base:latest",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$TemplateDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Fail($msg) { Write-Error "ERROR: $msg"; exit 1 }

if ($Engine -notmatch '^(tcp|unix|docker-container)://') {
    Fail "engine must be tcp:// (fleet default), got: $Engine"
}
if (-not (Get-Command container-use -ErrorAction SilentlyContinue)) {
    Fail "container-use not on PATH (install the fleet client package)"
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail "git not found" }

try { $RepoRoot = (git rev-parse --show-toplevel 2>$null).Trim() } catch { $RepoRoot = $null }
if (-not $RepoRoot) { Fail "run this inside a git repository" }
Set-Location $RepoRoot

if ((Test-Path .crush.json) -and (-not $Force)) {
    Fail ".crush.json already exists (use -Force to overwrite; a backup will be kept)"
}
if (Test-Path .crush.json) {
    Copy-Item .crush.json (".crush.json.bak-" + (Get-Date -Format "yyyyMMddHHmmss"))
}

# 1. .crush.json from the template
(Get-Content "$TemplateDir\crush.json.template" -Raw) -replace '\{\{ENGINE\}\}', $Engine |
    Set-Content -NoNewline .crush.json

# 2. CRUSH.md agent rules (append if one exists, install otherwise)
$Rules = Get-Content "$TemplateDir\CRUSH-rules.md" -Raw
if (Test-Path CRUSH.md) {
    if (-not (Select-String -Path CRUSH.md -Pattern "ONLY Environments" -Quiet)) {
        Add-Content CRUSH.md "`n$Rules"
        Write-Host "appended sandbox rules to existing CRUSH.md"
    }
} else {
    Set-Content CRUSH.md $Rules -NoNewline
}

# 3. pin the offline base image
$env:_EXPERIMENTAL_DAGGER_RUNNER_HOST = $Engine
container-use config base-image set $BaseImage | Out-Null

# 4. end-to-end probe of the remote engine
container-use list *> $null
if ($LASTEXITCODE -ne 0) {
    Fail "cannot reach the engine at $Engine -- check the security-group grant and that the container host is up"
}

Write-Host @"
sandbox mode enabled for $RepoRoot
  engine:     $Engine
  base image: $BaseImage

Start crush-vpc normally. Review agent work with:
  container-use list             # environments
  container-use log  <id>        # full command transcript
  container-use diff <id>        # the patch
  container-use merge <id>       # land it (keeps agent commits)
  container-use apply <id>       # stage it for your own commit

Commit .crush.json and CRUSH.md so teammates get the same setup.
"@
