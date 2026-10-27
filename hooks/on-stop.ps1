# Stop hook: when verifyOnStop is true, run the test command before Claude finishes.
# Exit 2 + stderr makes Claude continue and fix the failures.
# Scoped to my work: skipped when the working tree has no changes, and failures in
# code I did not change (teammates') are to be reported, not fixed.
$ErrorActionPreference = 'Stop'
$harness = Split-Path $PSScriptRoot -Parent
$root = Split-Path $harness -Parent

try {
  $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
  $config = [IO.File]::ReadAllText((Join-Path $harness 'harness.config.json')) | ConvertFrom-Json
} catch { exit 0 }

# Already continuing because of this hook: don't loop forever
if ($payload.stop_hook_active) { exit 0 }
if (-not $config.verifyOnStop -or -not $config.test) { exit 0 }

# No local changes: nothing of mine to verify (harness files are git-excluded, so they don't count)
$changed = @()
$gitOk = $false
Push-Location $root
try { $changed = @(git status --porcelain 2>$null); $gitOk = ($LASTEXITCODE -eq 0) } catch { $gitOk = $false } finally { Pop-Location }
if ($gitOk -and -not $changed.Count) { exit 0 }

Push-Location $root
try { $out = & cmd /c "$($config.test) 2>&1"; $code = $LASTEXITCODE } finally { Pop-Location }

if ($code -ne 0) {
  $tail = (($out | Out-String) -split "`n" | Select-Object -Last 80) -join "`n"
  $mine = if ($gitOk) { "`nMy changed files:`n" + (($changed | Select-Object -First 30) -join "`n") } else { '' }
  [Console]::Error.WriteLine("[harness] tests failed (``$($config.test)``). Fix failures caused by my changes. If a failure is in code I did not change (a teammate's), do not fix it: report it to the user instead.$mine`n`n$tail")
  exit 2
}
exit 0
