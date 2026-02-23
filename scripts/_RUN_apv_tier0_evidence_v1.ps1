param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$m){ throw $m }

function Ensure-Dir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ Die "Ensure-Dir: empty path" }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
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

function Sha256HexBytes([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $h = $sha.ComputeHash($Bytes)
    $sb = New-Object System.Text.StringBuilder
    foreach($b in $h){ [void]$sb.Append($b.ToString("x2")) }
    $sb.ToString()
  } finally { $sha.Dispose() }
}

function Sha256HexFile([string]$Path){
  Sha256HexBytes ([System.IO.File]::ReadAllBytes($Path))
}

$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRootAbs "scripts"

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

# Parse-gate ALL product scripts first (fail-fast)
$ps1s = Get-ChildItem -LiteralPath $ScriptsDir -Filter *.ps1 -File
foreach($f in $ps1s){
  Parse-GateFile $f.FullName
}

# Evidence bundle root
$stamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$evRoot = Join-Path $RepoRootAbs ("proofs\receipts\apv_tier0_evidence\" + $stamp)
Ensure-Dir $evRoot

$stdoutPath = Join-Path $evRoot "stdout.txt"
$stderrPath = Join-Path $evRoot "stderr.txt"
$metaPath   = Join-Path $evRoot "run_meta.json"
$shaPath    = Join-Path $evRoot "sha256sums.txt"

# Run selftest and capture stdout/stderr deterministically
$self = Join-Path $ScriptsDir "_selftest_apv_v1.ps1"
Parse-GateFile $self

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $PSExe
$psi.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -RepoRoot "{1}"' -f $self,$RepoRootAbs)
$psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError  = $true
$psi.CreateNoWindow = $true

$p = New-Object System.Diagnostics.Process
$p.StartInfo = $psi

[void]$p.Start()
$so = $p.StandardOutput.ReadToEnd()
$se = $p.StandardError.ReadToEnd()
$p.WaitForExit()

Write-Utf8NoBomLf $stdoutPath $so
Write-Utf8NoBomLf $stderrPath $se

if($p.ExitCode -ne 0){
  Die ("SELFTEST_FAIL: exit " + $p.ExitCode)
}

# Meta (minimal, deterministic keys via manual JSON text)
$meta = @(
'{',
'  "schema": "apv.evidence_run_meta.v1",',
'  "tool": "_RUN_apv_tier0_evidence_v1",',
('  "timestamp_local": "' + $stamp + '",'),
('  "repo_root": "' + ($RepoRootAbs -replace "\\","\\") + '",'),
('  "exit_code": ' + [string]$p.ExitCode),
'}'
) -join "`n"
Write-Utf8NoBomLf $metaPath $meta

# sha256sums for evidence bundle (exclude sha256sums.txt itself)
$files = Get-ChildItem -LiteralPath $evRoot -File | Where-Object { $_.Name -ne "sha256sums.txt" } | Sort-Object Name
$lines = New-Object System.Collections.Generic.List[string]
foreach($f in $files){
  $hex = Sha256HexFile $f.FullName
  [void]$lines.Add(($hex + "  " + $f.Name))
}
Write-Utf8NoBomLf $shaPath (($lines.ToArray()) -join "`n")

Write-Output "APV_TIER0_EVIDENCE_OK"
