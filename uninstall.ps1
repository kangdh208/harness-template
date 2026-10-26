<#
.SYNOPSIS
  Remove the Claude Code harness from a project.
.EXAMPLE
  .\uninstall.ps1 -Target "C:\path\to\project"
  .\uninstall.ps1 -Target . -KeepData   # keep .harness/ (context, state), team-* agents/skills, and the ignore entry
#>
param(
  [string]$Target = (Get-Location).Path,
  [switch]$KeepData
)
$ErrorActionPreference = 'Stop'
$Target = (Resolve-Path $Target).Path.TrimEnd('\')

$Utf8 = New-Object System.Text.UTF8Encoding($false)
function Read-Text($path) { if (Test-Path $path) { [IO.File]::ReadAllText($path) } else { '' } }
function Write-Text($path, $text) { [IO.File]::WriteAllText($path, $text, $Utf8) }

# Remove a marker-delimited block; delete the file if nothing else is left
function Remove-Block($path, $begin, $end) {
  if (-not (Test-Path $path)) { return }
  $pattern = [regex]::Escape($begin) + '[\s\S]*?' + [regex]::Escape($end) + '\r?\n?'
  $text = [regex]::Replace((Read-Text $path), $pattern, '')
  if ($text.Trim()) { Write-Text $path $text } else { Remove-Item $path -Force }
}

function Test-HarnessEntry($entry) { ($entry | ConvertTo-Json -Depth 20 -Compress) -match '\.harness/hooks/' }

$claude = Join-Path $Target '.claude'

# 1. Agents and skills
foreach ($kind in 'agents', 'skills') {
  $dir = Join-Path $claude $kind
  if (Test-Path $dir) {
    Get-ChildItem $dir -Filter 'harness-*' -Force | Remove-Item -Recurse -Force
    # Generated domain team is project data: kept with -KeepData
    if (-not $KeepData) { Get-ChildItem $dir -Filter 'team-*' -Force | Remove-Item -Recurse -Force }
    # Drop the folder only if the harness was its sole occupant
    if (-not (Get-ChildItem $dir -Force)) { Remove-Item $dir -Force }
  }
}

# 2. Hook entries in settings.local.json
$settingsPath = Join-Path $claude 'settings.local.json'
$raw = Read-Text $settingsPath
if ($raw.Trim()) {
  $cur = $raw | ConvertFrom-Json
  if ($cur.PSObject.Properties['hooks']) {
    foreach ($ev in @($cur.hooks.PSObject.Properties)) {
      $kept = @($ev.Value | Where-Object { -not (Test-HarnessEntry $_) })
      $cur.hooks.PSObject.Properties.Remove($ev.Name)
      if ($kept.Count) { $cur.hooks | Add-Member -NotePropertyName $ev.Name -NotePropertyValue $kept }
    }
    if (-not @($cur.hooks.PSObject.Properties).Count) { $cur.PSObject.Properties.Remove('hooks') }
  }
  if (@($cur.PSObject.Properties).Count) { Write-Text $settingsPath ($cur | ConvertTo-Json -Depth 20) }
  else { Remove-Item $settingsPath -Force }
}
if ((Test-Path $claude) -and -not (Get-ChildItem $claude -Force)) { Remove-Item $claude -Force }

# 3. CLAUDE.local.md imports
Remove-Block (Join-Path $Target 'CLAUDE.local.md') '<!-- >>> harness >>> -->' '<!-- <<< harness <<< -->'

# 4. .harness folder and ignore entries
if (-not $KeepData) {
  $H = Join-Path $Target '.harness'
  if (Test-Path $H) { Remove-Item $H -Recurse -Force }
  Remove-Block (Join-Path $Target '.gitignore') '# >>> harness >>>' '# <<< harness <<<'
  Remove-Block (Join-Path $Target '.git\info\exclude') '# >>> harness >>>' '# <<< harness <<<'
}

Write-Host "Harness removed from $Target$(if ($KeepData) { ' (.harness data kept)' })"
