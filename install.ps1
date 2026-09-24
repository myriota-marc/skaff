<#
.SYNOPSIS
  Deploys the Claude agent scaffold into a target project directory.

.DESCRIPTION
  Copies the shared `common/` tree and the selected pack overlay into the
  target project. Safe to re-run - existing files are preserved unless
  -Force is supplied.

.PARAMETER NewProjectDir
  Absolute or relative path to the target project directory. Created if it
  does not exist.

.PARAMETER Pack
  Pack and optional version, e.g. `csharp`, `csharp@v1`, `appsheet@v1`.
  Default: csharp (latest version).

.PARAMETER Force
  Overwrite existing files in the target. Without this flag, existing files
  are skipped and reported.

.PARAMETER AllowPackSwitch
  Proceed when the target's recorded .claude/.pack names a different pack
  than -Pack. Without this flag, installing a different pack over an
  existing install is refused after listing the files that would be
  orphaned. Re-installing the same pack (any version) is never a switch
  and never requires this flag.

.PARAMETER NoContinuity
  Skip the continuity layer (continuity/ in this repo: git and Claude Code
  hooks, gate scripts, Vale, docs/STATE.md).

.PARAMETER Human
  Actor id for human gate evidence, e.g. human:jdoe. Default:
  human:<local part of git config user.email>.

.PARAMETER Purpose
  One sentence for the docs/STATE.md purpose field.

.EXAMPLE
  .\install.ps1 -NewProjectDir C:\repos\MyService

.EXAMPLE
  .\install.ps1 -NewProjectDir ..\my-project -Pack appsheet@v1 -Force

.EXAMPLE
  .\install.ps1 -NewProjectDir ..\my-project -Pack terraform -Force -AllowPackSwitch
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string] $NewProjectDir,

    [string] $Pack = 'csharp',

    [switch] $Force,

    [switch] $AllowPackSwitch,

    [switch] $NoContinuity,

    [string] $Human = '',

    [string] $Purpose = ''
)

$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRoot = $scriptRoot
$commonRoot = Join-Path $sourceRoot 'common'

if (-not (Test-Path $commonRoot)) {
    Write-Error "Source layout not found. Expected common/ at $sourceRoot"
    exit 1
}

# Parse pack@version.
if ($Pack -match '^(?<name>[^@]+)(@(?<version>.+))?$') {
    $packName = $Matches['name']
    $packVersion = if ($Matches['version']) { $Matches['version'] } else { 'latest' }
} else {
    Write-Error "Invalid -Pack value: $Pack. Expected <name> or <name>@<version>."
    exit 1
}

$packDir = Join-Path $sourceRoot "packs/$packName"
if (-not (Test-Path $packDir)) {
    Write-Host "Unknown pack: $packName. Available:"
    Get-ChildItem -Path (Join-Path $sourceRoot 'packs') -Directory |
        ForEach-Object { Write-Host "  $($_.Name)" }
    exit 1
}

if ($packVersion -eq 'latest') {
    $versionDirs = Get-ChildItem -Path $packDir -Directory |
        Where-Object { $_.Name -match '^v[0-9]+$' } |
        Sort-Object { [int]($_.Name.Substring(1)) }
    if (-not $versionDirs) {
        Write-Error "Pack '$packName' has no installable versions yet. See packs/$packName/PACK.md"
        exit 1
    }
    $packVersion = $versionDirs[-1].Name
}

$packVersionDir = Join-Path $packDir $packVersion
if (-not (Test-Path $packVersionDir)) {
    Write-Host "Unknown version '$packVersion' for pack '$packName'. Available:"
    Get-ChildItem -Path $packDir -Directory |
        Where-Object { $_.Name -match '^v[0-9]+$' } |
        ForEach-Object { Write-Host "  $($_.Name)" }
    exit 1
}

$claudeTemplateRel = 'do-work/templates/CLAUDE.md.template'
$claudeTemplatePath = Join-Path $packVersionDir $claudeTemplateRel
if (-not (Test-Path $claudeTemplatePath)) {
    Write-Error "Pack '$packName@$packVersion' is missing required $claudeTemplateRel"
    exit 1
}

$target = Resolve-Path -Path $NewProjectDir -ErrorAction SilentlyContinue
if (-not $target) {
    Write-Host "Creating target directory: $NewProjectDir"
    New-Item -ItemType Directory -Path $NewProjectDir -Force | Out-Null
    $target = Resolve-Path -Path $NewProjectDir
}

