[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
# Builds dist\NibWhisper-<version>-Full.zip: the three addons, the helper and the start scripts, ready to share.
# See tools\package-full.mjs for what is left out. For the CurseForge upload use: npm run package:curseforge
& node (Join-Path $PSScriptRoot 'tools\package-full.mjs')
if ($LASTEXITCODE) { throw "Packaging failed with code $LASTEXITCODE" }
