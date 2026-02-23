param(
  [Parameter(Mandatory=$true)][string]$PacketDir,
  [Parameter(Mandatory=$false)][string]$OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "_lib_apv_v1.ps1")

function Fail([string]$Reason,[hashtable]$Checks,[string]$Expected,[string]$Actual,[string]$PacketDirAbs,[string]$OutDirAbs){
  $res = @{
    schema = "apv.verification_result.v1"
    tool   = "apv_verify_v1"
    verdict = "INVALID"
    reason_code = $Reason
    packet_dir = $PacketDirAbs
    packet_id_expected = $Expected
    packet_id_actual = $Actual
    checks = $Checks
  }
  $outPath = Join-Path $OutDirAbs "verification_result.json"
  Write-CanonJson $outPath $res
  $receipt = @{
    schema = "apv.receipt.v1"
    tool = "apv_verify_v1"
    verdict = "INVALID"
    reason_code = $Reason
    packet_dir = $PacketDirAbs
    packet_id_expected = $Expected
    packet_id_actual = $Actual
  }
  $rcptPath = Join-Path (Join-Path (Split-Path -Parent $OutDirAbs) "receipts") "apv.ndjson"
  Append-CanonNdjson $rcptPath $receipt
  return $outPath
}

function Succeed([hashtable]$Checks,[string]$Expected,[string]$Actual,[string]$PacketDirAbs,[string]$OutDirAbs){
  $res = @{
    schema = "apv.verification_result.v1"
    tool   = "apv_verify_v1"
    verdict = "VALID"
    reason_code = "OK"
    packet_dir = $PacketDirAbs
    packet_id_expected = $Expected
    packet_id_actual = $Actual
    checks = $Checks
  }
  $outPath = Join-Path $OutDirAbs "verification_result.json"
  Write-CanonJson $outPath $res
  $receipt = @{
    schema = "apv.receipt.v1"
    tool = "apv_verify_v1"
    verdict = "VALID"
    reason_code = "OK"
    packet_dir = $PacketDirAbs
    packet_id_expected = $Expected
    packet_id_actual = $Actual
  }
  $rcptPath = Join-Path (Join-Path (Split-Path -Parent $OutDirAbs) "receipts") "apv.ndjson"
  Append-CanonNdjson $rcptPath $receipt
  return $outPath
}

$PacketDirAbs = (Resolve-Path -LiteralPath $PacketDir).Path

if([string]::IsNullOrWhiteSpace($OutDir)){
  $OutDirAbs = Join-Path $PacketDirAbs "proofs\out"
} else {
  $OutDirAbs = (Resolve-Path -LiteralPath $OutDir).Path
}

Ensure-Dir $OutDirAbs

$manifestPath = Join-Path $PacketDirAbs "manifest.json"
$packetIdPath = Join-Path $PacketDirAbs "packet_id.txt"
$shaPath      = Join-Path $PacketDirAbs "sha256sums.txt"

$checks = @{}
$expected = ""
$actual = ""

if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){
  $checks["manifest_present"] = $false
  Fail "MISSING_MANIFEST" $checks "" "" $PacketDirAbs $OutDirAbs | Out-Null
  exit 0
}
$checks["manifest_present"] = $true

if(-not (Test-Path -LiteralPath $packetIdPath -PathType Leaf)){
  $checks["packet_id_present"] = $false
  Fail "MISSING_PACKET_ID" $checks "" "" $PacketDirAbs $OutDirAbs | Out-Null
  exit 0
}
$checks["packet_id_present"] = $true

if(-not (Test-Path -LiteralPath $shaPath -PathType Leaf)){
  $checks["sha256sums_present"] = $false
  Fail "MISSING_SHA256SUMS" $checks "" "" $PacketDirAbs $OutDirAbs | Out-Null
  exit 0
}
$checks["sha256sums_present"] = $true

$manifestBytes = [System.IO.File]::ReadAllBytes($manifestPath)
$actual = Sha256HexBytes $manifestBytes
$expected = Read-TextTrim $packetIdPath

$checks["packet_id_recomputed"] = $actual
$checks["packet_id_expected"] = $expected

if($expected -ne $actual){
  Fail "PACKET_ID_MISMATCH" $checks $expected $actual $PacketDirAbs $OutDirAbs | Out-Null
  exit 0
}

# Verify sha256sums lines: "<hex>  <path>"
$lines = [System.IO.File]::ReadAllLines($shaPath,[System.Text.Encoding]::UTF8)
$linesN = @()
foreach($ln in $lines){
  $t = ($ln -replace "`r`n","`n") -replace "`r","`n"
  $t = $t.Trim()
  if($t.Length -eq 0){ continue }
  $linesN += $t
}
$checks["sha256_line_count"] = [int]$linesN.Count

$bad = $false
$badReason = ""
$badDetail = ""

foreach($ln in $linesN){
  # require at least 64 hex + two spaces
  if($ln.Length -lt 68){
    $bad = $true
    $badReason = "SHA256SUMS_FORMAT"
    $badDetail = $ln
    break
  }
  $hex = $ln.Substring(0,64).ToLowerInvariant()
  $sep = $ln.Substring(64,2)
  if($sep -ne "  "){
    $bad = $true
    $badReason = "SHA256SUMS_FORMAT"
    $badDetail = $ln
    break
  }
  $relRaw = $ln.Substring(66).Trim()
  try {
    $rel = Normalize-Rel $relRaw
  } catch {
    $bad = $true
    $badReason = "BAD_RELPATH"
    $badDetail = $relRaw
    break
  }
  # sha256sums.txt must not include itself
  if($rel -ieq "sha256sums.txt"){
    $bad = $true
    $badReason = "SHA256SUMS_INCLUDES_SELF"
    $badDetail = $ln
    break
  }

  $abs = Join-Path $PacketDirAbs $rel
  if(-not (Test-Path -LiteralPath $abs -PathType Leaf)){
    $bad = $true
    $badReason = "MISSING_FILE"
    $badDetail = $rel
    break
  }

  $calc = Sha256HexFile $abs
  if($calc -ne $hex){
    $bad = $true
    $badReason = "FILE_HASH_MISMATCH"
    $badDetail = ($rel + "|" + $hex + "|" + $calc)
    break
  }
}

$checks["sha256sums_verified"] = (-not $bad)

if($bad){
  $checks["failure_detail"] = $badDetail
  Fail $badReason $checks $expected $actual $PacketDirAbs $OutDirAbs | Out-Null
  exit 0
}

Succeed $checks $expected $actual $PacketDirAbs $OutDirAbs | Out-Null
exit 0

# APV_BAD_RELPATH_CATCH_V1
