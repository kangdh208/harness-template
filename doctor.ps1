<#
.SYNOPSIS
  Check that the Claude Code harness is installed correctly in a project. Read-only.
  Prints one line per check: OK / WARN / FAIL. Exits 1 if any check FAILs.
.EXAMPLE
  .\doctor.ps1 -Target "C:\path\to\project"
#>
param(
  [string]$Target = (Get-Location).Path
)
$ErrorActionPreference = 'Stop'
$Template = $PSScriptRoot
$Target = (Resolve-Path $Target).Path.TrimEnd('\')

function Read-Text($path) { if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { '' } }
function Test-HarnessEntry($entry) { ($entry | ConvertTo-Json -Depth 20 -Compress) -match '\.harness/hooks/' }

$script:failed = $false
function Report($level, $item, $detail) {
  if ($level -eq 'FAIL') { $script:failed = $true }
  Write-Host ('{0,-5} {1}{2}' -f $level, $item, $(if ($detail) { " - $detail" } else { '' }))
}

$H = Join-Path $Target '.harness'
$claude = Join-Path $Target '.claude'
if (-not (Test-Path $H)) { Report 'FAIL' '.harness' 'not installed (run install.ps1)'; exit 1 }

# Version
$cur = (Read-Text (Join-Path $H 'VERSION')).Trim()
$latest = (Read-Text (Join-Path $Template 'VERSION')).Trim()
if (-not $cur) { Report 'WARN' 'version' "unknown; template is $latest (run install.ps1 to update)" }
elseif ($cur -ne $latest) { Report 'WARN' 'version' "$cur installed, template is $latest (run install.ps1 to update)" }
else { Report 'OK' 'version' $cur }

# Core files copied into .harness
foreach ($f in 'HARNESS.md', 'harness.config.json', 'hooks\post-edit.ps1', 'hooks\on-stop.ps1', 'state\progress.md', 'state\decisions.md') {
  if (Test-Path (Join-Path $H $f)) { Report 'OK' ".harness\$f" } else { Report 'FAIL' ".harness\$f" 'missing' }
}

# Agents and skills: every template entry must exist in .claude
foreach ($kind in 'agents', 'skills') {
  $missing = @(Get-ChildItem (Join-Path $Template $kind) | Where-Object { -not (Test-Path (Join-Path $claude "$kind\$($_.Name)")) } | ForEach-Object { $_.Name })
  if ($missing.Count) { Report 'FAIL' ".claude\$kind" "missing: $($missing -join ', ')" } else { Report 'OK' ".claude\$kind" }
}

# Hooks registered in settings.local.json
$settingsPath = Join-Path $claude 'settings.local.json'
$raw = Read-Text $settingsPath
if (-not $raw.Trim()) { Report 'FAIL' 'hooks' 'settings.local.json missing' }
else {
  $s = $raw | ConvertFrom-Json
  foreach ($ev in 'PostToolUse', 'Stop') {
    $has = $s.PSObject.Properties['hooks'] -and $s.hooks.PSObject.Properties[$ev] -and @($s.hooks.$ev | Where-Object { Test-HarnessEntry $_ }).Count
    if ($has) {
      $stale = ($s.hooks.$ev | ConvertTo-Json -Depth 20 -Compress) -notmatch [regex]::Escape($H.Replace('\', '/'))
      if ($stale) { Report 'WARN' "hooks.$ev" 'points at a different .harness path (project moved? re-run install.ps1)' }
      else { Report 'OK' "hooks.$ev" }
    } else { Report 'FAIL' "hooks.$ev" 'harness hook not registered' }
  }
}

# CLAUDE.local.md import block
if ((Read-Text (Join-Path $Target 'CLAUDE.local.md')) -match '<!-- >>> harness >>> -->') { Report 'OK' 'CLAUDE.local.md' }
else { Report 'FAIL' 'CLAUDE.local.md' 'harness import block missing' }

# Ignore block: the harness is personal, so it belongs in .git/info/exclude (never committed)
$inGitignore = (Read-Text (Join-Path $Target '.gitignore')) -match '# >>> harness >>>'
$inExclude = (Read-Text (Join-Path $Target '.git\info\exclude')) -match '# >>> harness >>>'
if ($inGitignore) { Report 'WARN' 'git ignore' 'harness block is in .gitignore, visible to teammates (re-run install.ps1 to move it to .git/info/exclude)' }
elseif ($inExclude) { Report 'OK' 'git ignore' '.git/info/exclude' }
elseif (Test-Path (Join-Path $Target '.git') -PathType Leaf) { Report 'OK' 'git ignore' 'worktree/submodule: not checked here, see tracked-files check' }
else { Report 'WARN' 'git ignore' 'no harness block in .gitignore or .git/info/exclude' }

# Harness files already tracked by git would reach teammates on the next push
$gitExe = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $gitExe -and (Test-Path "$env:ProgramFiles\Git\cmd\git.exe")) { $gitExe = "$env:ProgramFiles\Git\cmd\git.exe" }
if ($gitExe -and (Test-Path (Join-Path $Target '.git'))) {
  try {
    $tracked = @(& $gitExe -C $Target ls-files -- .harness CLAUDE.local.md .claude/settings.local.json '.claude/agents/harness-*' '.claude/skills/harness-*' '.claude/agents/team-*' '.claude/skills/team-*' 2>$null)
    if ($tracked.Count) { Report 'FAIL' 'tracked' "harness files are tracked by git (teammates get them): $(($tracked | Select-Object -First 5) -join ', ') - untrack with: git rm -r --cached <path>" }
    else { Report 'OK' 'tracked' 'no harness files in git' }
  } catch { Report 'WARN' 'tracked' 'could not run git ls-files' }
}

# Context docs still unfilled
$unfilled = @(Get-ChildItem (Join-Path $H 'context') -Filter *.md | Where-Object { (Read-Text $_.FullName) -match 'harness:unfilled' } | ForEach-Object { $_.Name })
if ($unfilled.Count) { Report 'WARN' 'context' "unfilled: $($unfilled -join ', ')" } else { Report 'OK' 'context' }

# Domain team: domain.md table <-> team-* files, and frontmatter name matches file
$domain = Read-Text (Join-Path $H 'context\domain.md')
$teamFiles = @{}
foreach ($a in @(Get-ChildItem (Join-Path $claude 'agents') -Filter 'team-*.md' -ErrorAction SilentlyContinue)) { $teamFiles[$a.BaseName] = $a.FullName }
foreach ($s in @(Get-ChildItem (Join-Path $claude 'skills') -Filter 'team-*' -Directory -ErrorAction SilentlyContinue)) { $teamFiles[$s.Name] = Join-Path $s.FullName 'SKILL.md' }
if (-not $domain) { Report 'WARN' 'domain' 'context\domain.md missing (run install.ps1)' }
elseif ($domain -match 'harness:unfilled') { Report 'WARN' 'domain' 'not set up yet (ask: "harness: build the domain team")' }
else {
  $declared = @([regex]::Matches($domain, '`(team-[a-z0-9-]+)`') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $missing = @($declared | Where-Object { -not $teamFiles.ContainsKey($_) })
  $undeclared = @($teamFiles.Keys | Where-Object { $declared -notcontains $_ })
  if ($missing.Count) { Report 'FAIL' 'team' "in domain.md but no file: $($missing -join ', ')" }
  if ($undeclared.Count) { Report 'WARN' 'team' "file exists but not in domain.md (never called by the loop): $($undeclared -join ', ')" }
  if (-not $missing.Count -and -not $undeclared.Count) { Report 'OK' 'team' $(if ($declared.Count) { $declared -join ', ' } else { 'no team-* members' }) }
}
foreach ($name in $teamFiles.Keys) {
  $head = Read-Text $teamFiles[$name]
  if ($head -notmatch '(?m)^description:\s*\S') { Report 'FAIL' $name 'frontmatter has no description' }
  elseif ($head -notmatch "(?m)^name:\s*$([regex]::Escape($name))\s*$") { Report 'FAIL' $name 'frontmatter name does not match file name' }
}

# Config: missing keys and empty commands
$cfg = (Read-Text (Join-Path $H 'harness.config.json')) | ConvertFrom-Json
$tcfg = (Read-Text (Join-Path $Template 'harness.config.json')) | ConvertFrom-Json
$missingKeys = @($tcfg.PSObject.Properties | Where-Object { -not $cfg.PSObject.Properties[$_.Name] } | ForEach-Object { $_.Name })
if ($missingKeys.Count) { Report 'WARN' 'config' "missing keys: $($missingKeys -join ', ') (run install.ps1)" }
$empty = @('format', 'lint', 'test' | Where-Object { -not $cfg.$_ })
if ($empty.Count) { Report 'WARN' 'config' "empty commands: $($empty -join ', ')" } else { Report 'OK' 'config' 'format, lint, test set' }
if ($cfg.verifyOnStop -and -not $cfg.test) { Report 'WARN' 'config' 'verifyOnStop is true but test is empty' }
foreach ($k in 'format', 'lint') {
  if ($cfg.$k -and -not $cfg.$k.Contains('{file}')) { Report 'WARN' 'config' "$k has no {file}: project-wide, so the edit hook skips it (it would touch or judge teammates' code)" }
}

if ($script:failed) { exit 1 }
exit 0
