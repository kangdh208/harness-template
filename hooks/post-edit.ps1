# PostToolUse hook: run format/lint from harness.config.json on the edited file.
# Exit 2 + stderr feeds lint errors back to Claude.
# Only file-scoped commands ({file}) run here: a project-wide format would rewrite
# teammates' files, and a project-wide lint would block on their errors.
$ErrorActionPreference = 'Stop'
$harness = Split-Path $PSScriptRoot -Parent
$root = Split-Path $harness -Parent

try {
  $payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
  $config = [IO.File]::ReadAllText((Join-Path $harness 'harness.config.json')) | ConvertFrom-Json
} catch { exit 0 }

$file = $payload.tool_input.file_path
if (-not $file) { exit 0 }
# Never lint the harness's own files
if ($file.Replace('\', '/') -match '/\.harness/') { exit 0 }

function Invoke-Configured($template) {
  $cmd = $template.Replace('{file}', "`"$file`"")
  Push-Location $root
  try { $out = & cmd /c "$cmd 2>&1"; $code = $LASTEXITCODE } finally { Pop-Location }
  return @{ Code = $code; Output = ($out | Out-String) }
}

if ($config.format -and $config.format.Contains('{file}')) { Invoke-Configured $config.format | Out-Null }

if ($config.lint -and $config.lint.Contains('{file}')) {
  $r = Invoke-Configured $config.lint
  if ($r.Code -ne 0) {
    $tail = ($r.Output -split "`n" | Select-Object -Last 60) -join "`n"
    [Console]::Error.WriteLine("[harness] lint failed for ${file}:`n$tail")
    exit 2
  }
}
exit 0
