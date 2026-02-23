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
$enc = [System.Text.Encoding]::UTF8

$V = Join-Path $RepoRootAbs "scripts\apv_verify_v1.ps1"
if(-not (Test-Path -LiteralPath $V -PathType Leaf)){ Die "Missing: scripts\apv_verify_v1.ps1" }
$vs = [System.IO.File]::ReadAllText($V,$enc)
$vs = ($vs -replace "`r`n","`n") -replace "`r","`n"
if($vs.Contains("APV_BAD_RELPATH_CATCH_V1")){
  Write-Output "VERIFY_ALREADY_PATCHED: APV_BAD_RELPATH_CATCH_V1"
} else {
  $needle = '(?m)^\s*\$rel\s*=\s*Normalize-Rel\s+\$relRaw\s*$'
  $replLines = New-Object System.Collections.Generic.List[string]
  [void]$replLines.Add("  try {")
  [void]$replLines.Add("    $rel = Normalize-Rel $relRaw")
  [void]$replLines.Add("  } catch {")
  [void]$replLines.Add("    $bad = $true")
  [void]$replLines.Add("    $badReason = ""BAD_RELPATH""")
  [void]$replLines.Add("    $badDetail = $relRaw")
  [void]$replLines.Add("    break")
  [void]$replLines.Add("  }")
  $replacement = ($replLines.ToArray() -join "`n")
  $before = $vs
  $vs = [regex]::Replace($vs,$needle,$replacement)
  if($vs -eq $before){ Die "PATCH_VERIFY_NOOP: could not find Normalize-Rel assignment line" }
  $vs = $vs + "`n# APV_BAD_RELPATH_CATCH_V1`n"
  Write-Utf8NoBomLf $V ($vs.TrimEnd() + "`n")
  Parse-GateFile $V
  Write-Output "PATCH_OK: APV_BAD_RELPATH_CATCH_V1"
}

