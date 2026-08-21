# Writes the resolved per-game options into dgVoodoo.conf next to the game
# executable, where dgVoodoo looks for it.
#
# This rewrites the file in one pass from upstream's own template rather than
# calling Update-IniValue per key. dgVoodoo.conf has ninety-odd keys, so that would
# be ninety read-modify-write cycles on every single launch. Rewriting also keeps
# upstream's comments and ordering intact, so the file a curious administrator opens
# still looks like the documented one.
#
# The option path is derived from the config's own section and key rather than from
# a hard-coded table, using the same transformation the schema generator applied
# when it parsed this file. That means a key upstream adds is written out correctly
# as soon as it appears in the schema, with no change here.
#
# Working directory: {InstallDir}\.lancommander\{RedistributableId}\Files\
# Available: $InstallDirectory, $GameManifest, $RedistributableManifest, $PlayerAlias

$ErrorActionPreference = 'Stop'

$metadata = Join-Path $InstallDirectory (Join-Path '.lancommander' $RedistributableManifest.Id)
$template = Join-Path (Join-Path $metadata 'Files') 'dgVoodoo.conf'

if (-not (Test-Path -LiteralPath $template)) {
    Write-Warning 'dgVoodoo.conf is not present in the downloaded archive; leaving the game directory alone'
    $Return = 0
    return
}

$options = Get-RedistributableOptions -Path $InstallDirectory -Id $GameManifest.Id -Name 'dgVoodoo2'

if (-not $options) {
    Write-Warning 'No dgVoodoo options could be resolved; leaving the game directory alone'
    $Return = 0
    return
}

# Mirrors ConvertTo-OptionKey in the packaging module, and Parse-Config.ps1 in this
# repository. All three have to agree or an option silently stops being applied.
function ConvertTo-Key {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Key)

    $sanitized = $Key -replace ' ', '' -replace '\.', '_' -replace '-', '_'
    $sanitized = $sanitized -replace '[^A-Za-z0-9_]', '_'

    if ([string]::IsNullOrEmpty($sanitized)) { return $sanitized }

    return $sanitized.Substring(0, 1).ToUpperInvariant() + $sanitized.Substring(1)
}

function Get-OptionValue {
    param([Parameter(Mandatory)][string] $Group, [Parameter(Mandatory)][string] $Key)

    $groupNode = $options.PSObject.Properties[$Group]
    if (-not $groupNode -or -not $groupNode.Value) { return $null }

    $leaf = $groupNode.Value.PSObject.Properties[$Key]
    if (-not $leaf) { return $null }

    return $leaf.Value
}

$section = $null
$applied = 0
$output = [System.Collections.Generic.List[string]]::new()

foreach ($rawLine in (Get-Content -LiteralPath $template)) {
    $trimmed = $rawLine.Trim()

    if ($trimmed.StartsWith('[') -and $trimmed.Contains(']')) {
        $section = $trimmed.TrimStart('[').Split(']')[0].Trim()
        $output.Add($rawLine)
        continue
    }

    # Comments and blanks pass through untouched, which is what preserves upstream's
    # documentation in the generated file.
    if (-not $trimmed -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) {
        $output.Add($rawLine)
        continue
    }

    $eq = $rawLine.IndexOf('=')

    if ($eq -le 0 -or -not $section) {
        $output.Add($rawLine)
        continue
    }

    $key = $rawLine.Substring(0, $eq).Trim()
    $value = Get-OptionValue -Group (ConvertTo-Key -Key $section) -Key (ConvertTo-Key -Key $key)

    if ($null -eq $value) {
        # Excluded from the schema, or upstream added it since the last release.
        # Upstream's own default is the right answer in both cases.
        $output.Add($rawLine)
        continue
    }

    $text = [string] $value

    # OptionDefinition.Default is object-typed and GetDefaultAsString() calls
    # ToString(), so a boolean arrives as .NET's "True"/"False". dgVoodoo parses
    # only lowercase true/false and silently treats anything else as false, which
    # would turn every enabled toggle off.
    if ($text -in @('True', 'False')) { $text = $text.ToLowerInvariant() }

    # Preserve upstream's column alignment so the result still reads like the
    # original file rather than a machine-mangled version of it.
    $output.Add(('{0}= {1}' -f $rawLine.Substring(0, $eq), $text).TrimEnd())
    $applied++
}

Set-Content -LiteralPath (Join-Path $InstallDirectory 'dgVoodoo.conf') `
    -Value $output -Encoding utf8

Write-Host "Wrote dgVoodoo.conf to $InstallDirectory ($applied option(s) applied)"

$Return = 0
