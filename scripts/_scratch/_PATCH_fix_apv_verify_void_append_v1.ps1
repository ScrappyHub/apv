param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

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
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  if($errors -and $errors.Count -gt 0){
    $m = ($errors | ForEach-Object { $_.ToString() }) -join "`n"
    throw ("PARSE_FAIL: " + $Path + "`n" + $m)
  }
}

$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRootAbs "scripts\apv_verify_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ Die "Missing target: $Target" }

$enc = [System.Text.Encoding]::UTF8
$s = [System.IO.File]::ReadAllText($Target,$enc)
$s = ($s -replace "`r`n","`n") -replace "`r","`n"
$before = $s

# Fix invalid "[void]$linesN += $t" -> "$linesN += $t"
# We keep it minimal and deterministic: replace the exact token sequence at line start.
$s = [regex]::Replace(
  $s,
  '(?m)^\s*\[void\]\$linesN\s*\+=\s*\$t\s*$',
  '  $linesN += $t'
)

if($s -eq $before){ Die "PATCH_NOOP: no changes applied (pattern not found)" }

Write-Utf8NoBomLf $Target ($s.TrimEnd() + "`n")
Parse-GateFile $Target

Write-Output ("PATCH_OK: fixed void-assignment in " + $Target)
