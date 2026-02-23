param()

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

function CanonJson-String([string]$s){
  if($null -eq $s){ return "null" }
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.Append('"')
  $chars = $s.ToCharArray()
  foreach($ch in $chars){
    $c = [int][char]$ch
    if($c -eq 34){ [void]$sb.Append('\"') }
    elseif($c -eq 92){ [void]$sb.Append('\\') }
    elseif($c -eq 8){ [void]$sb.Append('\b') }
    elseif($c -eq 12){ [void]$sb.Append('\f') }
    elseif($c -eq 10){ [void]$sb.Append('\n') }
    elseif($c -eq 13){ [void]$sb.Append('\r') }
    elseif($c -eq 9){ [void]$sb.Append('\t') }
    elseif($c -lt 32){
      [void]$sb.Append('\u')
      [void]$sb.Append($c.ToString("x4"))
    } else {
      [void]$sb.Append([char]$c)
    }
  }
  [void]$sb.Append('"')
  $sb.ToString()
}

function CanonJson-Bool([bool]$b){
  if($b){ "true" } else { "false" }
}

function CanonJson-Any([object]$v){
  if($null -eq $v){ return "null" }
  if($v -is [string]){ return (CanonJson-String $v) }
  if($v -is [bool]){ return (CanonJson-Bool $v) }
  if($v -is [int] -or $v -is [long]){ return ([string]$v) }
  if($v -is [hashtable]){ return (CanonJson-Obj $v) }
  if($v -is [object[]]){ return (CanonJson-Arr $v) }
  return (CanonJson-String ([string]$v))
}

function CanonJson-Obj([hashtable]$o){
  $keys = @($o.Keys | Sort-Object)
  $parts = New-Object System.Collections.Generic.List[string]
  foreach($k in $keys){
    $v = $o[$k]
    $kv = (CanonJson-String ([string]$k)) + ":" + (CanonJson-Any $v)
    [void]$parts.Add($kv)
  }
  "{" + (($parts.ToArray()) -join ",") + "}"
}

function CanonJson-Arr([object[]]$a){
  $parts = New-Object System.Collections.Generic.List[string]
  foreach($v in $a){
    [void]$parts.Add((CanonJson-Any $v))
  }
  "[" + (($parts.ToArray()) -join ",") + "]"
}

function Write-CanonJson([string]$Path,[hashtable]$Obj){
  $txt = (CanonJson-Obj $Obj)
  Write-Utf8NoBomLf $Path $txt
}

function Append-CanonNdjson([string]$Path,[hashtable]$Obj){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $line = (CanonJson-Obj $Obj)
  $line = ($line -replace "`r`n","`n") -replace "`r","`n"
  if($line.Contains("`n")){ Die "NDJSON must be single line" }
  $dir = Split-Path -Parent $Path
  if($dir){ Ensure-Dir $dir }
  [System.IO.File]::AppendAllText($Path,($line + "`n"),$enc)
}

function Normalize-Rel([string]$Rel){
  if([string]::IsNullOrWhiteSpace($Rel)){ Die "Bad relpath: empty" }
  $r = $Rel -replace "\\","/"
  if($r.StartsWith("/")){ Die "Bad relpath: absolute: $Rel" }
  if($r.Contains("..")){ Die "Bad relpath: traversal: $Rel" }
  if($r.Contains(":")){ Die "Bad relpath: drive/colon: $Rel" }
  $r
}

function Read-TextTrim([string]$Path){
  $t = [System.IO.File]::ReadAllText($Path,[System.Text.Encoding]::UTF8)
  $t = ($t -replace "`r`n","`n") -replace "`r","`n"
  $t.Trim()
}
