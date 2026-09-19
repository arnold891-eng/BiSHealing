# BiSHealing :: release.ps1 (copied from BiSMemories', which came from BiSInnervate's)
# Zips the addon and pushes it to CurseForge through the upload API.
#
#   .\release.ps1                 -> zip + upload as alpha (nobody is pushed it)
#   .\release.ps1 -Type beta      -> beta; -Type release -> everyone. Or flip it on the dashboard.
#   .\release.ps1 -ZipOnly        -> just the zip, no upload
#   .\release.ps1 -Force          -> upload again even though this version already went up
#
# A version goes up ONCE: after a successful upload a marker sits beside the zip
# (Downloads\<Addon>-<version>.uploaded, holding the file id). Pasting the block
# twice is then a no-op that tells you the file id, not a duplicate on CurseForge.
#
# Needs, once:
#   * the API token in %USERPROFILE%\Downloads\curseforge-token.txt
#     (CurseForge -> My Account -> API Tokens). One line, nothing else.
#   * the CurseForge project id in the TOC: ## X-Curse-Project-ID (0 until the project exists -
#     a zip still builds, an upload refuses). The game version type is the TOC's
#     ## X-CurseForge-GameVersionType ("Burning Crusade" today; the Forever name when it exists).
#   * On GitHub none of this lives on disk: a pushed tag vX.Y.Z runs bisdev's release workflow,
#     which sets RELEASE_OUT and CURSEFORGE_TOKEN (see _bisdev/docs/playbook.md).
#
# The zip lands in Downloads. The changelog sent is the top entry of
# CHANGELOG.md; the version is the TOC's ## Version. Game version is looked
# up live so a client patch never needs a code change here.

param(
    [ValidateSet("release", "beta", "alpha")] [string] $Type = "alpha",
    [switch] $ZipOnly,
    [switch] $Force
)

$ErrorActionPreference = "Stop"

$AddonName = "BiSHealing"
$Root      = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)   # ..\BiSHealing
# On Arn's PC the zip lands in Downloads. GitHub's release workflow (bisdev .github/workflows/release.yml)
# sets RELEASE_OUT instead - no Downloads folder on a build machine.
$Downloads = if ($env:RELEASE_OUT) { $env:RELEASE_OUT } else { Join-Path $env:USERPROFILE "Downloads" }
$TokenFile = Join-Path $Downloads "curseforge-token.txt"

