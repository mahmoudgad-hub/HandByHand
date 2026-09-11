# Stamp the owner line onto a Markdown document.
#
# RUN IT FROM INSIDE POWERSHELL, with the call operator and an explicit array:
#
#   & .\scripts\stamp-doc-owner.ps1 -Owner "tester" -Files @("tests\test-cases\*.md","tests\README.md") -WhatIf
#   & .\scripts\stamp-doc-owner.ps1 -Owner "back end" -Files @("api\README.md")
#
# A bare comma list works too from inside PowerShell. @() is preferred
# because it puts the intent in the line instead of relying on a parsing
# rule - which is exactly the rule that breaks under -File below.
#
# CHECKING YOUR WORK: read it back with -Encoding UTF8.
#
#   Get-Content docs\INDEX.md -TotalCount 6 -Encoding UTF8
#
# Without that switch Windows PowerShell 5.1 decodes the file in the system
# ANSI codepage and prints the Arabic as mojibake - over a file that is
# perfectly correct on disk. It reads as "the script corrupted my document"
# and it is the console, not the file. Confirm with the bytes before you
# revert anything: a correct Arabic line starts 216,167 / 217,132 ... , not
# 195,152. The screen is not the file, in both directions.
#
# NOT `powershell -File ... -Files "a","b"`. That form hands the whole comma
# list to -Files as ONE string, it matches nothing, and the run ends
# "0 file(s), nothing written" with exit code 0 - which reads as "nothing
# needed stamping" and is the opposite. The script now refuses that shape by
# name, and exits non-zero when it stamps nothing at all: a stamp run that
# stamped no file did not succeed. `powershell -File` with a SINGLE pattern
# is fine.
#
# Ownership lives in docs/OWNERS.md. This puts it where it is read: the top
# of the file itself, under the title. A registry alone is a rule you have
# to go and look up, and a rule you look up is a rule you skip.
#
# STAMP ONLY THE FILES YOU OWN. That is the whole policy, and a script that
# makes it easy to stamp everything makes it easy to break it. -WhatIf
# prints what would change and writes nothing.
#
# Idempotent: re-running replaces the existing stamp rather than stacking a
# second one, so a change of owner is one more run, not a hand edit.
#
# KEEP THIS FILE SAVED AS UTF-8 WITH BOM. Windows PowerShell 5.1 reads a
# BOM-less .ps1 in the system ANSI codepage, so the Arabic literals below
# arrive as mojibake and the parser dies on "Unexpected token" pointing at
# lines that are perfectly valid. The error never mentions encoding. Any
# editor that strips the BOM breaks this script without touching its logic.

param(
  [Parameter(Mandatory=$true)][string]$Owner,
  [Parameter(Mandatory=$true)][string[]]$Files,
  [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# powershell -File does NOT split a comma-separated argument into an array:
# -Files "a\*.md","b.md" arrives as the single string 'a\*.md,b.md', matches
# nothing, and the run ends "0 file(s), nothing written" with exit code 0.
# That reads as "nothing needed stamping" and it is the opposite. Refuse it
# by name rather than warn - a warning in a green run is a warning nobody
# reads.
foreach ($p in $Files) {
  if ($p -like '*,*') {
    Write-Error @"
-Files got one string containing a comma:
    $p

`powershell -File` passes a comma list as ONE argument. Run it from inside
PowerShell instead, where the comma really builds an array:

    & .\scripts\stamp-doc-owner.ps1 -Owner "$Owner" -Files "a\*.md","b.md"

Or pass a single pattern per run.
"@
    exit 2
  }
}

# The marker is what makes this idempotent. Never change it without a
# migration for the files already carrying it.
$marker = '<!-- doc-owner -->'

$changed = 0
$skipped = 0

foreach ($pattern in $Files) {
  $matched = @(Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue)
  if ($matched.Count -eq 0) { Write-Warning "no match: $pattern"; continue }

  foreach ($f in $matched) {
    if ($f.Extension -ne '.md') { Write-Warning "not markdown, skipped: $($f.Name)"; $skipped++; continue }

    # Read as UTF-8 explicitly. The default here is the ANSI codepage and
    # it turns Arabic into mojibake on write-back.
    $lines = [System.IO.File]::ReadAllLines($f.FullName, [System.Text.Encoding]::UTF8)

    # Relative path back to docs/OWNERS.md, so the link works from wherever
    # the file sits. Uri.MakeRelativeUri does the segment counting.
    $docsOwners = Join-Path $PSScriptRoot '..\docs\OWNERS.md'
    $docsOwners = [System.IO.Path]::GetFullPath($docsOwners)
    $from = New-Object System.Uri($f.FullName)
    $to   = New-Object System.Uri($docsOwners)
    $rel  = [System.Uri]::UnescapeDataString($from.MakeRelativeUri($to).ToString())

    $stamp = @(
      $marker
      "> **المالك:** $Owner — **هو وحده من يكتب في هذه الوثيقة.**"
      "> لاحظت خطأً؟ **راسله ولا تصلحه بنفسك** — راجع [`OWNERS.md`]($rel)."
      $marker
    )

    # Drop any previous stamp, marker lines included.
    $out = New-Object System.Collections.Generic.List[string]
    $inOld = $false
    $hadOld = $false
    foreach ($l in $lines) {
      if ($l.Trim() -eq $marker) {
        if ($inOld) { $inOld = $false } else { $inOld = $true; $hadOld = $true }
        continue
      }
      if (-not $inOld) { $out.Add($l) }
    }

    # Place it under the first H1 so the title still reads first. A file
    # with no H1 gets it at the very top.
    $insertAt = 0
    for ($i = 0; $i -lt $out.Count; $i++) {
      if ($out[$i] -match '^#\s') { $insertAt = $i + 1; break }
    }

    $final = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $insertAt; $i++) { $final.Add($out[$i]) }
    if ($insertAt -gt 0) { $final.Add('') }
    foreach ($s in $stamp) { $final.Add($s) }
    # Blank line after the stamp: without it the next paragraph butts against
    # the closing comment and some renderers fold the two together.
    $final.Add('')
    for ($i = $insertAt; $i -lt $out.Count; $i++) {
      # Avoid leaving a double blank line where the old stamp was.
      if ($i -eq $insertAt -and $out[$i].Trim() -eq '') { continue }
      $final.Add($out[$i])
    }

    $verb = 'stamped'
    if ($hadOld) { $verb = 're-stamped' }

    if ($WhatIf) {
      Write-Output "would be $verb : $($f.FullName.Replace((Get-Location).Path + '\','')) -> $Owner"
    } else {
      [System.IO.File]::WriteAllLines($f.FullName, $final, (New-Object System.Text.UTF8Encoding $false))
      Write-Output "$verb : $($f.FullName.Replace((Get-Location).Path + '\','')) -> $Owner"
    }
    $changed++
  }
}

Write-Output ""
if ($WhatIf) { Write-Output "$changed file(s) would change, $skipped skipped. Nothing was written." }
else         { Write-Output "$changed file(s) stamped, $skipped skipped." }

# A stamp run that stamped nothing did not succeed - it matched nothing, and
# the caller believes their files are stamped. Same shape as the deletion
# that removes zero rows and reports success.
if ($changed -eq 0) {
  Write-Error "nothing matched - no file was stamped. Check the paths."
  exit 1
}