$T = Join-Path $RepoRootAbs "scripts\_selftest_apv_v1.ps1"
if(-not (Test-Path -LiteralPath $T -PathType Leaf)){ Die "Missing: scripts\_selftest_apv_v1.ps1" }
$ts = [System.IO.File]::ReadAllText($T,$enc)
$ts = ($ts -replace "`r`n","`n") -replace "`r","`n"
if($ts.Contains("APV_NEGATIVE_SUITE_V1")){
  Write-Output "SELFTEST_ALREADY_PATCHED: APV_NEGATIVE_SUITE_V1"
} else {
  $before = $ts
  $anchorPaths = '(?m)^\$srcPid\s*=\s*Join-Path\s+\$tvRoot\s+"02_packetid_tamper"\s*$'
  $pathsLines = New-Object System.Collections.Generic.List[string]
  [void]$pathsLines.Add('$srcPid = Join-Path $tvRoot "02_packetid_tamper"')
  [void]$pathsLines.Add('$srcMissing = Join-Path $tvRoot "03_missing_file"')
  [void]$pathsLines.Add('$srcShaFmt = Join-Path $tvRoot "04_sha256sums_format"')
  [void]$pathsLines.Add('$srcShaSelf = Join-Path $tvRoot "05_sha256sums_includes_self"')
  [void]$pathsLines.Add('$srcTraversal = Join-Path $tvRoot "06_relpath_traversal"')
  $pathsBlock = ($pathsLines.ToArray() -join "`n")
  $ts = [regex]::Replace($ts,$anchorPaths,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $pathsBlock })
  if($ts -eq $before){ Die "PATCH_SELFTEST_NOOP_A: could not add vector paths" }
  $before = $ts

  $anchorPidWrite = '(?m)^\s*Write-Utf8NoBomLf\s+\(Join-Path\s+\$srcPid\s+"packet_id\.txt"\)\s+\("0"\s*\*\s*64\)\s*$'
  $blk = New-Object System.Collections.Generic.List[string]
  [void]$blk.Add('Write-Utf8NoBomLf (Join-Path $srcPid "packet_id.txt") ("0" * 64)')
  [void]$blk.Add('')
  [void]$blk.Add('# --- additional negatives (APV_NEGATIVE_SUITE_V1) ---')
  [void]$blk.Add('# 03_missing_file: delete payload/hello.txt but keep sha256sums entry')
  [void]$blk.Add('if(Test-Path -LiteralPath $srcMissing -PathType Container){ Remove-Item -LiteralPath $srcMissing -Recurse -Force }')
  [void]$blk.Add('Copy-Dir $srcValid $srcMissing')
  [void]$blk.Add('Remove-Item -LiteralPath (Join-Path $srcMissing "payload\hello.txt") -Force')
  [void]$blk.Add('')
  [void]$blk.Add('# 04_sha256sums_format: break format (no "  " separator)')
  [void]$blk.Add('if(Test-Path -LiteralPath $srcShaFmt -PathType Container){ Remove-Item -LiteralPath $srcShaFmt -Recurse -Force }')
  [void]$blk.Add('Copy-Dir $srcValid $srcShaFmt')
  [void]$blk.Add('Write-Utf8NoBomLf (Join-Path $srcShaFmt "sha256sums.txt") "not-a-valid-line"')
  [void]$blk.Add('')
  [void]$blk.Add('# 05_sha256sums_includes_self: include sha256sums.txt')
  [void]$blk.Add('if(Test-Path -LiteralPath $srcShaSelf -PathType Container){ Remove-Item -LiteralPath $srcShaSelf -Recurse -Force }')
  [void]$blk.Add('Copy-Dir $srcValid $srcShaSelf')
  [void]$blk.Add('$hSelf = Sha256HexFile (Join-Path $srcShaSelf "sha256sums.txt")')
  [void]$blk.Add('$shaSelfTxt = @($hSelf + "  " + "sha256sums.txt") -join "`n"' )
  [void]$blk.Add('Write-Utf8NoBomLf (Join-Path $srcShaSelf "sha256sums.txt") $shaSelfTxt')
  [void]$blk.Add('')
  [void]$blk.Add('# 06_relpath_traversal: ../ in relpath -> INVALID (must not crash verifier)')
  [void]$blk.Add('if(Test-Path -LiteralPath $srcTraversal -PathType Container){ Remove-Item -LiteralPath $srcTraversal -Recurse -Force }')
  [void]$blk.Add('Copy-Dir $srcValid $srcTraversal')
  [void]$blk.Add('$hM = Sha256HexFile (Join-Path $srcTraversal "manifest.json")')
  [void]$blk.Add('$hP = Sha256HexFile (Join-Path $srcTraversal "packet_id.txt")')
  [void]$blk.Add('$hH = Sha256HexFile (Join-Path $srcTraversal "payload\hello.txt")')
  [void]$blk.Add('$shaTrav = @(')
  [void]$blk.Add('  ($hM + "  " + "manifest.json"),')
  [void]$blk.Add('  ($hP + "  " + "packet_id.txt"),')
  [void]$blk.Add('  ($hH + "  " + "../payload/hello.txt")')
  [void]$blk.Add(') -join "`n"' )
  [void]$blk.Add('Write-Utf8NoBomLf (Join-Path $srcTraversal "sha256sums.txt") $shaTrav')

  $block = ($blk.ToArray() -join "`n")
  $ts = [regex]::Replace($ts,$anchorPidWrite,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
  if($ts -eq $before){ Die "PATCH_SELFTEST_NOOP_B: could not inject negative builders" }
  $before = $ts

  $anchorRun = '(?m)^\s*Run-Verify\s+\$srcPid\s+"INVALID"\s*$'
  $runLines = New-Object System.Collections.Generic.List[string]
  [void]$runLines.Add('Run-Verify $srcPid "INVALID"')
  [void]$runLines.Add('Run-Verify $srcMissing "INVALID"')
  [void]$runLines.Add('Run-Verify $srcShaFmt "INVALID"')
  [void]$runLines.Add('Run-Verify $srcShaSelf "INVALID"')
  [void]$runLines.Add('Run-Verify $srcTraversal "INVALID"')
  $runBlock = ($runLines.ToArray() -join "`n")
  $ts = [regex]::Replace($ts,$anchorRun,[System.Text.RegularExpressions.MatchEvaluator]{ param($m) $runBlock })
  if($ts -eq $before){ Die "PATCH_SELFTEST_NOOP_C: could not extend Run-Verify calls" }

  $ts = $ts + "`n# APV_NEGATIVE_SUITE_V1`n"
  Write-Utf8NoBomLf $T ($ts.TrimEnd() + "`n")
  Parse-GateFile $T
  Write-Output "PATCH_OK: APV_NEGATIVE_SUITE_V1"
}

Write-Output "PATCH_DONE"
