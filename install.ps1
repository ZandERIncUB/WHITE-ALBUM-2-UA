param([string]$GameDir, [switch]$Upgrade)

$ErrorActionPreference = 'Stop'
$package = Split-Path -Parent $MyInvocation.MyCommand.Path
$manifest = Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$payload = Join-Path $package 'payload'

if ([string]::IsNullOrWhiteSpace($GameDir)) {
    Write-Host 'Enter the folder containing the Japanese WA2.exe:'
    $GameDir = Read-Host 'Game folder'
}
$GameDir = $GameDir.Trim(' ', '"')
if (-not (Test-Path -LiteralPath $GameDir -PathType Container)) {
    throw "Game folder does not exist: $GameDir"
}
$game = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $GameDir).Path)
$sourceExe = Join-Path $game 'WA2.exe'
if (-not (Test-Path -LiteralPath $sourceExe -PathType Leaf)) {
    throw 'WA2.exe was not found in the selected folder.'
}
if ((Test-Path -LiteralPath (Join-Path $game 'WA2_UA_install.json')) -and -not $Upgrade) {
    throw 'This version of the Ukrainian patch is already installed. No files were changed.'
}
foreach ($required in $manifest.required_game_files) {
    $requiredPath = Join-Path $game $required
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required game archive is missing: $required. No files were changed."
    }
}
$hash = (Get-FileHash -LiteralPath $sourceExe -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifest.source_wa2_sha256 -notcontains $hash) {
    throw 'This WA2.exe version is not supported, or the Ukrainian patch is already installed. No files were changed.'
}
if (Get-Process -Name 'WA2' -ErrorAction SilentlyContinue) {
    throw 'Close the game before installing the patch.'
}

Write-Host 'Checking package files...'
foreach ($item in $manifest.files.PSObject.Properties) {
    $relative = $item.Name.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $file = Join-Path $payload $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        throw "Package file is missing: $relative"
    }
    $actual = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $item.Value) {
        throw "Package file is damaged: $relative"
    }
}

$backup = Join-Path $game ('WA2_UA_Backup_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Path $backup | Out-Null
$items = @('WA2.exe', 'd3d9.dll', 'en.pak', 'script', 'IC/script', 'fnt', 'todokanai', 'WA2_UA_install.json')
$existing = @()
$created = @()
try {
    foreach ($name in $items) {
        $destination = Join-Path $game $name
        if (Test-Path -LiteralPath $destination) {
            $backupTarget = Join-Path $backup $name
            $backupParent = Split-Path -Parent $backupTarget
            if (-not (Test-Path -LiteralPath $backupParent)) {
                New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
            }
            Move-Item -LiteralPath $destination -Destination $backupTarget
            $existing += $name
        }
    }
    foreach ($name in $items) {
        $source = Join-Path $payload $name
        if (Test-Path -LiteralPath $source) {
            $target = Join-Path $game $name
            $targetParent = Split-Path -Parent $target
            if (-not (Test-Path -LiteralPath $targetParent)) {
                New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
            }
            $created += $name
            Copy-Item -LiteralPath $source -Destination $target -Recurse
        }
    }
    $info = @{ version = $manifest.version; installed = (Get-Date).ToString('o'); backup = $backup; original = $existing }
    $created += 'WA2_UA_install.json'
    $info | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $game 'WA2_UA_install.json') -Encoding UTF8
} catch {
    foreach ($name in $created) {
        $target = Join-Path $game $name
        if (Test-Path -LiteralPath $target) {
            $resolved = [System.IO.Path]::GetFullPath($target)
            if (-not $resolved.StartsWith($game.TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                throw 'Rollback stopped: unexpected file path.'
            }
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }
    foreach ($name in $existing) {
        $target = Join-Path $game $name
        $original = Join-Path $backup $name
        if (Test-Path -LiteralPath $original) {
            Move-Item -LiteralPath $original -Destination $target
        }
    }
    throw
}

Write-Host "Ukrainian patch installed in: $game"
Write-Host "Original files saved in: $backup"
Write-Host 'Start WA2.exe through Locale Emulator with Japanese locale.'
