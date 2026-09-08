# Builds dist\mpv-config.zip: everything someone else needs, and nothing of
# mine. Run it from the repo root.
#
#   powershell -ExecutionPolicy Bypass -File package.ps1
#
# They unzip it into %APPDATA%\mpv and that is the whole install.

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$stage = Join-Path $root "dist\stage"
$zip = Join-Path $root "dist\mpv-config.zip"

# Personal state, caches, and credentials. None of this travels.
$skip = @(
    "presence-key.txt",       # TMDB key
    "presence-cache.json",    # which show is in which folder
    "subdict-cache.json",     # looked-up words
    "substyle-state.txt",     # last used subtitle preset
    "*.before-substyle",      # backups the adjust panel made
    "dist", ".git", ".github", "package.ps1"
)

if (Test-Path (Join-Path $root "dist")) { Remove-Item (Join-Path $root "dist") -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null

Get-ChildItem -Path $root -Force | Where-Object {
    $name = $_.Name
    -not ($skip | Where-Object { $name -like $_ })
} | ForEach-Object {
    Copy-Item $_.FullName -Destination $stage -Recurse -Force
}

# Paths that are mine. Point them somewhere that works on any machine;
# ~~ is mpv's own config folder, so screenshots land beside the config.
$conf = Join-Path $stage "mpv.conf"
(Get-Content $conf -Raw) `
    -replace 'screenshot-dir=.*', 'screenshot-dir="~~/screenshots"' |
    Set-Content $conf -NoNewline -Encoding utf8

# Presets someone saved themselves; ship the file empty, with its header.
$custom = Join-Path $stage "substyle-custom.conf"
if (Test-Path $custom) {
    (Get-Content $custom) | Where-Object { $_ -match '^\s*#' -or $_ -eq '' } |
        Set-Content $custom -Encoding utf8
}

Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force
Remove-Item $stage -Recurse -Force

$size = [math]::Round((Get-Item $zip).Length / 1MB, 1)
Write-Output "built $zip ($size MB)"
