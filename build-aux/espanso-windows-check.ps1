# Fed to Windows PowerShell on stdin by `make check-espanso-windows' (WSL).
# Read-only.  Stdin mode evaluates LINE BY LINE, so every statement must be
# complete on its own line: an `else' may not start a line.
Set-Location $env:USERPROFILE
$rc = 0
$v = [Environment]::GetEnvironmentVariable("ESPANSO_CONFIG_DIR", "User")
if (-not $v) { Write-Output "    ESPANSO_CONFIG_DIR: NOT set (run: make setup-espanso-windows)"; exit 1 }
Write-Output "    config dir:  $v"
if ($v -notlike "*Proton Drive*") { Write-Output "    WARNING: that is not inside Proton Drive"; $rc = 1 }
if (Test-Path "$v\match\base.yml") { Write-Output "    base.yml:    present" } else { Write-Output "    base.yml:    MISSING (Proton Drive still syncing?)"; $rc = 1 }
if (Test-Path "$env:APPDATA\espanso") { Write-Output "    NOTE: a stale private config remains at $env:APPDATA\espanso (unused)" }
if (Get-Process espansod -ErrorAction SilentlyContinue) { Write-Output "    daemon:      running" } else { Write-Output "    daemon:      NOT running"; $rc = 1 }
exit $rc
