[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$node = Get-Command node.exe -ErrorAction Stop
$companion = Join-Path $PSScriptRoot 'companion'
$settingsPath = Join-Path $companion 'data\bridge-settings.json'
$settings = Get-Content -Raw -LiteralPath $settingsPath | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $settings.addonsRoot -PathType Container)) { throw 'Install Nib first.' }
# Without the reply modules the helper still serves the companion page for copy and paste; it just does not watch the screen.
$optical = [bool]$settings.opticalInstalled

$statusUri = 'http://127.0.0.1:17861/api/status'
try { $running = Invoke-RestMethod -Uri $statusUri -TimeoutSec 2 } catch { $running = $null }
if ($running) {
    if ($running.bridgeVersion -eq 4 -and ([bool]$running.opticalEnabled -eq $optical)) { return }
    throw 'Close the previous Nib companion before starting Nib Helper.'
}

$env:NIB_PORT = '17861'
if ($optical) { $env:NIB_OPTICAL_ADDONS = [IO.Path]::GetFullPath($settings.addonsRoot) } else { $env:NIB_OPTICAL_ADDONS = $null }
$env:NIB_OPEN_BROWSER = '0'
Start-Process -FilePath $node.Source -ArgumentList 'server.mjs' -WorkingDirectory $companion -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $companion 'nib-helper.log') -RedirectStandardError (Join-Path $companion 'nib-helper-error.log')