# Guard against pack mixing. The installer never removes files, so replacing
# an installed pack with a different one orphans the first pack's
# uniquely-named agents (still discoverable and spawnable by Claude Code) and
# silently swaps same-named agents (ratchet.md, reviewer.md, git-workflow.md,
# do-work-run) between incompatible toolchains and ratchet dimension sets.
$existingPackFile = Join-Path $target '.claude/.pack'
if (Test-Path $existingPackFile) {
    $existingPackName = $null
    $existingPackVersion = $null
    Get-Content $existingPackFile | ForEach-Object {
        if ($_ -match '^pack:\s*(.+)$') { $existingPackName = $Matches[1].Trim() }
        if ($_ -match '^version:\s*(.+)$') { $existingPackVersion = $Matches[1].Trim() }
    }

    if ($existingPackName -and $existingPackName -ne $packName) {
        $oldPackVersionDir = Join-Path $sourceRoot "packs/$existingPackName/$existingPackVersion"
        $orphaned = @()
        if (Test-Path $oldPackVersionDir) {
            $oldFiles = Get-ChildItem -Path $oldPackVersionDir -Recurse -File |
                ForEach-Object { $_.FullName.Substring($oldPackVersionDir.Length).TrimStart('\', '/') }
            $newFiles = Get-ChildItem -Path $packVersionDir -Recurse -File |
                ForEach-Object { $_.FullName.Substring($packVersionDir.Length).TrimStart('\', '/') }
            $newFilesSet = [System.Collections.Generic.HashSet[string]]::new([string[]] $newFiles)
            $orphaned = $oldFiles | Where-Object { -not $newFilesSet.Contains($_) } | Sort-Object
        }

        if (-not $AllowPackSwitch) {
            Write-Host "Target was installed with pack '$existingPackName@$existingPackVersion'. Requested pack is '$packName@$packVersion'."
            Write-Host "Refusing: installing a different pack over an existing install orphans the previous pack's files - Claude Code still discovers and can spawn orphaned agents by their frontmatter 'name:', and same-named agents (ratchet.md, reviewer.md, git-workflow.md, the do-work-run command) get silently swapped between incompatible toolchains and ratchet dimension sets."
            Write-Host ""
            if ($orphaned.Count -gt 0) {
                Write-Host "$($orphaned.Count) file(s) unique to '$existingPackName@$existingPackVersion' would be orphaned:"
                $orphaned | ForEach-Object { Write-Host "  - $_" }
            } else {
                Write-Host "Could not enumerate the previous pack's overlay - packs/$existingPackName/$existingPackVersion is no longer present in this scaffold checkout."
            }
            Write-Host ""
            Write-Host "Re-run with -AllowPackSwitch to proceed anyway."
            exit 1
        }

        Write-Host "Switching pack: '$existingPackName@$existingPackVersion' -> '$packName@$packVersion' (-AllowPackSwitch supplied)."
        if ($orphaned.Count -gt 0) {
            Write-Host "$($orphaned.Count) file(s) unique to '$existingPackName@$existingPackVersion' will be orphaned:"
            $orphaned | ForEach-Object { Write-Host "  - $_" }
        }
        Write-Host ""
    }
}

Write-Host "Source: $sourceRoot"
Write-Host "Pack:   $packName@$packVersion"
Write-Host "Target: $target"
Write-Host ""

$copied  = @()
$skipped = @()

$claudeTemplateRelSep = $claudeTemplateRel -replace '/', [IO.Path]::DirectorySeparatorChar

function Copy-Tree {
    param([string] $SourcePath)

    Get-ChildItem -Path $SourcePath -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($SourcePath.Length).TrimStart('\', '/')
        $relNorm  = $relative -replace '/', [IO.Path]::DirectorySeparatorChar

        if ($relNorm -eq $claudeTemplateRelSep) {
            return
        }

        $destPath = Join-Path $target $relative
        $destDir  = Split-Path -Parent $destPath
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        if ((Test-Path $destPath) -and -not $Force) {
            $script:skipped += $relative
            return
        }

        Copy-Item -Path $_.FullName -Destination $destPath -Force
        $script:copied += $relative
    }
}

Copy-Tree -SourcePath $commonRoot
Copy-Tree -SourcePath $packVersionDir

# Special-case: install CLAUDE.md.template from the chosen pack to <target>/CLAUDE.md.
$claudeDest = Join-Path $target 'CLAUDE.md'
if ((Test-Path $claudeDest) -and -not $Force) {
    $skipped += 'CLAUDE.md'
} else {
    Copy-Item -Path $claudeTemplatePath -Destination $claudeDest -Force
    $copied += 'CLAUDE.md'
}

# Continuity layer (continuity/ in this repo, rules in
# common/.claude/conventions/continuity-protocol.md). Mirrors install.sh:
# files/ copies skip existing files (-Force overwrites scaffold-owned ones,
# never docs/ or .gates/), merge/ appends only what is missing, and
# docs/STATE.md is rendered only when absent. Text is written as UTF-8
# without BOM and with LF line endings so the sh scripts keep working.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false

function Write-Lf {
    param([string] $Path, [string] $Text)
    [IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $utf8NoBom)
}

function Merge-Lines {
    param([string] $Src, [string] $Rel, [string] $Mode)
    $Dest = Join-Path $target $Rel
    $rel = $Rel
    if (-not (Test-Path $Dest)) {
        Write-Lf $Dest ([IO.File]::ReadAllText($Src))
        $script:copied += $rel
        return
    }
    $existing = @(Get-Content -Path $Dest)
    $out = New-Object System.Collections.Generic.List[string]
    $pending = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -Path $Src)) {
        if ($line -eq '') { continue }
        if ($line.StartsWith('#')) { $pending.Add($line); continue }
        if ($Mode -eq 'firstword') {
            $key = ($line -split ' ')[0]
            $present = @($existing | Where-Object { $_ -match ('^' + [regex]::Escape($key) + '( |$)') }).Count -gt 0
        } else {
            $present = $existing -contains $line
        }
        if ($present) { $pending.Clear(); continue }
        $out.AddRange($pending); $pending.Clear(); $out.Add($line)
    }
    if ($out.Count -eq 0) { return }
    $text = [IO.File]::ReadAllText($Dest)
    if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { $text += "`n" }
    $added = @($out | Where-Object { -not $_.StartsWith('#') }).Count
    Write-Lf $Dest ($text + "# skaff continuity`n" + (($out -join "`n") + "`n"))
    $script:copied += "$rel (merged $added line(s))"
}

function Install-Continuity {
    $cdir = Join-Path $sourceRoot 'continuity'
    if (-not (Test-Path $cdir)) { return }
    $filesRoot = (Resolve-Path (Join-Path $cdir 'files')).Path

    if (-not $script:Human) {
        $email = (git -C $target config user.email 2>$null)
        if (-not $email) { $email = (git config user.email 2>$null) }
        if ($email) { $script:Human = 'human:' + ($email.Trim() -split '@')[0] }
    }

    $script:indexNew = $false
    Get-ChildItem -Path $filesRoot -Recurse -File -Force | ForEach-Object {
        $rel = $_.FullName.Substring($filesRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        $dest = Join-Path $target $rel
        $destDir = Split-Path -Parent $dest
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        if (Test-Path $dest) {
            $protected = $rel -like 'docs/*' -or $rel -like '.gates/*'
            if (-not $Force -or $protected) { $script:skipped += $rel; return }
        }
        if ($rel -eq 'docs/decisions/index.md') { $script:indexNew = $true }
        $text = [IO.File]::ReadAllText($_.FullName)
        if ($rel -eq 'scripts/lib.sh' -and $script:Human) {
            $text = $text.Replace('@@CONTINUITY_HUMAN@@', $script:Human)
        }
        Write-Lf $dest $text
        if ((Get-Command chmod -ErrorAction SilentlyContinue) -and ($rel -like '*.sh' -or $rel -like '.githooks/*') -and $rel -ne 'scripts/lib.sh') {
            chmod +x $dest
        }
        $script:copied += $rel
    }

    $adrs = @(Get-ChildItem -Path (Join-Path $target 'docs/decisions') -Filter '[0-9][0-9][0-9][0-9]-*.md' -ErrorAction SilentlyContinue)
    if ($script:indexNew -and $adrs.Count -gt 0) {
        if (Get-Command sh -ErrorAction SilentlyContinue) {
            $env:CLAUDE_PROJECT_DIR = $target
            sh (Join-Path $target 'scripts/adr-index.sh')
            Remove-Item Env:\CLAUDE_PROJECT_DIR
        } else {
            Write-Warning 'Existing ADRs found: run scripts/adr-index.sh to regenerate docs/decisions/index.md'
        }
    }

    Merge-Lines (Join-Path $cdir 'merge/gitignore') '.gitignore' 'exact'
    Merge-Lines (Join-Path $cdir 'merge/gitattributes') '.gitattributes' 'exact'
    Merge-Lines (Join-Path $cdir 'merge/tool-versions') '.tool-versions' 'firstword'

    # .claude/settings.json: add each hook group whose command is not already configured.
    $srcSettings = Join-Path $cdir 'merge/settings.json'
    $settings = Join-Path $target '.claude/settings.json'
    if (-not (Test-Path $settings)) {
        Write-Lf $settings ([IO.File]::ReadAllText($srcSettings))
        $script:copied += '.claude/settings.json'
    } else {
        $dst = [IO.File]::ReadAllText($settings) | ConvertFrom-Json
        $src = [IO.File]::ReadAllText($srcSettings) | ConvertFrom-Json
        if (-not $dst.PSObject.Properties['hooks']) {
            $dst | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
        }
        $changed = $false
        foreach ($evt in $src.hooks.PSObject.Properties) {
            $have = @()
            if ($dst.hooks.PSObject.Properties[$evt.Name]) { $have = @($dst.hooks.($evt.Name)) }
            $cmds = @($have | ForEach-Object { $_.hooks } | ForEach-Object { $_.command })
            $add = @($evt.Value | Where-Object { @($_.hooks | Where-Object { $cmds -notcontains $_.command }).Count -gt 0 })
            if ($add.Count -eq 0) { continue }
            $new = @($have) + $add
            if ($dst.hooks.PSObject.Properties[$evt.Name]) { $dst.hooks.($evt.Name) = $new }
            else { $dst.hooks | Add-Member -NotePropertyName $evt.Name -NotePropertyValue $new }
            $changed = $true
        }
        if ($changed) {
            Write-Lf $settings (($dst | ConvertTo-Json -Depth 20) + "`n")
            $script:copied += '.claude/settings.json (merged hooks)'
        }
    }

    # docs/STATE.md: rendered once, never overwritten.
    $state = Join-Path $target 'docs/STATE.md'
    if (Test-Path $state) {
        $script:skipped += 'docs/STATE.md'
    } else {
        $repo = Split-Path -Leaf $target
        $nowUtc = (Get-Date).ToUniversalTime()
        $p = $Purpose
        if (-not $p) { $p = "Replace with one sentence on what $repo is for." }
        $h = $script:Human
        if (-not $h) { $h = 'human:unknown' }
        $text = [IO.File]::ReadAllText((Join-Path $cdir 'templates/STATE.md.template'))
        $text = $text.Replace('@@REPO@@', $repo).Replace('@@DATE@@', $nowUtc.ToString('yyyy-MM-dd')).
            Replace('@@STALE_AFTER@@', $nowUtc.AddDays(14).ToString('yyyy-MM-dd')).
            Replace('@@GENERATED_AT@@', $nowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')).
            Replace('@@PACK@@', "$packName@$packVersion").Replace('@@PURPOSE@@', $p.Replace('"', '')).
            Replace('@@HUMAN@@', $h)
        $docsDir = Join-Path $target 'docs'
        if (-not (Test-Path $docsDir)) { New-Item -ItemType Directory -Path $docsDir -Force | Out-Null }
        Write-Lf $state $text
        $script:copied += 'docs/STATE.md'
    }

    if (-not $script:Human) {
        Write-Warning 'No -Human and no git user.email; set HUMAN in scripts/lib.sh before human gates.'
    }
}

if (-not $NoContinuity) {
    Install-Continuity
}

# Write pack identity sentinel.
$packSentinel = Join-Path $target '.claude/.pack'
$sentinelDir = Split-Path -Parent $packSentinel
if (-not (Test-Path $sentinelDir)) {
    New-Item -ItemType Directory -Path $sentinelDir -Force | Out-Null
}
$scaffoldCommit = try {
    (git -C $sourceRoot rev-parse --short HEAD 2>$null).Trim()
} catch { 'unknown' }
if (-not $scaffoldCommit) { $scaffoldCommit = 'unknown' }
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
@"
pack: $packName
version: $packVersion
installed_at: $timestamp
scaffold_commit: $scaffoldCommit
"@ | Set-Content -Path $packSentinel -Encoding utf8

Write-Host "Copied $($copied.Count) file(s):"
$copied | ForEach-Object { Write-Host "  + $_" }

if ($skipped.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped $($skipped.Count) existing file(s) - re-run with -Force to overwrite:"
    $skipped | ForEach-Object { Write-Host "  - $_" }
}

Write-Host ""
Write-Host "Pack identity written to .claude/.pack"
Write-Host ""
Write-Host "Done. Next steps:"
Write-Host "  1. cd $target"
Write-Host "  2. Review CLAUDE.md and .claude/conventions/"
Write-Host "  3. git add . && git commit -m 'chore: bootstrap claude agent scaffold'"
if (-not $NoContinuity) {
    Write-Host "  4. sh scripts/bootstrap.sh   (core.hooksPath, tool pins in .tool-versions, vale sync)"
    Write-Host "  5. git switch -c chore/continuity; sh scripts/gate.sh A1   (runs scripts/selftest.sh)"
    Write-Host "  6. set A1 status: done in docs/STATE.md, commit with trailer 'Closes-Item: A1'"
}
