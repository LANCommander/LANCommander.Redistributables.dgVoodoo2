<#
.SYNOPSIS
    Parses dgVoodoo.conf into parsed option records.
.DESCRIPTION
    dgVoodoo.conf is INI-shaped, but its documentation is laid out in a way the
    shared INI parser cannot follow. Upstream documents a whole section at once, in
    a single comment block that sits between the section header and a blank line:

        [Glide]

        ;  VideoCard:      "voodoo_graphics", "voodoo_rush", "voodoo_2", ...
        ; OnboardRAM:      in MBs
        ;    TMUFiltering: "appdriven", "pointsampled", "bilinear"

        VideoCard                           = voodoo_2
        OnboardRAM                          = 8

    ConvertFrom-IniConfig clears its comment buffer at the first blank line, since
    everywhere else a comment block belongs to the key directly beneath it. Here
    that drops every description and every choice list on the floor, which is why
    this file exists rather than a ChoiceCommentPattern.

    Two passes per section: build a key -> {description, choices} map out of the
    comment block, then attach it to the key = value lines below.

    Nothing here is specific to a dgVoodoo version. Keys upstream adds are picked up
    on the next scheduled run along with whatever documentation they carry, which is
    the whole point of parsing rather than hand-writing the schema.
.PARAMETER Content
    Raw file contents, passed by ConvertTo-OptionSchema.
.PARAMETER Source
    File name, recorded on each record for provenance.
.OUTPUTS
    Records shaped like New-ParsedOption's output: Path, Segments, Type, Default,
    Choices, Comment, Source. Built by hand rather than through the module's own
    helper, because a repository-local parser should not depend on module internals.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][AllowEmptyString()][string] $Content,
    [string] $Source
)

$ErrorActionPreference = 'Stop'

# Mirrors ConvertTo-OptionKey in the shared module. The generated dot-path has to
# match what that would have produced, because Schema.Overlay.yml is keyed by it
# and BeforeStart.ps1 derives the same path from the same config key at runtime.
function ConvertTo-Key {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Key)

    $sanitized = $Key -replace ' ', '' -replace '\.', '_' -replace '-', '_'
    $sanitized = $sanitized -replace '[^A-Za-z0-9_]', '_'

    if ([string]::IsNullOrEmpty($sanitized)) { return $sanitized }

    return $sanitized.Substring(0, 1).ToUpperInvariant() + $sanitized.Substring(1)
}

# Same rules as Get-InferredOptionType: 0 and 1 stay int, because in an INI file
# they are genuinely ambiguous and mistyping an int as bool destroys the value.
# dgVoodoo writes real booleans as true/false, so this gets them right.
function Get-Type {
    param([AllowNull()][AllowEmptyString()][string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return 'string' }

    $trimmed = $Value.Trim()

    if ($trimmed -in @('true', 'false')) { return 'bool' }

    $parsed = 0
    if ([int]::TryParse($trimmed, [ref] $parsed)) { return 'int' }

    return 'string'
}

<#
.SYNOPSIS
    Turns one section's comment block into a key -> documentation map.
.DESCRIPTION
    A line of the form ';<indent>SomeKey: rest' opens an entry. Any comment line
    after it that is not itself such a header is a continuation of it. A bare ';'
    is a separator and is dropped.

    The header test deliberately requires the name to be followed by a colon and to
    look like an identifier, so prose containing a colon does not open a bogus
    entry. It is confirmed against the real key list afterwards regardless.
#>
function Get-SectionDocumentation {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]] $CommentLines)

    $entries = [ordered] @{}
    $current = $null

    foreach ($line in $CommentLines) {
        $text = $line -replace '^\s*;', ''

        if ([string]::IsNullOrWhiteSpace($text)) { continue }

        if ($text -match '^\s*(?<key>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*(?<rest>.*)$') {
            $current = $Matches['key']

            if (-not $entries.Contains($current)) {
                $entries[$current] = [System.Collections.Generic.List[string]]::new()
            }

            $rest = $Matches['rest'].Trim()
            if ($rest) { $entries[$current].Add($rest) }

            continue
        }

        # Continuation of whatever header was last seen. Text before the first
        # header in a block is section-level preamble and belongs to no key.
        if ($current) { $entries[$current].Add($text.Trim()) }
    }

    return $entries
}

