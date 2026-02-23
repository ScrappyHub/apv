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

function Parse-GateFile([string]$Path){
  $tokens=$null
  $errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if($errors -and $errors.Count -gt 0){
    $m = ($errors | ForEach-Object { $_.ToString() }) -join "`n"
    throw ("PARSE_FAIL: " + $Path + "`n" + $m)
  }
}

$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
Set-Location -LiteralPath $RepoRootAbs

# --- write .gitignore (UTF-8 no BOM + LF) ---
$gi = Join-Path $RepoRootAbs ".gitignore"
$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add("# APV .gitignore (Tier-0 hygiene)")
[void]$lines.Add("# Keep test_vectors committed; ignore generated proofs/receipts and scratch patchers")
[void]$lines.Add("")
[void]$lines.Add("# Generated evidence / receipts (reproducible, but not committed)")
[void]$lines.Add("proofs/")
[void]$lines.Add("**/proofs/")
[void]$lines.Add("")
[void]$lines.Add("# Scratch patchers (not product surface)")
[void]$lines.Add("")
[void]$lines.Add("# OS/editor noise")
[void]$lines.Add(".vscode/")
[void]$lines.Add("*.tmp")
[void]$lines.Add("*.log")
[void]$lines.Add("Thumbs.db")
[void]$lines.Add("Desktop.ini")
[void]$lines.Add("")
Write-Utf8NoBomLf $gi ((@($lines.ToArray()) -join "`n") + "`n")
Parse-GateFile $gi
Write-Output ("GITIGNORE_OK: " + $gi)

# --- stop tracking already-committed proofs/scratch (do NOT delete locally) ---
$paths = @("proofs","scripts/_scratch")
foreach($p in $paths){
  if(Test-Path -LiteralPath (Join-Path $RepoRootAbs $p)){
    & git rm -r --cached --ignore-unmatch $p | Out-Host
  }
}

# --- commit hygiene ---
& git add .gitignore | Out-Host
& git status | Out-Host
& git commit -m "APV: repo hygiene (.gitignore; untrack proofs + scratch)" | Out-Host
Write-Output "APV_HYGIENE_COMMIT_OK"

