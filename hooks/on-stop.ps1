# Stop hook: when verifyOnStop is true, run the test command before Claude finishes.
# Exit 2 + stderr makes Claude continue and fix the failures.
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

Push-Location $root
try { $out = & cmd /c "$($config.test) 2>&1"; $code = $LASTEXITCODE } finally { Pop-Location }

if ($code -ne 0) {
  $tail = (($out | Out-String) -split "`n" | Select-Object -Last 80) -join "`n"
  [Console]::Error.WriteLine("[harness] tests failed (``$($config.test)``). Fix before finishing:`n$tail")
  exit 2
}
exit 0
