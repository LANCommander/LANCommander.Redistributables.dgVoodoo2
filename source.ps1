<#
.SYNOPSIS
    Resolves the upstream dgVoodoo2 release and refreshes the reference config.
.DESCRIPTION
    Contract:
      -CheckOnly            write the upstream version to stdout and exit.
      -OutputPath <dir>     write the reference material there, then emit a JSON
                            object with Version and optionally Changelog.

    Source.Mode is 'none', so this never produces a shippable payload. dgVoodoo's
    license forbids bundling it inside a launcher, and the packaging module honours
    that by never returning a payload path in this mode.

    This script upholds the same rule independently: the ONLY file it ever writes
    out is dgVoodoo.conf. A DLL cannot leave here even if this is called with
    -OutputPath by mistake or by a future workflow change. Do not "helpfully" widen
    the copy step -- that is the one edit that would turn this repository into a
    license violation.

    dgVoodoo.conf is needed because it is the sole input to the option schema.
    Resolve-RedistributablePayload -RefreshReference points -OutputPath at the
    repository's Reference/ directory so the scheduled upstream check can commit
    a refreshed copy alongside the regenerated schema.

    Upstream tags with a leading 'v' ('v2.87.3'); Resolve-UpstreamVersion strips
    exactly one, leaving the version upstream itself calls it.
#>
[CmdletBinding(DefaultParameterSetName = 'Download')]
param(
    [Parameter(ParameterSetName = 'Check')][switch] $CheckOnly,
    [Parameter(ParameterSetName = 'Download', Mandatory)][string] $OutputPath
)

$ErrorActionPreference = 'Stop'

$definition = Get-RedistributableDefinition -Path $PSScriptRoot
$source = $definition['Source']

$upstream = Resolve-UpstreamVersion -Resolver ([string] $source['Resolver']) `
    -Url ([string] $source['Url']) `
    -AssetPattern ([string] $source['AssetPattern'])

if ($CheckOnly) {
    Write-Output $upstream.Version
    return
}

if (-not $upstream.DownloadUrl) {
    throw "No asset matched '$($source['AssetPattern'])' on the latest release"
}

$temp = Join-Path ([System.IO.Path]::GetTempPath()) "dgVoodoo2-$([guid]::NewGuid())"
$archive = Join-Path $temp 'dgVoodoo2.zip'

$null = New-Item -ItemType Directory -Path $temp -Force

try {
    Write-Verbose "Downloading $($upstream.DownloadUrl)"
    Invoke-WebRequest -Uri $upstream.DownloadUrl -OutFile $archive -MaximumRetryCount 3 -RetryIntervalSec 5

    if ($PSVersionTable.PSEdition -eq 'Desktop') {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
    }

    # Read the single entry straight out of the ZIP rather than expanding it. With
    # nothing else ever unpacked there is no window in which a DLL exists on disk,
    # and no chance of a later copy step sweeping one up.
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)

    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -eq 'dgVoodoo.conf' } | Select-Object -First 1

        if (-not $entry) {
            # Fall back to a search before giving up: upstream moving the file is a
            # layout change worth reporting precisely, not a mystery failure.
            $entry = $zip.Entries | Where-Object { $_.Name -eq 'dgVoodoo.conf' } | Select-Object -First 1
        }

        if (-not $entry) {
            $listing = ($zip.Entries | ForEach-Object { $_.FullName }) -join ', '
            throw "The release archive has no dgVoodoo.conf; upstream may have changed its layout. Contents: $listing"
        }

        if (-not (Test-Path -LiteralPath $OutputPath)) {
            $null = New-Item -ItemType Directory -Path $OutputPath -Force
        }

        [System.IO.Compression.ZipFileExtensions]::ExtractToFile(
            $entry, (Join-Path $OutputPath 'dgVoodoo.conf'), $true)
    }
    finally {
        $zip.Dispose()
    }

    @{
        Version   = $upstream.Version
        Changelog = $upstream.Changelog
    } | ConvertTo-Json -Compress | Write-Output
}
finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