<#
.SYNOPSIS
    Extracts the quoted literals from a documentation entry.
.DESCRIPTION
    Upstream writes valid values as double-quoted, comma-separated tokens. Tokens
    containing '%' are printf-style placeholders describing a family of values
    ("%dx", "max_%dx") rather than values themselves, so they are dropped -- an
    option is only a genuine choice list when every literal is selectable.

    A single quoted token is not a choice list. It is almost always prose quoting
    one special value, and turning it into a one-item dropdown would lock the option
    to that value.
#>
function Get-QuotedChoice {
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Text)

    $tokens = [regex]::Matches($Text, '"(?<value>[^"]+)"') |
        ForEach-Object { $_.Groups['value'].Value.Trim() } |
        Where-Object { $_ -and $_ -notmatch '%' }

    $unique = @($tokens | Select-Object -Unique)

    if ($unique.Count -lt 2) { return @() }

    return $unique
}

$records = [System.Collections.Generic.List[object]]::new()

$section = $null
$commentLines = [System.Collections.Generic.List[string]]::new()
$documentation = [ordered] @{}

foreach ($rawLine in ($Content -split "`r?`n")) {
    $line = $rawLine.Trim()

    if ([string]::IsNullOrEmpty($line)) { continue }

    if ($line.StartsWith('[') -and $line.Contains(']')) {
        $section = $line.TrimStart('[').Split(']')[0].Trim()
        $commentLines.Clear()
        $documentation = [ordered] @{}
        continue
    }

    if ($line.StartsWith(';') -or $line.StartsWith('#')) {
        # Unlike the shared parser, comment lines accumulate across blank lines and
        # are only reset by a section header. That is the whole difference.
        $commentLines.Add($line)
        $documentation = Get-SectionDocumentation -CommentLines $commentLines
        continue
    }

    $eq = $line.IndexOf('=')
    if ($eq -le 0) { continue }

    $key = $line.Substring(0, $eq).Trim()
    $value = $line.Substring($eq + 1).Trim().Trim('"')

    if (-not $key) { continue }

    $comment = ''
    $choices = @()

    if ($documentation.Contains($key)) {
        $joined = ($documentation[$key] -join ' ').Trim()
        $choices = Get-QuotedChoice -Text $joined

        # Collapse runs of whitespace so the reflowed block reads as a sentence
        # rather than carrying upstream's column alignment into the admin UI.
        $comment = ($joined -replace '\s+', ' ').Trim()

        if ($choices.Count -gt 0) {
            # For many options upstream's entire documentation IS the list of valid
            # values. Repeating it as the description just prints the dropdown twice.
            # Drop the description unless there is prose left once the literals are
            # removed -- an empty one is honest, and Export-OptionSchemaFile reports
            # the option as uncurated so it can be written properly in the overlay.
            $residue = ($comment -replace '"[^"]*"', '') -replace '[\s,;:.()\[\]{}|/-]', ''

            if ($residue.Length -lt 12) { $comment = '' }
        }
    }

    $type = if ($choices.Count -gt 0) { 'choice' } else { Get-Type -Value $value }

    # Match ConvertTo-OptionDefault: booleans are stored lowercase, so an unquoted
    # YAML boolean can never reach the SDK and come back as .NET's "False".
    $default = if ($type -eq 'bool') { $value.Trim().ToLowerInvariant() } else { $value }

    $segments = if ($section) {
        @((ConvertTo-Key -Key $section), (ConvertTo-Key -Key $key))
    }
    else {
        @(ConvertTo-Key -Key $key)
    }

    $records.Add([pscustomobject] @{
            Path     = ($segments -join '.')
            Segments = $segments
            Type     = $type
            Default  = $default
            Choices  = $choices
            Comment  = $comment
            Source   = $Source
        })
}

return $records.ToArray()
