# Server-side. This is where the dgVoodoo payload actually comes from.
#
# Unlike every other redistributable in the family, this one does NOT repackage our
# own .lcx release -- that release deliberately contains no dgVoodoo files at all.
# dgVoodoo's license forbids bundling it inside a launcher, so we publish scripts
# only, and each LANCommander server fetches the archive from the author himself.
#
# The whole archive is kept, including the control panel, the ARM64 builds and the
# documentation shortcuts. That is deliberate and is the opposite of the usual
# advice to narrow a payload: the license says that anyone redistributing dgVoodoo
# as a standalone component "must provide the full .zip package", and a server
# handing it to its own clients is doing exactly that.
#
# Returning nothing means "no new package required", which is the normal result.
#
# Available: $Redistributable (including its current Version) and $LatestArchivePath.

$ErrorActionPreference = 'Stop'

$repository = 'dege-diosg/dgVoodoo2'

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/latest" -Headers @{
    'Accept'     = 'application/vnd.github+json'
    'User-Agent' = 'LANCommander'
}

$version = ([string] $release.tag_name) -replace '^v', ''

if ([string]::IsNullOrWhiteSpace($version)) {
    throw "The latest dgVoodoo2 release has no usable tag name"
}

# Nothing to do when the server already has this version.
if ($version -eq $Redistributable.Version) {
    return
}

# Every release also carries a debug build, a developer package, the API headers
# and a standalone WinMM shim. Only the plain versioned archive is the one users
# are meant to deploy.
$asset = $release.assets |
    Where-Object { $_.name -match '^dgVoodoo2_[0-9_]+\.zip$' } |
    Select-Object -First 1

if (-not $asset) {
    $listing = ($release.assets | ForEach-Object { $_.name }) -join ', '
    throw "Release $($release.tag_name) has no plain dgVoodoo2 archive. Assets: $listing"
}

$staging = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP "dgVoodoo2-$version")
$archive = Join-Path $env:TEMP "dgVoodoo2-$version.zip"

try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $archive

    Expand-Archive -Path $archive -DestinationPath $staging -Force

    # Sanity check the layout before handing it over. If upstream reorganises, this
    # should fail here with something readable rather than on every client at
    # install time with a missing-file error.
    if (-not (Test-Path -LiteralPath (Join-Path $staging 'dgVoodoo.conf'))) {
        throw "The downloaded archive has no dgVoodoo.conf at its root; upstream may have changed its layout"
    }

    # dgVoodoo states its terms on its website rather than shipping them in the
    # archive, so they are written in here. Inline rather than copied from the
    # repository because this script runs as a packed script body on a LANCommander
    # server, where $PSScriptRoot is not this repository and the file would not
    # exist. Putting the terms beside the binaries means they reach every client.
    $terms = @'
dgVoodoo 2 - Copyright (c) 2013-2026 Dege
https://dege.freeweb.hu/dgVoodoo2/

Proprietary freeware. Redistribution rights, verbatim from
https://dege.freeweb.hu/dgVoodoo2/ReadmeGeneral/ :

  You can freely ship your game or game mod with individual dgVoodoo files
  included. If you want to host or re-distribute dgVoodoo as a standalone
  component for any reason then you must provide the full .zip package. You
  cannot bundle dgVoodoo inside launchers or frameworks, for general use across
  multiple applications

These files were downloaded from the author's own release page by your
LANCommander server, complete and unmodified. They are not redistributed by the
LANCommander project.
'@

    Set-Content -LiteralPath (Join-Path $staging 'LICENSE.txt') -Value $terms -Encoding utf8

    $Return = New-Package
    $Return.Path = $staging.FullName
    $Return.Version = $version
    $Return.Changelog = $release.body
}
finally {
    Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
}
