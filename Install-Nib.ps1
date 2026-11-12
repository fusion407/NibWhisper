[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$AddOnsPath = 'A:\World of Warcraft\_forever_\Interface\AddOns',
    [switch]$Optical,
    # Uninstalls the 200 reply-slot addons so they leave the AddOns list. AI chat then uses copy and paste.
    [switch]$RemoveSlots,
    [switch]$Background
)
$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'addon'))
$targetRoot = [IO.Path]::GetFullPath($AddOnsPath).TrimEnd('\')
if ((Split-Path $targetRoot -Leaf) -ne 'AddOns' -or (Split-Path (Split-Path $targetRoot -Parent) -Leaf) -ne 'Interface') {
    throw 'Choose the explicit Forever Interface\AddOns directory.'
}
if (-not (Test-Path -LiteralPath $targetRoot -PathType Container)) { throw 'The selected AddOns directory does not exist.' }
if ((Get-Item -LiteralPath $targetRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Choose an ordinary AddOns directory, not a junction or symlink.' }
$clientRunning = [bool](Get-Process -Name 'Wow','WowClassic','WowB','WowT' -ErrorAction SilentlyContinue)
$names = @('NibWhisper', 'NibWhisper_Guide', 'NibWhisper_Assistant')
$slotNames = 1..200 | ForEach-Object { 'NibWhisperReply{0:D3}' -f $_ }
if ($Optical -and $RemoveSlots) { throw 'Choose either -Optical or -RemoveSlots.' }
if ($Optical) { $names += $slotNames }
foreach ($name in $names) {
    $source = Join-Path $sourceRoot $name
    $target = [IO.Path]::GetFullPath((Join-Path $targetRoot $name))
    if (-not $target.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Install target escaped the selected AddOns directory.' }
    if (Test-Path -LiteralPath $target) {
        if ((Get-Item -LiteralPath $target).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'An addon destination is a junction or symlink.' }
        $toc = Join-Path $target ($name + '.toc')
        if (-not (Test-Path -LiteralPath $toc) -or -not ((Get-Content -Raw -LiteralPath $toc) -match 'Nib')) { throw "An unrelated existing folder occupies $target" }
    }
    if ($PSCmdlet.ShouldProcess($target, 'Install Nib addon files')) {
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        foreach ($file in (Get-ChildItem -LiteralPath $source -Recurse -File)) {
            $relative = $file.FullName.Substring($source.Length).TrimStart('\')
            if ($relative.StartsWith('tests\', [StringComparison]::OrdinalIgnoreCase)) { continue }
            $destination = [IO.Path]::GetFullPath((Join-Path $target $relative))
            if (-not $destination.StartsWith($target + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'File escaped the addon destination.' }
            $parent = Split-Path $destination -Parent
            if (Test-Path -LiteralPath $parent) {
                if ((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'An addon subdirectory is a junction or symlink.' }
            } else { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        }
    }
}
# Files that moved into the Leveling Guide and AI Assistant addons. Remove the copies an older install left in the core folder.
$coreTarget = Join-Path $targetRoot 'NibWhisper'
foreach ($stale in @('Trail.lua', 'TrailData.lua', 'QuestLinks.lua', 'TrailSync.lua', 'CharacterData.lua', 'Optical.lua', 'ThirdParty\QuestieDB-LICENSE.md')) {
    $path = Join-Path $coreTarget $stale
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and $PSCmdlet.ShouldProcess($path, 'Remove a file that moved to a Nib sub-addon')) { Remove-Item -LiteralPath $path -Force }
}
$assistantTarget = Join-Path $targetRoot 'NibWhisper_Assistant'
foreach ($retired in @('AddonListFold.lua', 'FontProbe.lua', 'Fonts\Map.lua')) {
    $path = Join-Path $assistantTarget $retired
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and $PSCmdlet.ShouldProcess($path, 'Remove a retired Nib file')) { Remove-Item -LiteralPath $path -Force }
}
# Reply files. The helper writes each AI reply into one of these fonts and the game reads it back as character widths,
# so no reply-slot addons are needed. The game only sees files that exist when it starts, which is why the whole pool
# is created now. Existing files are left alone: the helper or a running game may be using them.
$fontDir = Join-Path $assistantTarget 'Fonts'
$poolSize = 8000
if ((Test-Path -LiteralPath $fontDir -PathType Container) -and -not ((Get-Item -LiteralPath $fontDir).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
    Get-ChildItem -LiteralPath $fontDir -File | Where-Object { $_.Name -match '^[A-Z]\d?\.ttf$' } | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove a trial font')) { Remove-Item -LiteralPath $_.FullName -Force }
    }
    if ($PSCmdlet.ShouldProcess($fontDir, "Create missing reply files (pool of $poolSize)")) {
        $placeholder = [Text.Encoding]::ASCII.GetBytes("NIB PLACEHOLDER`n")
        $created = 0
        foreach ($i in 1..$poolSize) {
            $file = Join-Path $fontDir ('R{0:D4}.ttf' -f $i)
            if (-not (Test-Path -LiteralPath $file)) { [IO.File]::WriteAllBytes($file, $placeholder); $created++ }
        }
        if ($created) { Write-Output "Created $created reply files." }
    }
}
$staleFolder = Join-Path $coreTarget 'ThirdParty'
if ((Test-Path -LiteralPath $staleFolder -PathType Container) -and -not (Get-ChildItem -LiteralPath $staleFolder -Force) -and $PSCmdlet.ShouldProcess($staleFolder, 'Remove an empty folder')) { Remove-Item -LiteralPath $staleFolder -Force }
# Reply slots that are already installed get their updated manifest, so the AddOns list can group them under Nib Whisper.
# Their data files are left alone.
if ($RemoveSlots) {
    $removed = 0
    foreach ($name in $slotNames) {
        $folder = [IO.Path]::GetFullPath((Join-Path $targetRoot $name))
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) { continue }
        if (-not $folder.StartsWith($targetRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Reply slot path escaped the selected AddOns directory.' }
        if ((Get-Item -LiteralPath $folder).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reply slot $name is a junction or symlink." }
        $toc = Join-Path $folder ($name + '.toc')
        # Only folders that are recognisably Nib's own reply slots are deleted, and only their two known files.
        if (-not (Test-Path -LiteralPath $toc -PathType Leaf) -or -not ((Get-Content -Raw -LiteralPath $toc) -match 'Nib reply slot')) { throw "$folder is not a Nib reply slot." }
        if ($PSCmdlet.ShouldProcess($folder, 'Remove Nib reply slot')) {
            foreach ($file in @($toc, (Join-Path $folder 'Data.lua'))) { if (Test-Path -LiteralPath $file -PathType Leaf) { Remove-Item -LiteralPath $file -Force } }
            Get-ChildItem -LiteralPath $folder -Filter 'Data.*.tmp' -File | Remove-Item -Force
            if (Get-ChildItem -LiteralPath $folder -Force) { Write-Warning "$folder has other files and was left in place." } else { Remove-Item -LiteralPath $folder -Force; $removed++ }
        }
    }
    Write-Output "Removed $removed Nib reply slot folder(s)."
} elseif (-not $Optical) {
    foreach ($name in $slotNames) {
        $installed = Join-Path $targetRoot ($name + '\' + $name + '.toc')
        $manifest = Join-Path $sourceRoot ($name + '\' + $name + '.toc')
        if ((Test-Path -LiteralPath $installed -PathType Leaf) -and (Test-Path -LiteralPath $manifest -PathType Leaf) -and
            -not ((Get-Item -LiteralPath (Split-Path $installed -Parent)).Attributes -band [IO.FileAttributes]::ReparsePoint) -and
            $PSCmdlet.ShouldProcess($installed, 'Update reply slot manifest')) {
            Copy-Item -LiteralPath $manifest -Destination $installed -Force
        }
    }
}
if (-not $WhatIfPreference) {
    # The helper watches the screen when the game has a way to receive replies: the reply files, or the older reply slots.
    $hasSlots = $Optical -or (Test-Path -LiteralPath (Join-Path $targetRoot 'NibWhisperReply200\NibWhisperReply200.toc')) -or (Test-Path -LiteralPath (Join-Path $targetRoot 'NibWhisper_Assistant\Fonts\R0001.ttf'))
    $settings = @{ addonsRoot = $targetRoot; opticalInstalled = [bool]$hasSlots }
    $settingsDir = Join-Path $PSScriptRoot 'companion\data'
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
    $settings | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $settingsDir 'bridge-settings.json') -Encoding UTF8
    Write-Output "Installed $($names.Count) Nib addon folder(s). Start WoW and enable Nib Whisper, then Nib Whisper: Leveling Guide, Nib Whisper: AI Assistant, or both."
    if ($clientRunning) { Write-Output 'WoW is running. These new folders will appear after you fully exit and reopen the client; your current session was left running.' }
    if ($Optical) { Write-Output 'Automatic mode is optional: launch Start-Nib.ps1 -Optical, then type /nib auto in-game. A full client restart is required after first installing reply slots.' }
    if ($Background) {
        if (-not $hasSlots) { throw 'Use -Optical -Background to install the reply modules and helper together.' }
        $startup = [Environment]::GetFolderPath('Startup')
        $shortcutPath = Join-Path $startup 'Nib Helper.lnk'
        if ($PSCmdlet.ShouldProcess($shortcutPath, 'Start Nib Helper when you sign into Windows')) {
            $shell = New-Object -ComObject WScript.Shell
            $shortcut = $shell.CreateShortcut($shortcutPath)
            $shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            $helper = Join-Path $PSScriptRoot 'Start-Nib-Helper.ps1'
            $shortcut.Arguments = '-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $helper + '"'
            $shortcut.WorkingDirectory = $PSScriptRoot
            $shortcut.Description = 'Start the local Nib helper for WoW chat and progress sync.'
            $shortcut.Save()
            & $helper
            Write-Output 'Nib Helper starts at Windows sign-in. Connect Gemini from Nib chat in WoW.'
        }
    }
}