# version from the TOC
$toc = Get-Content (Join-Path $Root "$AddonName.toc")
$version = ($toc | Where-Object { $_ -match '^## Version:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() })
if (-not $version) { throw "no ## Version in the TOC" }
# the CurseForge project and game type live in the TOC, so a new addon never edits this script
$ProjectId = [int](@($toc | Where-Object { $_ -match '^## X-Curse-Project-ID:\s*(\d+)' } | ForEach-Object { $Matches[1] }) + '0')[0]
$GameType = @($toc | Where-Object { $_ -match '^## X-CurseForge-GameVersionType:\s*(.+)$' } | ForEach-Object { $Matches[1].Trim() })[0]
if (-not $GameType) { $GameType = "Burning Crusade" }

# the top entry of the changelog: from the first "## x.y.z" to the next one
$lines = Get-Content (Join-Path $Root "CHANGELOG.md")
$entry = @(); $inside = $false
foreach ($l in $lines) {
    if ($l -match '^## ') { if ($inside) { break }; $inside = $true; continue }
    if ($inside) { $entry += $l }
}
$changelog = ($entry -join "`n").Trim()

# embedded libs must be byte-identical to their canonical copies, or a release
# ships an old lib (10 Sep 2026: minor 4 still in three addons while minor 5
# fixed the phantom summon). ..\_bisdev\sync.ps1 copies them; -Check just looks.
$canon = @{
    "Libs\BiSTheme\Console.lua" = "..\BiSTheme\Console.lua"
    "Libs\BiSTheme\Options.lua" = "..\BiSTheme\Options.lua"
    "Libs\BiSTheme\Minimap.lua" = "..\BiSTheme\Minimap.lua"
}
foreach ($k in $canon.Keys) {
    $mine = Join-Path $Root $k
    $ref  = Join-Path $Root $canon[$k]
    if ((Test-Path $mine) -and (Test-Path $ref)) {
        $a = (Get-FileHash $mine -Algorithm MD5).Hash
        $b = (Get-FileHash $ref  -Algorithm MD5).Hash
        if ($a -ne $b) { throw "embedded $k differs from its canonical copy - run ..\_bisdev\sync.ps1 first" }
    }
}

# the zip: everything but dev/, CLAUDE.md, .git* (.git, .github, .gitignore, .gitattributes)
# and this repo's local leftovers - desk debt 28, 16 Sep 2026
$zip = Join-Path $Downloads "$AddonName-$version.zip"
$stage = Join-Path ([System.IO.Path]::GetTempPath()) "$AddonName-release"   # $env:TEMP does not exist on Linux
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory -Path (Join-Path $stage $AddonName) | Out-Null
Get-ChildItem $Root -Force | Where-Object {
    $_.Name -notin @("dev", "CLAUDE.md", ".pkgmeta", "LICENSE.bak") -and $_.Name -notlike ".git*"
} | ForEach-Object { Copy-Item $_.FullName -Destination (Join-Path $stage $AddonName) -Recurse }
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $stage $AddonName) -DestinationPath $zip
Write-Host "zip: $zip"
if ($ZipOnly) { exit 0 }

$marker = Join-Path $Downloads "$AddonName-$version.uploaded"
if ((Test-Path $marker) -and -not $Force) {
    Write-Host "already uploaded: $AddonName $version went up as file id $((Get-Content $marker -Raw).Trim()) - bump the version (or -Force to send it again)"
    exit 0
}

if ($ProjectId -eq 0) { throw "no CurseForge project yet - put its id in the TOC as ## X-Curse-Project-ID" }
# GitHub's release workflow hands the token over as CURSEFORGE_TOKEN (a repo secret); on Arn's PC it is the file
if ($env:CURSEFORGE_TOKEN) {
    $token = $env:CURSEFORGE_TOKEN.Trim()
} else {
    if (-not (Test-Path $TokenFile)) { throw "no token file at $TokenFile" }
    $token = (Get-Content $TokenFile -Raw).Trim()
}
$headers = @{ "X-Api-Token" = $token }

# game version: the newest version under the TOC's game type, whatever its id is this month
$types = Invoke-RestMethod -Headers $headers -Uri "https://wow.curseforge.com/api/game/version-types"
$tbcType = $types | Where-Object { $_.name -like "*$GameType*" } | Select-Object -First 1
if (-not $tbcType) { throw "no CurseForge game version type like '$GameType': " + (($types | ForEach-Object { $_.name }) -join ", ") }
$versions = Invoke-RestMethod -Headers $headers -Uri "https://wow.curseforge.com/api/game/versions"
$gv = $versions | Where-Object { $_.gameVersionTypeID -eq $tbcType.id } | Sort-Object name -Descending | Select-Object -First 1
if (-not $gv) { throw "no game version under type $($tbcType.name)" }
Write-Host "game version: $($gv.name) (id $($gv.id), type $($tbcType.name))"

# WoW Forever. A TOC that lists 16001 ships for that client as well, so the upload has to carry its
# CurseForge id too: the API takes CURSEFORGE'S OWN ids in gameVersions, never "1.60.1" and never an
# interface number, and an upload with only the TBC id lands on the wrong flavour.
#
# Looked up live, with _bisdev/release/versions.json as the pinned record and the fallback for a
# machine that cannot reach the API. Refresh it with _bisdev/release/fetch-versions.ps1 (Arn runs
# that: the token never passes through Claude).
$gameVersionIds = @($gv.id)
$ifaceLine = @($toc | Where-Object { $_ -match '^##\s*Interface\s*:\s*(.+)$' } | ForEach-Object { $Matches[1] })
if ($ifaceLine -and (($ifaceLine[0] -split '[,\s]+') -contains '16001')) {
    $pin = Join-Path $PSScriptRoot "..\..\_bisdev\release\versions.json"
    $typeId = 88568                      # the 1.60.x / Forever family on CurseForge
    $pinnedId = $null
    if (Test-Path $pin) {
        $doc = Get-Content $pin -Raw | ConvertFrom-Json
        if ($doc.typeId) { $typeId = [int]$doc.typeId }
        if ($doc.forever -and $doc.forever.id) { $pinnedId = [int]$doc.forever.id }
    }
    $fv = $versions | Where-Object { $_.gameVersionTypeID -eq $typeId -and $_.name -like '1.60*' } |
          Sort-Object name | Select-Object -Last 1
    $foreverId = if ($fv) { [int]$fv.id } elseif ($pinnedId) { $pinnedId } else { $null }
    if (-not $foreverId) {
        throw "the TOC claims 16001 but CurseForge has no 1.60.x under type ${typeId}. Run _bisdev/release/fetch-versions.ps1 and commit versions.json"
    }
    if ($gameVersionIds -notcontains $foreverId) { $gameVersionIds += $foreverId }
    if ($fv) { Write-Host "forever version: $($fv.name) (id $foreverId)" }
    else     { Write-Host "forever version: id $foreverId (pinned in versions.json)" }
}


# multipart by hand: Invoke-RestMethod -Form needs PS 6+, this runs on 5.1 too
function Send-Upload($log, $logType) {
    $metadata = @{
        changelog     = $log
        changelogType = $logType
        displayName   = "$AddonName $version"
        gameVersions  = @($gameVersionIds)
        releaseType   = $Type
    } | ConvertTo-Json -Compress
    $boundary = [System.Guid]::NewGuid().ToString()
    $bytes = [System.IO.File]::ReadAllBytes($zip)
    $enc = [System.Text.Encoding]::UTF8
    $head = "--$boundary`r`nContent-Disposition: form-data; name=`"metadata`"`r`nContent-Type: application/json`r`n`r`n$metadata`r`n" +
            "--$boundary`r`nContent-Disposition: form-data; name=`"file`"; filename=`"$(Split-Path $zip -Leaf)`"`r`nContent-Type: application/zip`r`n`r`n"
    $tail = "`r`n--$boundary--`r`n"
    $body = New-Object System.IO.MemoryStream
    $b = $enc.GetBytes($head); $body.Write($b, 0, $b.Length)
    $body.Write($bytes, 0, $bytes.Length)
    $b = $enc.GetBytes($tail); $body.Write($b, 0, $b.Length)
    return Invoke-RestMethod -Method Post -Headers $headers -ContentType "multipart/form-data; boundary=$boundary" `
        -Uri "https://wow.curseforge.com/api/projects/$ProjectId/upload-file" -Body $body.ToArray()
}

# CurseForge answers 500 now and then for no reason it will name. Three tries
# with the markdown changelog, then once more with it as plain text - if that
# one lands, the markdown was what it choked on and the log will say so.
$resp = $null
$attempts = @(
    @{ log = $changelog; type = "markdown" },
    @{ log = $changelog; type = "markdown" },
    @{ log = $changelog; type = "markdown" },
    @{ log = ($changelog -replace '[`*_]', ''); type = "text" }
)
for ($i = 0; $i -lt $attempts.Count -and -not $resp; $i++) {
    try {
        $resp = Send-Upload $attempts[$i].log $attempts[$i].type
    } catch {
        $msg = $_.Exception.Message
        try { $sr = New-Object IO.StreamReader($_.Exception.Response.GetResponseStream()); $msg = $sr.ReadToEnd() } catch {}
        Write-Host ("attempt {0} ({1}) failed: {2}" -f ($i + 1), $attempts[$i].type, $msg)
        if ($i -lt $attempts.Count - 1) { Start-Sleep -Seconds 5 }
    }
}
if (-not $resp) { throw "upload failed after $($attempts.Count) attempts - the zip is still in Downloads, upload it by hand on the project page" }
Set-Content -Path $marker -Value $resp.id
Write-Host "uploaded: file id $($resp.id) - $AddonName $version ($Type)"
