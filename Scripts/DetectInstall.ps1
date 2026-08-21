# Returns $true when the currently configured dgVoodoo deployment is already in
# place for this game, which skips the Install script entirely.
#
# The stamp records the version, the architecture AND the exact file list, because
# all three can change without the others. Switching a game from Glide to Direct3D 9,
# or from x86 to x64, has to redeploy even though the dgVoodoo version is unchanged.
# A bare "does D3D9.dll exist" check would silently leave the old set in place.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\
# -- one level above Files\, which may not exist yet.
#
# Hard 10 second timeout and no network calls: this is a few file reads.

$metadata = Join-Path $InstallDirectory (Join-Path '.lancommander' $RedistributableManifest.Id)
$stamp = Join-Path $metadata 'InstalledVersion.txt'

$Return = $false

if (-not (Test-Path -LiteralPath $stamp)) { return }

$recorded = ([string] (Get-Content -LiteralPath $stamp -Raw -ErrorAction SilentlyContinue)).Trim()

$options = Get-RedistributableOptions -Path $InstallDirectory -Id $GameManifest.Id -Name 'dgVoodoo2'
$architecture = if ($options.Deployment.Architecture) { [string] $options.Deployment.Architecture } else { 'x86' }

function Test-Enabled {
    param([AllowNull()] $Value)
    return ([string] $Value).Trim() -in @('true', 'True', '1')
}

# Must stay in step with the table in Install.ps1: x64 has no DDraw, D3DImm or D3D8.
$sets = @(
    @{ Option = 'DirectDraw'; Files = @('DDraw.dll', 'D3DImm.dll'); Architectures = @('x86') }
    @{ Option = 'Direct3D8';  Files = @('D3D8.dll');                Architectures = @('x86') }
    @{ Option = 'Direct3D9';  Files = @('D3D9.dll');                Architectures = @('x86', 'x64') }
    @{ Option = 'Glide';      Files = @('Glide.dll', 'Glide2x.dll', 'Glide3x.dll'); Architectures = @('x86', 'x64') }
)

$expected = [System.Collections.Generic.List[string]]::new()

foreach ($set in $sets) {
    if (-not (Test-Enabled $options.Deployment.($set.Option))) { continue }
    if ($set.Architectures -notcontains $architecture) { continue }
    foreach ($file in $set.Files) { $expected.Add($file) }
}

$wanted = "$($RedistributableManifest.Version)|$architecture|$($expected -join ',')"

if ($recorded -ne $wanted) { return }

# The stamp can survive files being deleted from the game directory by hand, or by
# a game's own updater, so confirm they are actually still there.
foreach ($file in $expected) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDirectory $file))) { return }
}

$Return = $true
