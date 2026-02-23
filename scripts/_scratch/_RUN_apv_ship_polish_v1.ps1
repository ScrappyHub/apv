param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Die([string]$m){ throw $m }

$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location -LiteralPath $RepoRootAbs

# --- LICENSE (MIT) ---
$lic = Join-Path $RepoRootAbs "LICENSE"
if(-not (Test-Path -LiteralPath $lic -PathType Leaf)){
  $year = (Get-Date).Year
  $txt = @()
  $txt += "MIT License"
  $txt += ""
  $txt += ("Copyright (c) " + $year + " ScrappyHub")
  $txt += ""
  $txt += "Permission is hereby granted, free of charge, to any person obtaining a copy"
  $txt += "of this software and associated documentation files (the `"Software`"), to deal"
  $txt += "in the Software without restriction, including without limitation the rights"
  $txt += "to use, copy, modify, merge, publish, distribute, sublicense, and/or sell"
  $txt += "copies of the Software, and to permit persons to whom the Software is"
  $txt += "furnished to do so, subject to the following conditions:"
  $txt += ""
  $txt += "The above copyright notice and this permission notice shall be included in all"
  $txt += "copies or substantial portions of the Software."
  $txt += ""
  $txt += "THE SOFTWARE IS PROVIDED `"AS IS`", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR"
  $txt += "IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,"
  $txt += "FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE"
  $txt += "AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER"
  $txt += "LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,"
  $txt += "OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE"
  $txt += "SOFTWARE."
  Write-Utf8NoBomLf $lic ((@($txt) -join "`n") + "`n")
  Write-Output "LICENSE_WRITTEN"
} else { Write-Output "LICENSE_EXISTS" }

# sanity check: LICENSE is plain text (do NOT ParseFile it)
$raw = [System.IO.File]::ReadAllText($lic, (New-Object System.Text.UTF8Encoding($false)))
if([string]::IsNullOrWhiteSpace($raw)){ Die "LICENSE_EMPTY" }
if($raw -notmatch "(?m)^\s*MIT License\s*$"){ Die "LICENSE_BAD_HEADER" }
Write-Output "LICENSE_OK"

# --- Optional: minimal GitHub Actions CI (Windows PowerShell selftest) ---
$wfDir = Join-Path $RepoRootAbs ".github\workflows"
$wf = Join-Path $wfDir "ci.yml"
if(-not (Test-Path -LiteralPath $wf -PathType Leaf)){
  $y = @()
  $y += "name: ci"
  $y += ""
  $y += "on:"
  $y += "  push:"
  $y += "  pull_request:"
  $y += ""
  $y += "jobs:"
  $y += "  windows-selftest:"
  $y += "    runs-on: windows-latest"
  $y += "    steps:"
  $y += "      - uses: actions/checkout@v4"
  $y += "      - name: APV selftest (Windows PowerShell)"
  $y += "        shell: powershell"
  $y += "        run: |"
  $y += "          `$ErrorActionPreference = `"Stop`""
  $y += "          Set-StrictMode -Version Latest"
  $y += "          powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File scripts\_selftest_apv_v1.ps1 -RepoRoot `"`$PWD`""
  Write-Utf8NoBomLf $wf ((@($y) -join "`n") + "`n")
  Write-Output "CI_WORKFLOW_OK"
} else { Write-Output "CI_WORKFLOW_EXISTS" }

# --- Commit ---
& git add LICENSE .github/workflows/ci.yml | Out-Host
& git status | Out-Host
& git commit -m "APV: ship polish (LICENSE + CI)" | Out-Host

# --- Tag ---
$tag = "v0.1.0-tier0"
& git tag -a $tag -m "APV Tier-0 nucleus: verifier + selftest + evidence (GREEN)" | Out-Host
Write-Output ("TAG_OK: " + $tag)

# --- Push ---
& git push | Out-Host
& git push --tags | Out-Host
Write-Output "APV_SHIP_POLISH_GREEN"
