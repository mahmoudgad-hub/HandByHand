# Render an Arabic Markdown document to an RTL PDF.
#
#   powershell -File scripts/md-to-pdf.ps1 -Md docs/x.md [-Pdf out.pdf] [-KeepHtml]
#
# Why a converter and not a hand-written HTML twin: the owner questionnaire
# has a .md and a .html that must be edited together, and "edit both" is how
# figma/preview.html went stale - it kept saying fourteen CRUD resources long
# after there were twenty-eight. The .md is the source here; the HTML is a
# build artefact and is deleted unless -KeepHtml.
#
# Chrome does the typesetting. It shapes Arabic and resolves bidi with the
# same engine the app runs on, which no PDF library that assembles Arabic
# itself gets right. --headless=new is required: the old mode exits 0 and
# writes nothing.
#
# This handles the Markdown this project actually writes - headings, tables,
# blockquotes, fenced code, bold, inline code, links, lists, rules. It is not
# a general parser and does not pretend to be.

param(
  [Parameter(Mandatory=$true)][string]$Md,
  [string]$Pdf,
  [switch]$KeepHtml
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Md)) { throw "no such file: $Md" }
$mdPath = (Resolve-Path $Md).Path
if (-not $Pdf) { $Pdf = [System.IO.Path]::ChangeExtension($mdPath, '.pdf') }

