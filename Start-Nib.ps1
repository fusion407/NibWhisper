[CmdletBinding()]
param([switch]$Optical, [switch]$Open, [string]$AddOnsPath)
$ErrorActionPreference = 'Stop'

# Starts Nib's helper. With -Optical (what Start-Nib-Auto.cmd passes) it also does first-time setup:
# it finds the AddOns folder you dropped Nib into, creates the reply files there, and remembers the folder.

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    throw 'Nib needs Node.js 24 or newer. Install it from https://nodejs.org, then start Nib again.'
}
$companion = Join-Path $PSScriptRoot 'companion'
$settingsFile = Join-Path $companion 'data\bridge-settings.json'

function Test-NibAddOns([string]$Path) {
    return [bool]$Path -and (Test-Path -LiteralPath (Join-Path $Path 'NibWhisper\NibWhisper.toc') -PathType Leaf)
}

# Looks in the usual places for an AddOns folder that already contains Nib.
function Find-NibAddOns {
    $roots = @()
    foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft', 'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft') {
        try { $install = (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallPath; if ($install) { $roots += (Split-Path $install.TrimEnd('\') -Parent); $roots += $install.TrimEnd('\') } } catch {}
    }
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        foreach ($folder in 'World of Warcraft', 'Program Files (x86)\World of Warcraft', 'Program Files\World of Warcraft', 'Games\World of Warcraft') {
            $roots += (Join-Path $drive.Root $folder)
        }
    }
    $found = @()
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        foreach ($flavor in (Get-ChildItem -LiteralPath $root -Directory -Filter '_*_' -ErrorAction SilentlyContinue)) {
            $candidate = Join-Path $flavor.FullName 'Interface\AddOns'
            if (Test-NibAddOns $candidate) { $found += $candidate }
        }
    }
    # Prefer the Forever client when Nib is installed in more than one.
    return ($found | Sort-Object { $_ -notmatch '\\_forever_\\' } | Select-Object -First 1)
}

# The game only sees files that exist when it starts, so the whole pool of reply files is created up front.
function Initialize-NibReplyFiles([string]$AddOns) {
    $fontDir = Join-Path $AddOns 'NibWhisper_Assistant\Fonts'
    if (-not (Test-Path -LiteralPath $fontDir -PathType Container)) { return 0 }
    $placeholder = [Text.Encoding]::ASCII.GetBytes("NIB PLACEHOLDER`n")
    $created = 0
    foreach ($i in 1..8000) {
        $file = Join-Path $fontDir ('R{0:D4}.ttf' -f $i)
        if (-not (Test-Path -LiteralPath $file)) { [IO.File]::WriteAllBytes($file, $placeholder); $created++ }
    }
    return $created
}

$previousOptical = $env:NIB_OPTICAL_ADDONS
$previousOpenBrowser = $env:NIB_OPEN_BROWSER
try {
    if ($Open) { $env:NIB_OPEN_BROWSER = '1' }
    if ($Optical) {
        if (-not $AddOnsPath -and (Test-Path -LiteralPath $settingsFile)) {
            $saved = (Get-Content -Raw -LiteralPath $settingsFile | ConvertFrom-Json).addonsRoot
            if (Test-NibAddOns $saved) { $AddOnsPath = $saved }
        }
        if (-not $AddOnsPath) { $AddOnsPath = Find-NibAddOns }
        while (-not (Test-NibAddOns $AddOnsPath)) {
            Write-Output ''
            Write-Output "I couldn't find Nib in your AddOns folder."
            Write-Output 'Drag the NibWhisper folders into World of Warcraft\_forever_\Interface\AddOns first.'
            $AddOnsPath = (Read-Host 'Then paste the full path of that AddOns folder here').Trim().Trim('"')
        }
        $AddOnsPath = [IO.Path]::GetFullPath($AddOnsPath).TrimEnd('\')
        $created = Initialize-NibReplyFiles $AddOnsPath
        New-Item -ItemType Directory -Path (Split-Path $settingsFile -Parent) -Force | Out-Null
        @{ addonsRoot = $AddOnsPath; opticalInstalled = $true } | ConvertTo-Json | Set-Content -LiteralPath $settingsFile -Encoding UTF8
        Write-Output "Nib found in $AddOnsPath"
        if ($created) {
            Write-Output "Created $created reply files. If World of Warcraft is open, fully exit and reopen it once so it sees them."
        }
        $env:NIB_OPTICAL_ADDONS = $AddOnsPath
    } else { $env:NIB_OPTICAL_ADDONS = '' }
    # Gemini needs nothing beyond Node. The optional OpenAI provider needs the packages in companion.
    if (-not (Test-Path -LiteralPath (Join-Path $companion 'node_modules\eve'))) {
        Write-Output 'Gemini is ready to use. (OpenAI, if you want it, needs "npm ci" run in the companion folder.)'
    }
    Write-Output 'Nib helper running at http://127.0.0.1:17861. Keep this window open while you play. Ctrl+C stops it.'
    Push-Location -LiteralPath $companion
    try { & node --env-file-if-exists=.env server.mjs; if ($LASTEXITCODE) { throw "Nib exited with code $LASTEXITCODE" } }
    finally { Pop-Location }
} finally { $env:NIB_OPTICAL_ADDONS = $previousOptical; $env:NIB_OPEN_BROWSER = $previousOpenBrowser }
