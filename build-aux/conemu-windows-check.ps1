# Fed to Windows PowerShell on stdin by `make check-conemu-windows' (WSL).
# Read-only.  Stdin mode evaluates LINE BY LINE, so every statement must be
# complete on its own line: an `else' may not start a line.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $env:USERPROFILE
$rc = 0
$xmlPath = "$env:APPDATA\ConEmu.xml"
if (-not (Test-Path -LiteralPath $xmlPath)) { Write-Output "    ConEmu.xml:  NOT found at $xmlPath"; exit 1 }
Write-Output "    config file: $xmlPath"
$raw = [System.IO.File]::ReadAllText($xmlPath, [System.Text.Encoding]::UTF8)
$match = [regex]::Match($raw, '<value name="TabConsole" type="string" data="([^"]*)"/>')
$expected = "%m$([char]0x25A0)m %s"
if (-not $match.Success) { Write-Output "    TabConsole:  MISSING from ConEmu.xml (run: make setup-conemu-windows)"; exit 1 }
$val = $match.Groups[1].Value
if ($val -eq $expected) { Write-Output "    TabConsole:  $val (in sync)" } else { Write-Output "    TabConsole:  $val (expected '$expected' -- run: make setup-conemu-windows)"; $rc = 1 }
if (Get-Process ConEmu64, ConEmu -ErrorAction SilentlyContinue) { Write-Output "    process:     running" } else { Write-Output "    process:     not running" }
exit $rc
