<#
.SYNOPSIS
  Install (or update) the Claude Code harness into a project. Safe to re-run.
.EXAMPLE
  .\install.ps1 -Target "C:\path\to\project"
  .\install.ps1 -Target . -UseExclude    # ignore via .git/info/exclude instead of .gitignore
#>
param(
  [string]$Target = (Get-Location).Path,
  [switch]$UseExclude
)
$ErrorActionPreference = 'Stop'
$Template = $PSScriptRoot
$Target = (Resolve-Path $Target).Path.TrimEnd('\')
if ($Target -eq $Template.TrimEnd('\')) { throw "Target is the template folder itself." }

$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-Text($path) { if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { '' } }
function Write-Text($path, $text) { [IO.File]::WriteAllText($path, $text, $Utf8) }

# Insert or replace a marker-delimited block in a text file
function Set-Block($path, $begin, $end, $body) {
  $text = Read-Text $path
  $block = "$begin`r`n$body`r`n$end"
  $pattern = [regex]::Escape($begin) + '[\s\S]*?' + [regex]::Escape($end)
  if ($text -match $pattern) {
    $text = [regex]::Replace($text, $pattern, $block.Replace('$', '$$'))
  } else {
    if ($text -and -not $text.EndsWith("`n")) { $text += "`r`n" }
    $text += "$block`r`n"
  }
  Write-Text $path $text
}

function Test-HarnessEntry($entry) { ($entry | ConvertTo-Json -Depth 20 -Compress) -match '\.harness/hooks/' }

$H = Join-Path $Target '.harness'
$isUpdate = Test-Path $H
$mode = if ($isUpdate) { 'update' } else { 'install' }
$oldVersion = (Read-Text (Join-Path $H 'VERSION')).Trim()
if (-not $oldVersion) { $oldVersion = if ($isUpdate) { 'unknown' } else { 'none' } }
$newVersion = (Read-Text (Join-Path $Template 'VERSION')).Trim()

# 1. Copy template -> .harness (project data is preserved on update)
$skip = @('install.ps1', 'uninstall.ps1', 'doctor.ps1', 'README.md', 'CHANGELOG.md', 'global-skill', '.git', '.gitignore')
$preserve = @('context', 'state', 'harness.config.json')
New-Item -ItemType Directory -Force $H | Out-Null
$addedFiles = @()
foreach ($item in Get-ChildItem $Template -Force | Where-Object { $skip -notcontains $_.Name }) {
  $dest = Join-Path $H $item.Name
  if ($preserve -contains $item.Name -and (Test-Path $dest)) {
    # Keep project data, but add files that newer template versions introduced (e.g. context/domain.md)
    if ($item.PSIsContainer) {
      foreach ($f in Get-ChildItem $item.FullName -Recurse -File) {
        $rel = $f.FullName.Substring($item.FullName.Length + 1)
        $to = Join-Path $dest $rel
        if (-not (Test-Path $to)) {
          New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
          Copy-Item $f.FullName $to
          $addedFiles += "$($item.Name)/$($rel.Replace('\', '/'))"
        }
      }
    }
    continue
  }
  if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
  Copy-Item $item.FullName $dest -Recurse -Force
}

# Preserved config may predate newer template keys: add missing keys, keep existing values
$cfgPath = Join-Path $H 'harness.config.json'
$cfg = (Read-Text $cfgPath) | ConvertFrom-Json
$addedKeys = @()
foreach ($p in ((Read-Text (Join-Path $Template 'harness.config.json')) | ConvertFrom-Json).PSObject.Properties) {
  if (-not $cfg.PSObject.Properties[$p.Name]) {
    $cfg | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value
    $addedKeys += $p.Name
  }
}
if ($addedKeys) { Write-Text $cfgPath ($cfg | ConvertTo-Json -Depth 20) }

# 2. Agents and skills -> .claude/ (only harness-* entries are touched)
$claude = Join-Path $Target '.claude'
foreach ($kind in 'agents', 'skills') {
  $dir = Join-Path $claude $kind
  New-Item -ItemType Directory -Force $dir | Out-Null
  Get-ChildItem $dir -Filter 'harness-*' -Force | Remove-Item -Recurse -Force
  Get-ChildItem (Join-Path $Template $kind) | ForEach-Object {
    $dest = Join-Path $dir $_.Name
    Copy-Item $_.FullName $dest -Recurse -Force
    # Let copied docs point back at the template source (used by harness-evolve)
    Get-ChildItem $dest -Recurse -File -Filter *.md | ForEach-Object {
      $text = Read-Text $_.FullName
      if ($text.Contains('{{TEMPLATE_DIR}}')) { Write-Text $_.FullName $text.Replace('{{TEMPLATE_DIR}}', $Template) }
    }
  }
}

# 3. Merge hooks into .claude/settings.local.json (other settings are kept)
$settingsPath = Join-Path $claude 'settings.local.json'
$tmplText = (Read-Text (Join-Path $Template 'settings.local.template.json')).Replace('{{HARNESS_DIR}}', $H.Replace('\', '/'))
$tmpl = $tmplText | ConvertFrom-Json
$raw = Read-Text $settingsPath
$cur = if ($raw.Trim()) { $raw | ConvertFrom-Json } else { New-Object PSObject }
if (-not $cur.PSObject.Properties['hooks']) { $cur | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject) }
foreach ($ev in $tmpl.hooks.PSObject.Properties) {
  $kept = @()
  if ($cur.hooks.PSObject.Properties[$ev.Name]) {
    $kept = @($cur.hooks.($ev.Name) | Where-Object { -not (Test-HarnessEntry $_) })
    $cur.hooks.PSObject.Properties.Remove($ev.Name)
  }
  $cur.hooks | Add-Member -NotePropertyName $ev.Name -NotePropertyValue (@($kept) + @($ev.Value))
}
Write-Text $settingsPath ($cur | ConvertTo-Json -Depth 20)

# 4. Load harness docs through CLAUDE.local.md
$imports = @(
  '@.harness/HARNESS.md',
  '@.harness/context/project.md',
  '@.harness/context/architecture.md',
  '@.harness/context/conventions.md',
  '@.harness/context/domain.md',
  '@.harness/state/progress.md'
) -join "`r`n"
Set-Block (Join-Path $Target 'CLAUDE.local.md') '<!-- >>> harness >>> -->' '<!-- <<< harness <<< -->' $imports

# 5. Keep harness files out of git
$ignoreLines = @(
  '.harness/',
  'CLAUDE.local.md',
  '.claude/settings.local.json',
  '.claude/agents/harness-*',
  '.claude/skills/harness-*',
  '.claude/agents/team-*',
  '.claude/skills/team-*'
) -join "`r`n"
$ignorePath = Join-Path $Target '.gitignore'
if ($UseExclude) {
  $gitDir = Join-Path $Target '.git'
  if (Test-Path $gitDir -PathType Container) {
    $ignorePath = Join-Path $gitDir 'info\exclude'
    New-Item -ItemType Directory -Force (Split-Path $ignorePath) | Out-Null
  } else {
    Write-Warning "No .git directory found; falling back to .gitignore"
  }
}
Set-Block $ignorePath '# >>> harness >>>' '# <<< harness <<<' $ignoreLines

$unfilled = (Get-ChildItem (Join-Path $H 'context') -Filter *.md | Where-Object { (Read-Text $_.FullName) -match 'harness:unfilled' }).Name
Write-Host "MODE: $mode"
Write-Host "VERSION: $oldVersion -> $newVersion"
Write-Host "TARGET: $Target"
Write-Host "ADDED_FILES: $($addedFiles -join ', ')"
Write-Host "CONFIG_KEYS_ADDED: $($addedKeys -join ', ')"
Write-Host "IGNORE: $ignorePath"
Write-Host "UNFILLED_CONTEXT: $($unfilled -join ', ')"
Write-Host "Done. Restart the Claude Code session (or start a new one) to load the harness."
