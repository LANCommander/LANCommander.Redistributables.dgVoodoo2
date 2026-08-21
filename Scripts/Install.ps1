# Copies the enabled dgVoodoo DLLs next to the game executable.
#
# dgVoodoo is not installed in any normal sense: it works by sitting in the game's
# own directory under the name of the API it replaces, so the game loads it instead
# of the system one. Nothing is registered, nothing goes in System32, and no
# elevation is needed.
#
# That also means it must be opted into per API. A stray DDraw.dll hijacks a game
# that was talking to DirectDraw perfectly well on its own, so every API defaults to
# off and an administrator enables what a given game actually needs.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\Files\
# -- the extracted upstream archive, which Scripts/Package.ps1 downloaded onto the
# server. Available: $InstallDirectory, $GameManifest, $RedistributableManifest

$ErrorActionPreference = 'Stop'

$metadata = Join-Path $InstallDirectory (Join-Path '.lancommander' $RedistributableManifest.Id)
$files = Join-Path $metadata 'Files'

# Source.Mode is 'none', so the published package carries no archive. The files
# only exist once a server has run the Package script against upstream. Say so
# plainly -- this is the one predictable way this redistributable fails.
if (-not (Test-Path -LiteralPath (Join-Path $files 'dgVoodoo.conf'))) {
    Write-Error @"
dgVoodoo has not been downloaded yet.

This package ships scripts only, because dgVoodoo's license does not permit
bundling it inside a launcher. Your LANCommander server fetches the archive from
the author on its own, through this redistributable's Package script.

Run that Package script from the server's Redistributables page, then reinstall
this game's redistributables.
"@
    $Return = 1
    return
}

$options = Get-RedistributableOptions -Path $InstallDirectory -Id $GameManifest.Id -Name 'dgVoodoo2'

$architecture = if ($options.Deployment.Architecture) { [string] $options.Deployment.Architecture } else { 'x86' }

# Options come back as strings; OptionDefinition.Default is object-typed and
# stringified, so a bool arrives as "true"/"True" rather than a real boolean.
function Test-Enabled {
    param([AllowNull()] $Value)
    return ([string] $Value).Trim() -in @('true', 'True', '1')
}

# What upstream actually ships, verified against the 2.87.3 archive. The DirectX
# side is asymmetric and this is the trap worth knowing about: MS\x64 contains ONLY
# D3D9.dll. There is no 64-bit DDraw, D3DImm or D3D8, because no 64-bit application
# ever targeted those APIs.
$sets = @(
    @{ Option = 'DirectDraw'; Folder = 'MS';   Files = @('DDraw.dll', 'D3DImm.dll'); Architectures = @('x86') }
    @{ Option = 'Direct3D8';  Folder = 'MS';   Files = @('D3D8.dll');                Architectures = @('x86') }
    @{ Option = 'Direct3D9';  Folder = 'MS';   Files = @('D3D9.dll');                Architectures = @('x86', 'x64') }
    @{ Option = 'Glide';      Folder = '3Dfx'; Files = @('Glide.dll', 'Glide2x.dll', 'Glide3x.dll'); Architectures = @('x86', 'x64') }
)

$placed = [System.Collections.Generic.List[string]]::new()
$enabled = 0

foreach ($set in $sets) {
    if (-not (Test-Enabled $options.Deployment.($set.Option))) { continue }

    $enabled++

    if ($set.Architectures -notcontains $architecture) {
        Write-Warning "$($set.Option) is enabled but upstream ships no $architecture build of it, so it was skipped. dgVoodoo only provides $($set.Architectures -join '/') for this API."
        continue
    }

    $sourceDir = Join-Path (Join-Path $files $set.Folder) $architecture

    if (-not (Test-Path -LiteralPath $sourceDir)) {
        Write-Error "Expected $($set.Folder)\$architecture in the dgVoodoo archive but it is missing; upstream may have changed its layout"
        $Return = 1
        return
    }

    foreach ($file in $set.Files) {
        $from = Join-Path $sourceDir $file

        if (-not (Test-Path -LiteralPath $from)) {
            Write-Warning "$($set.Folder)\$architecture\$file is not in this dgVoodoo release; skipping it"
            continue
        }

        Copy-Item -LiteralPath $from -Destination (Join-Path $InstallDirectory $file) -Force
        $placed.Add($file)
    }
}

if ($enabled -eq 0) {
    Write-Warning 'No dgVoodoo APIs are enabled for this game, so nothing was deployed. Enable the ones it needs under Deployment in the game''s redistributable options.'
}

# Record exactly what was placed. Uninstall reads this rather than guessing, so it
# can never delete a DLL that genuinely belongs to the game.
Set-Content -LiteralPath (Join-Path $metadata 'DeployedFiles.txt') `
    -Value ($placed -join "`n") -Encoding utf8

Write-Host "dgVoodoo $($RedistributableManifest.Version) ($architecture): deployed $($placed.Count) file(s) to $InstallDirectory"

# Written last, once everything above has succeeded. DetectInstall compares against
# this, so it must not exist unless the deployment is complete and usable.
Set-Content -LiteralPath (Join-Path $metadata 'InstalledVersion.txt') `
    -Value "$($RedistributableManifest.Version)|$architecture|$($placed -join ',')" -Encoding utf8 -NoNewline

$Return = 0
