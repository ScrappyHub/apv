param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

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

function Sha256HexBytes([byte[]]$Bytes){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try{
    $h = $sha.ComputeHash($Bytes)
    $sb = New-Object System.Text.StringBuilder
    foreach($b in $h){
      [void]$sb.Append($b.ToString("x2"))
    }
    $sb.ToString()
  } finally {
    $sha.Dispose()
  }
}

function Sha256HexFile([string]$Path){
  Sha256HexBytes ([System.IO.File]::ReadAllBytes($Path))
}

function Copy-Dir([string]$Src,[string]$Dst){
  Ensure-Dir $Dst
  $items = Get-ChildItem -LiteralPath $Src -Recurse -Force
  foreach($it in $items){
    $rel = $it.FullName.Substring($Src.Length).TrimStart("\","/")
    $out = Join-Path $Dst $rel
    if($it.PSIsContainer){
      Ensure-Dir $out
    } else {
      $odir = Split-Path -Parent $out
      if($odir){ Ensure-Dir $odir }
      Copy-Item -LiteralPath $it.FullName -Destination $out -Force
    }
  }
}

function Read-CanonVerdict([string]$Path){
  $txt = [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)
  # very small deterministic parse: locate "verdict":"X"
  $m = [regex]::Match($txt,'"verdict"\s*:\s*"(?<v>[^"]+)"')
  if(-not $m.Success){ Die "Could not parse verdict from: $Path" }
  $m.Groups["v"].Value
}

$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
$tvRoot = Join-Path $RepoRootAbs "test_vectors\apv_tier0_v1"
$srcValid = Join-Path $tvRoot "00_valid"
$srcTamper = Join-Path $tvRoot "01_payload_tamper"
$srcPid = Join-Path $tvRoot "02_packetid_tamper"
$srcMissing = Join-Path $tvRoot "03_missing_file"
$srcShaFmt = Join-Path $tvRoot "04_sha256sums_format"
$srcShaSelf = Join-Path $tvRoot "05_sha256sums_includes_self"
$srcTraversal = Join-Path $tvRoot "06_relpath_traversal"
$verify = Join-Path $RepoRootAbs "scripts\apv_verify_v1.ps1"
if(-not (Test-Path -LiteralPath $verify -PathType Leaf)){ Die "Missing verifier: $verify" }

# Build golden vectors deterministically
Ensure-Dir $tvRoot
Ensure-Dir $srcValid
Ensure-Dir (Join-Path $srcValid "payload")

Write-Utf8NoBomLf (Join-Path $srcValid "payload\hello.txt") "hello apv"

$manifestObj = @(
'{',
'  "schema": "apv.test_manifest.v1",',
'  "notes": "minimal test manifest; bytes are canonical as written (UTF-8 no BOM, LF)",',
'  "payload": {',
'    "hello_path": "payload/hello.txt"',
'  }',
'}'
) -join "`n"
Write-Utf8NoBomLf (Join-Path $srcValid "manifest.json") $manifestObj

$manifestBytes = [System.IO.File]::ReadAllBytes((Join-Path $srcValid "manifest.json"))
$packetId = Sha256HexBytes $manifestBytes
Write-Utf8NoBomLf (Join-Path $srcValid "packet_id.txt") $packetId

# sha256sums (exclude sha256sums.txt itself)
$hashManifest = Sha256HexFile (Join-Path $srcValid "manifest.json")
$hashPid      = Sha256HexFile (Join-Path $srcValid "packet_id.txt")
$hashHello    = Sha256HexFile (Join-Path $srcValid "payload\hello.txt")

$sha = @(
($hashManifest + "  " + "manifest.json"),
($hashPid      + "  " + "packet_id.txt"),
($hashHello    + "  " + "payload/hello.txt")
) -join "`n"
Write-Utf8NoBomLf (Join-Path $srcValid "sha256sums.txt") $sha

# Derive negative vectors by copying then tampering
if(Test-Path -LiteralPath $srcTamper -PathType Container){
  Remove-Item -LiteralPath $srcTamper -Recurse -Force
}
Copy-Dir $srcValid $srcTamper
Write-Utf8NoBomLf (Join-Path $srcTamper "payload\hello.txt") "hello apv TAMPERED"

if(Test-Path -LiteralPath $srcPid -PathType Container){
  Remove-Item -LiteralPath $srcPid -Recurse -Force
}
Copy-Dir $srcValid $srcPid
Write-Utf8NoBomLf (Join-Path $srcPid "packet_id.txt") ("0" * 64)

# --- additional negatives (APV_NEGATIVE_SUITE_V1) ---
# 03_missing_file
if(Test-Path -LiteralPath $srcMissing -PathType Container){ Remove-Item -LiteralPath $srcMissing -Recurse -Force }
Copy-Dir $srcValid $srcMissing
Remove-Item -LiteralPath (Join-Path $srcMissing "payload\hello.txt") -Force

# 04_sha256sums_format
if(Test-Path -LiteralPath $srcShaFmt -PathType Container){ Remove-Item -LiteralPath $srcShaFmt -Recurse -Force }
Copy-Dir $srcValid $srcShaFmt
Write-Utf8NoBomLf (Join-Path $srcShaFmt "sha256sums.txt") "not-a-valid-line"

# 05_sha256sums_includes_self
if(Test-Path -LiteralPath $srcShaSelf -PathType Container){ Remove-Item -LiteralPath $srcShaSelf -Recurse -Force }
Copy-Dir $srcValid $srcShaSelf
$hSelf = Sha256HexFile (Join-Path $srcShaSelf "sha256sums.txt")
$shaSelfTxt = @($hSelf + "  " + "sha256sums.txt") -join "`n"
Write-Utf8NoBomLf (Join-Path $srcShaSelf "sha256sums.txt") $shaSelfTxt

# 06_relpath_traversal
if(Test-Path -LiteralPath $srcTraversal -PathType Container){ Remove-Item -LiteralPath $srcTraversal -Recurse -Force }
Copy-Dir $srcValid $srcTraversal
$hM = Sha256HexFile (Join-Path $srcTraversal "manifest.json")
$hP = Sha256HexFile (Join-Path $srcTraversal "packet_id.txt")
$hH = Sha256HexFile (Join-Path $srcTraversal "payload\hello.txt")
$shaTrav = @(
  ($hM + "  " + "manifest.json"),
  ($hP + "  " + "packet_id.txt"),
  ($hH + "  " + "../payload/hello.txt")
) -join "`n"
Write-Utf8NoBomLf (Join-Path $srcTraversal "sha256sums.txt") $shaTrav
# Run verifier over each vector
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

function Run-Verify([string]$Dir,[string]$ExpectVerdict){
  $outDir = Join-Path $Dir "proofs\out"
  if(Test-Path -LiteralPath $outDir -PathType Container){
    Remove-Item -LiteralPath $outDir -Recurse -Force
  }
  Ensure-Dir $outDir

  $p = Start-Process -FilePath $PSExe -ArgumentList @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$verify,
    "-PacketDir",$Dir,
    "-OutDir",$outDir
  ) -NoNewWindow -Wait -PassThru

  if($p.ExitCode -ne 0){ Die ("Verifier nonzero exit: " + $p.ExitCode) }

  $resPath = Join-Path $outDir "verification_result.json"
  if(-not (Test-Path -LiteralPath $resPath -PathType Leaf)){ Die "Missing verification_result.json" }
  $v = Read-CanonVerdict $resPath
  if($v -ne $ExpectVerdict){
    $txt = [System.IO.File]::ReadAllText($resPath,[System.Text.Encoding]::UTF8)
    Die ("Expected verdict " + $ExpectVerdict + " got " + $v + "`n" + $txt)
  }
}

Run-Verify $srcValid "VALID"
Run-Verify $srcTamper "INVALID"
Run-Verify $srcPid "INVALID"
Run-Verify $srcMissing "INVALID"
Run-Verify $srcShaFmt "INVALID"
Run-Verify $srcShaSelf "INVALID"
Run-Verify $srcTraversal "INVALID"
Write-Output "SELFTEST_APV_OK"

# APV_NEGATIVE_SUITE_V1
