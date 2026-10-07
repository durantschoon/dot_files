# Fed to Windows PowerShell on stdin by `make setup-conemu-windows' (WSL).
# Stdin mode evaluates LINE BY LINE: keep every statement complete on one line.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $env:USERPROFILE
$xmlPath = "$env:APPDATA\ConEmu.xml"
if (-not (Test-Path -LiteralPath $xmlPath)) { Write-Output "    ConEmu.xml not found at $xmlPath"; exit 1 }
$raw = [System.IO.File]::ReadAllText($xmlPath, [System.Text.Encoding]::UTF8)
$expected = "%m$([char]0x25A0)m %s"
$pattern = '(<value name="TabConsole" type="string" data=")[^"]*("/>)'
if ($raw -match $pattern) { $replacement = '$1' + $expected + '$2'; $updated = [regex]::Replace($raw, $pattern, $replacement); if ($updated -ne $raw) { $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($xmlPath, $updated, $utf8NoBom); Write-Output "    TabConsole:  updated to '$expected'" } else { Write-Output "    TabConsole:  already set to '$expected'" } } else { $keyPattern = '(<key name="\.[^"]*"[^>]*>)'; if ($raw -match $keyPattern) { $entry = "`r`n`t`t`t<value name=`"TabConsole`" type=`"string`" data=`"$expected`"/>"; $updated = [regex]::Replace($raw, $keyPattern, "${1}$entry", 1); $utf8NoBom = New-Object System.Text.UTF8Encoding($false); [System.IO.File]::WriteAllText($xmlPath, $updated, $utf8NoBom); Write-Output "    TabConsole:  added '$expected'" } else { Write-Output "    could not find configuration key in $xmlPath"; exit 1 } }
if (Get-Process ConEmu64, ConEmu -ErrorAction SilentlyContinue) { Write-Output "    NOTE: ConEmu is currently running; restart it or reopen settings to reload" }
exit 0
