[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath($PSScriptRoot)
$dist = Join-Path $workspace 'dist'
$stage = Join-Path $dist 'personal'
New-Item -ItemType Directory -Force -Path $stage | Out-Null
function Copy-PackageFile([string]$Relative) {
    $source = [IO.Path]::GetFullPath((Join-Path $workspace $Relative))
    $target = [IO.Path]::GetFullPath((Join-Path $stage $Relative))
    if (-not $source.StartsWith($workspace + '\', [StringComparison]::OrdinalIgnoreCase) -or -not $target.StartsWith($stage + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Package path escaped workspace.' }
    New-Item -ItemType Directory -Force -Path (Split-Path $target -Parent) | Out-Null
    Copy-Item -LiteralPath $source -Destination $target -Force
}
foreach ($name in @('README.md','QA.md','Install-Nib.ps1','Start-Nib.ps1','Start-Nib-Helper.ps1','Start-Nib.cmd','Start-Nib-Auto.cmd','Open-Nib.cmd')) { Copy-PackageFile $name }
foreach ($folder in @('addon','companion\agent','companion\lib','companion\public')) {
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $workspace $folder) -Recurse -File)) {
        $relative = $file.FullName.Substring($workspace.Length + 1)
        if ($relative.Contains('\tests\') -or $relative.Contains('\node_modules\')) { continue }
        Copy-PackageFile $relative
    }
}
foreach ($name in @('server.mjs','package.json','package-lock.json','tsconfig.json','.env.example','README.md','BACKEND.md')) { Copy-PackageFile ('companion\' + $name) }
foreach ($name in @('guide-index.json','knowledge.json','provider-settings.json','trail-catalog.json','trail-starters.json')) { Copy-PackageFile ('companion\data\' + $name) }
foreach ($name in @('capture-optical.ps1','optical-bridge.mjs','optical-protocol.mjs','font-transport.mjs','build-quest-links.mjs')) { Copy-PackageFile ('tools\' + $name) }
Copy-PackageFile 'reports\Forever companion assistant.md'
$addonFolders = Get-ChildItem -LiteralPath (Join-Path $stage 'addon') -Directory | Select-Object -ExpandProperty FullName
Compress-Archive -LiteralPath $addonFolders -DestinationPath (Join-Path $dist 'NibWhisper-Addon.zip') -Force -CompressionLevel Optimal
$personalItems = Get-ChildItem -LiteralPath $stage -Force | Select-Object -ExpandProperty FullName
Compress-Archive -LiteralPath $personalItems -DestinationPath (Join-Path $dist 'NibWhisper-Personal.zip') -Force -CompressionLevel Optimal
Get-Item -LiteralPath (Join-Path $dist 'NibWhisper-Addon.zip'),(Join-Path $dist 'NibWhisper-Personal.zip') | Select-Object FullName,Length
