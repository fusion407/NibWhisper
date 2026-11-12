[CmdletBinding()]
param([switch]$Optical, [switch]$Open, [string]$AddOnsPath)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command node -ErrorAction SilentlyContinue)) { throw 'Install Node.js 24 or newer before starting Nib.' }
$companion = Join-Path $PSScriptRoot 'companion'
if (-not (Test-Path -LiteralPath (Join-Path $companion 'node_modules\eve'))) {
    throw 'Dependencies are missing. In the companion folder, run npm ci, then launch Nib again.'
}
$previousOptical = $env:NIB_OPTICAL_ADDONS
$previousOpenBrowser = $env:NIB_OPEN_BROWSER
try {
    if ($Open) { $env:NIB_OPEN_BROWSER = '1' }
    if ($Optical) {
        if (-not $AddOnsPath) {
            $settingsFile = Join-Path $companion 'data\bridge-settings.json'
            if (Test-Path -LiteralPath $settingsFile) {
                $settings = Get-Content -Raw -LiteralPath $settingsFile | ConvertFrom-Json
                $AddOnsPath = $settings.addonsRoot
            }
        }
        if (-not $AddOnsPath) { $AddOnsPath = 'A:\World of Warcraft\_forever_\Interface\AddOns' }
        $env:NIB_OPTICAL_ADDONS = [IO.Path]::GetFullPath($AddOnsPath)
        Write-Output 'Optional visual bridge enabled. Only the game color-code is decoded locally; screen images are not stored or uploaded.'
    } else { $env:NIB_OPTICAL_ADDONS = '' }
    Write-Output 'Nib companion: http://127.0.0.1:17861. Keep this terminal open. Ctrl+C stops the companion.'
    Push-Location -LiteralPath $companion
    try { & node --env-file-if-exists=.env server.mjs; if ($LASTEXITCODE) { throw "Nib exited with code $LASTEXITCODE" } }
    finally { Pop-Location }
} finally { $env:NIB_OPTICAL_ADDONS = $previousOptical; $env:NIB_OPEN_BROWSER = $previousOpenBrowser }
