# Removes the dgVoodoo.conf that BeforeStart generated.
#
# BeforeStart writes a config built from this game's options into the game's own
# directory. Left behind it is stale the moment an administrator changes anything,
# and worse, it keeps forcing resolution, antialiasing and vsync onto the game even
# if the redistributable is later detached from it. The DLLs are tracked and cleaned
# up by Uninstall; this file is regenerated on every launch, so nothing is lost by
# removing it now.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\Files\
# Available: $InstallDirectory, $GameManifest, $PlayerAlias

$conf = Join-Path $InstallDirectory 'dgVoodoo.conf'

if (Test-Path -LiteralPath $conf) {
    Remove-Item -LiteralPath $conf -Force -ErrorAction SilentlyContinue
}

$Return = 0
