# Removes only the files this redistributable placed in the game directory.
#
# dgVoodoo's DLLs are named after the system libraries they stand in for -- DDraw.dll,
# D3D9.dll, Glide2x.dll. Some games legitimately ship their own copy of exactly those
# names, so deleting by name would destroy game files. Install.ps1 records what it
# actually wrote and this reads that list back.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\Files\
# Runs before the launcher deletes the tracked files and the metadata directory.

$metadata = Join-Path $InstallDirectory (Join-Path '.lancommander' $RedistributableManifest.Id)
$manifest = Join-Path $metadata 'DeployedFiles.txt'

$Return = 0

if (-not (Test-Path -LiteralPath $manifest)) {
    # Nothing was recorded, so nothing is known to be ours. Leaving files behind is
    # the safe failure here; guessing is not.
    return
}

$deployed = @(Get-Content -LiteralPath $manifest -ErrorAction SilentlyContinue |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ })

foreach ($file in $deployed) {
    # Defend against a tampered manifest steering the delete outside the game
    # directory. Only ever remove a bare file name from $InstallDirectory itself.
    if ($file -match '[\/]' -or $file -eq '.' -or $file -eq '..') {
        Write-Warning "Skipping '$file': the deployment manifest should only contain bare file names"
        continue
    }

    $path = Join-Path $InstallDirectory $file

    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

# The generated config is ours too, and AfterStop may not have run.
$conf = Join-Path $InstallDirectory 'dgVoodoo.conf'
if (Test-Path -LiteralPath $conf) {
    Remove-Item -LiteralPath $conf -Force -ErrorAction SilentlyContinue
}

Write-Host "Removed $($deployed.Count) dgVoodoo file(s) from $InstallDirectory"
