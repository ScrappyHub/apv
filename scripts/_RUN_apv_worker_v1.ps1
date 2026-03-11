param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir([string]$p){ if(-not (Test-Path -LiteralPath $p -PathType Container)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Write-Utf8NoBomLf([string]$Path,[string]$Text){ $dir=Split-Path -Parent $Path; if($dir){ Ensure-Dir $dir }; $t=$Text.Replace("`r`n","`n").Replace("`r","`n"); if(-not $t.EndsWith("`n")){ $t += "`n" }; [System.IO.File]::WriteAllText($Path,$t,(New-Object System.Text.UTF8Encoding($false))) }
function Read-Utf8([string]$p){ [System.IO.File]::ReadAllText($p,(New-Object System.Text.UTF8Encoding($false))) }
function Die([string]$m){ throw $m }
function Load-DotEnv([string[]]$Files){
  foreach($f in @($Files)){
    if(-not (Test-Path -LiteralPath $f -PathType Leaf)){ continue }
    foreach($ln in @((Read-Utf8 $f).Replace("`r`n","`n").Replace("`r","`n") -split "`n", -1)){
      if([string]::IsNullOrWhiteSpace($ln)){ continue }
      $t = $ln.Trim()
      if($t.StartsWith("#")){ continue }
      $eq = $t.IndexOf("=")
      if($eq -lt 1){ continue }
      $k = $t.Substring(0,$eq).Trim()
      $v = $t.Substring($eq+1).Trim()
      if([string]::IsNullOrWhiteSpace($k)){ continue }
      if($v.Length -ge 2){
        $a = $v.Substring(0,1)
        $b = $v.Substring($v.Length-1,1)
        if(($a -eq '"' -and $b -eq '"') -or ($a -eq "'" -and $b -eq "'")){ $v = $v.Substring(1,$v.Length-2) }
      }
      $existing = [Environment]::GetEnvironmentVariable($k,"Process")
      if(-not [string]::IsNullOrEmpty($existing)){ continue }
      [Environment]::SetEnvironmentVariable($k,$v,"Process")
    }
  }
}

$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
$ApiRoot     = Join-Path $RepoRootAbs "apps\api"
$WorkerCjs   = Join-Path $ApiRoot "src\worker.cjs"
$WorkerJs    = Join-Path $ApiRoot "src\worker.js"

if(-not (Test-Path -LiteralPath $ApiRoot -PathType Container)){ Die ("MISSING_API_ROOT: " + $ApiRoot) }
if((Test-Path -LiteralPath $WorkerJs -PathType Leaf) -and (-not (Test-Path -LiteralPath $WorkerCjs -PathType Leaf))){
  Rename-Item -LiteralPath $WorkerJs -NewName "worker.cjs"
  Write-Output "WORKER_RENAME_OK"
} elseif(Test-Path -LiteralPath $WorkerCjs -PathType Leaf){
  Write-Output "WORKER_RENAME_SKIP_ALREADY_CJS"
} else {
  Die ("MISSING_WORKER: expected " + $WorkerCjs + " (or " + $WorkerJs + ")")
}

$envFiles = @(
  (Join-Path $ApiRoot ".env"),
  (Join-Path $ApiRoot ".env.local"),
  (Join-Path $RepoRootAbs ".env"),
  (Join-Path $RepoRootAbs ".env.local")
)
Load-DotEnv $envFiles

$secretFile = Join-Path $RepoRootAbs "proofs\secrets\SUPABASE_SERVICE_ROLE_KEY.txt"
if(Test-Path -LiteralPath $secretFile -PathType Leaf){
  $v = (Read-Utf8 $secretFile).Trim()
  if(-not [string]::IsNullOrWhiteSpace($v)){
    $existing = [Environment]::GetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY","Process")
    if([string]::IsNullOrWhiteSpace($existing)){
      [Environment]::SetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY",$v,"Process")
      Write-Output "ENV_LOADED_SERVICE_ROLE_KEY=1"
    }
  }
}

$url = [Environment]::GetEnvironmentVariable("SUPABASE_URL","Process")
if([string]::IsNullOrWhiteSpace($url)){
  [Environment]::SetEnvironmentVariable("SUPABASE_URL","http://127.0.0.1:54331","Process")
  Write-Output "ENV_DEFAULT_SUPABASE_URL=1"
}

$srk = [Environment]::GetEnvironmentVariable("SUPABASE_SERVICE_ROLE_KEY","Process")
if([string]::IsNullOrWhiteSpace($srk)){ Die "MISSING_ENV_SUPABASE_SERVICE_ROLE_KEY" }

$node = (Get-Command node.exe -ErrorAction Stop).Source
if(-not (Test-Path -LiteralPath $node -PathType Leaf)){ Die ("MISSING_NODE: " + $node) }
$runDir = Join-Path $RepoRootAbs "proofs\runs\apv_worker_v1"
Ensure-Dir $runDir
$ts = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss")
$outLog = Join-Path $runDir ("worker_stdout_" + $ts + ".log")
$errLog = Join-Path $runDir ("worker_stderr_" + $ts + ".log")
Write-Output "APV_WORKER_V1_START"
Write-Output ("API_ROOT=" + $ApiRoot)
Write-Output ("LOG_STDOUT=" + $outLog)
Write-Output ("LOG_STDERR=" + $errLog)
Push-Location -LiteralPath $ApiRoot
try {
  $p = Start-Process -FilePath $node -ArgumentList @(".\src\worker.cjs") -NoNewWindow -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
  Start-Sleep -Seconds 2
  if($p.HasExited){ Die ("WORKER_EXIT_EARLY: " + $p.ExitCode + " (see logs)") }
  Write-Output ("WORKER_STARTED_PID=" + $p.Id)
} finally { Pop-Location }
Write-Output "APV_WORKER_V1_OK"