$chrome = @(
  "C:\Program Files\Google\Chrome\Application\chrome.exe",
  "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
  "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $chrome) { throw "no Chrome or Edge found - both render Arabic correctly, a PDF library may not" }

# ---------------------------------------------------------------- inline ---
function Convert-Inline([string]$t) {
  # Escape first so a literal < in the prose cannot open a tag.
  $t = $t -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'
  # Code before bold: **x** inside `code` must stay literal.
  $t = [regex]::Replace($t, '`([^`]+)`', '<code>$1</code>')
  $t = [regex]::Replace($t, '\*\*([^*]+)\*\*', '<strong>$1</strong>')
  $t = [regex]::Replace($t, '(?<![\*\w])\*([^*]+)\*(?!\w)', '<em>$1</em>')
  $t = [regex]::Replace($t, '\[([^\]]+)\]\(([^)]+)\)', '<a href="$2">$1</a>')
  # An ISO date is three LTR digit runs joined by neutral hyphens, so in an
  # RTL paragraph bidi reorders them and 2026-09-10 is displayed 10-09-2026.
  # Nothing warns; it just reads as the wrong date. Isolate it as LTR.
  $t = [regex]::Replace($t, '(?<![\d>-])(\d{4}-\d{2}-\d{2})(?![\d<-])', '<span dir="ltr">$1</span>')
  return $t
}

# ------------------------------------------------------------------ block ---
$lines = [System.IO.File]::ReadAllLines($mdPath, [System.Text.Encoding]::UTF8)
$out   = New-Object System.Text.StringBuilder
$title = [System.IO.Path]::GetFileNameWithoutExtension($mdPath)

$inCode  = $false
$inTable = $false
$quote   = New-Object System.Collections.Generic.List[string]
$list    = $null   # 'ul' or 'ol' or $null

function Close-Table { if ($script:inTable) { [void]$out.AppendLine('</table>'); $script:inTable = $false } }
function Close-List  { if ($script:list)   { [void]$out.AppendLine("</$($script:list)>"); $script:list = $null } }
function Flush-Quote {
  if ($script:quote.Count -eq 0) { return }
  [void]$out.AppendLine('<blockquote>')
  foreach ($q in $script:quote) {
    if ($q.Trim() -eq '') { [void]$out.AppendLine('<br>') }
    else { [void]$out.AppendLine('<p>' + (Convert-Inline $q) + '</p>') }
  }
  [void]$out.AppendLine('</blockquote>')
  $script:quote.Clear()
}

foreach ($raw in $lines) {
  $line = $raw.TrimEnd()

  # fenced code - passes through untouched, only escaped
  if ($line -match '^\s*```') {
    Flush-Quote; Close-Table; Close-List
    if ($inCode) { [void]$out.AppendLine('</pre>'); $inCode = $false }
    else { [void]$out.AppendLine('<pre>'); $inCode = $true }
    continue
  }
  if ($inCode) {
    [void]$out.AppendLine(($raw -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;'))
    continue
  }

  # blockquote - buffered so consecutive > lines become one block
  if ($line -match '^>\s?(.*)$') {
    Close-Table; Close-List
    $quote.Add($Matches[1])
    continue
  }
  Flush-Quote

  # table
  if ($line -match '^\s*\|') {
    Close-List
    $cells = $line.Trim().Trim('|') -split '(?<!\\)\|'
    # the |---|---| separator row carries no content
    $isSep = $true
    foreach ($c in $cells) { if ($c.Trim() -notmatch '^:?-{2,}:?$') { $isSep = $false } }
    if ($isSep) { continue }
    if (-not $inTable) { [void]$out.AppendLine('<table>'); $inTable = $true; $head = $true }
    $tag = 'td'
    if ($head) { $tag = 'th'; $head = $false }
    $row = '<tr>'
    foreach ($c in $cells) { $row += "<$tag>" + (Convert-Inline $c.Trim().Replace('\|','|')) + "</$tag>" }
    [void]$out.AppendLine($row + '</tr>')
    continue
  }
  Close-Table

  # horizontal rule
  if ($line -match '^\s*---+\s*$') { Close-List; [void]$out.AppendLine('<hr>'); continue }

  # headings
  if ($line -match '^(#{1,6})\s+(.*)$') {
    Close-List
    $n = $Matches[1].Length
    $txt = Convert-Inline $Matches[2]
    if ($n -eq 1 -and $title -eq [System.IO.Path]::GetFileNameWithoutExtension($mdPath)) {
      $title = ($Matches[2] -replace '[`*]','')
    }
    [void]$out.AppendLine("<h$n>$txt</h$n>")
    continue
  }

  # lists
  if ($line -match '^\s*[-*]\s+(.*)$') {
    if ($list -ne 'ul') { Close-List; [void]$out.AppendLine('<ul>'); $list = 'ul' }
    [void]$out.AppendLine('<li>' + (Convert-Inline $Matches[1]) + '</li>')
    continue
  }
  if ($line -match '^\s*\d+\.\s+(.*)$') {
    if ($list -ne 'ol') { Close-List; [void]$out.AppendLine('<ol>'); $list = 'ol' }
    [void]$out.AppendLine('<li>' + (Convert-Inline $Matches[1]) + '</li>')
    continue
  }

  if ($line.Trim() -eq '') { Close-List; continue }

  Close-List
  [void]$out.AppendLine('<p>' + (Convert-Inline $line) + '</p>')
}
Flush-Quote; Close-Table; Close-List
if ($inCode) { [void]$out.AppendLine('</pre>') }

# ------------------------------------------------------------------ shell ---
$css = @'
  @page { size: A4; margin: 14mm 12mm; }
  * { box-sizing: border-box; }
  html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  body { font-family:"Segoe UI",Tahoma,Arial,sans-serif; font-size:10pt; line-height:1.75;
         color:#16202b; margin:0; }
  h1 { font-size:19pt; color:#0f4c81; margin:0 0 6px; border-bottom:2px solid #0f4c81;
       padding-bottom:6px; }
  h2 { font-size:14.5pt; color:#fff; background:#0f4c81; padding:7px 12px; border-radius:4px;
       margin:22px 0 8px; page-break-after:avoid; }
  h3 { font-size:12pt; color:#0f4c81; border-right:4px solid #0f4c81; padding-right:9px;
       margin:16px 0 6px; page-break-after:avoid; }
  h4 { font-size:10.5pt; color:#2c4a63; margin:12px 0 4px; page-break-after:avoid; }
  p { margin:6px 0; }
  hr { border:0; border-top:1px solid #dde4ec; margin:16px 0; }
  table { width:100%; border-collapse:collapse; margin:9px 0 12px; font-size:9.5pt;
          page-break-inside:avoid; }
  th { background:#e8eef5; color:#0f4c81; font-weight:600; text-align:right; padding:6px 8px;
       border:1px solid #b9cbdc; font-size:9pt; }
  td { border:1px solid #c8d4e0; padding:6px 8px; vertical-align:top; }
  tr:nth-child(even) td { background:#fafbfd; }
  blockquote { background:#fff8e6; border-right:4px solid #d9a441; padding:7px 12px;
               margin:10px 0; font-size:9.5pt; page-break-inside:avoid; }
  blockquote p { margin:4px 0; }
  blockquote strong { color:#8a5d00; }
  pre { background:#f4f7fa; border:1px solid #d5e0ea; border-right:4px solid #7f9bb5;
        padding:9px 12px; margin:10px 0; font-family:Consolas,"Courier New",monospace;
        font-size:9pt; line-height:1.5; direction:ltr; text-align:left; overflow-x:auto;
        white-space:pre; page-break-inside:avoid; }
  code { font-family:Consolas,"Courier New",monospace; background:#eef2f6; padding:1px 4px;
         border-radius:3px; font-size:9pt; direction:ltr; display:inline-block;
         unicode-bidi:embed; }
  pre code { background:none; padding:0; }
  a { color:#0f4c81; text-decoration:none; border-bottom:1px dotted #9db4c9; }
  ul,ol { margin:6px 0; padding-right:22px; }
  li { margin:2px 0; }
  strong { color:#16202b; }
'@

$html = "<!DOCTYPE html><html lang=`"ar`" dir=`"rtl`"><head><meta charset=`"utf-8`">" +
        "<title>$title</title><style>$css</style></head><body>" +
        $out.ToString() + "</body></html>"

$htmlPath = [System.IO.Path]::ChangeExtension($Pdf, '.html')
[System.IO.File]::WriteAllText($htmlPath, $html, (New-Object System.Text.UTF8Encoding $true))

if (Test-Path $Pdf) { Remove-Item $Pdf -Force }

# Not "file:///" + path. This project lives under a path with spaces AND
# parentheses - "...\Hand By Hand(new)\..." - and an unencoded space makes
# Chrome read one argument as several: "Multiple targets are not supported
# in headless mode", which reads like a flag problem and is not one.
# System.Uri percent-encodes it correctly, Arabic segments included.
$uri = ([System.Uri]$htmlPath).AbsoluteUri
# The output path has spaces too, and Start-Process does not quote for you:
# --print-to-pdf=C:\...\Hand By Hand(new)\...  arrives as three arguments and
# Chrome reports the same "Multiple targets" error. Quote it explicitly.
Start-Process -FilePath $chrome -Wait -NoNewWindow -ArgumentList @(
  "--headless=new","--disable-gpu","--no-sandbox","--no-pdf-header-footer",
  "--virtual-time-budget=20000",
  ('--print-to-pdf="{0}"' -f $Pdf),
  $uri
)

if (-not $KeepHtml) { Remove-Item $htmlPath -Force }

if (Test-Path $Pdf) {
  $kb = [math]::Round((Get-Item $Pdf).Length/1KB,1)
  Write-Output "$Pdf  ($kb KB)"
} else {
  throw "chrome produced no PDF"
}
