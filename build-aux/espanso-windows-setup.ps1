# Fed to Windows PowerShell on stdin by `make setup-espanso-windows' (WSL).
# Points Windows espanso at the config Proton Drive syncs.  See the Makefile
# comment above that target for why each step is the way it is.  Stdin mode
# evaluates LINE BY LINE: keep every statement complete on one line.
Set-Location $env:USERPROFILE
$p = Get-ChildItem "$env:USERPROFILE\Proton Drive\*\My files\espanso" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $p) { Write-Output "    no espanso folder in Proton Drive yet -- run: make check-protondrive"; exit 1 }
$e = "$env:LOCALAPPDATA\Programs\Espanso\espansod.exe"
if (-not (Test-Path $e)) { Write-Output "    espanso is not installed on Windows -- winget install Espanso.Espanso"; exit 1 }
setx ESPANSO_CONFIG_DIR "$p" | Out-Null
$env:ESPANSO_CONFIG_DIR = $p
Write-Output "    ESPANSO_CONFIG_DIR = $p"
Start-Process -FilePath $e -ArgumentList "restart" -WindowStyle Hidden
Write-Output "    espanso restarted"
exit 0
