param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$RepoRootAbs = (Resolve-Path -LiteralPath $RepoRoot).Path
Write-Output "APV_LOCAL_STACK_V1_START"
Write-Output ("REPO_ROOT=" + $RepoRootAbs)
Write-Output "TODO: wire Supabase local + run upload + worker verify."
Write-Output "APV_LOCAL_STACK_V1_OK"
