param(
  [ValidateSet("java", "python")]
  [string]$Mode = "java",
  [string]$JavaHost = "0.0.0.0",
  [int]$JavaPort = 8091,
  [string]$PythonHost = "0.0.0.0",
  [int]$PythonPort = 8090,
  [switch]$SkipEslCheck
)

$ErrorActionPreference = "Stop"

function Get-ListeningProcessInfo {
  param([Parameter(Mandatory = $true)][int]$Port)

  $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1

  if (-not $connection) {
    return $null
  }

  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $($connection.OwningProcess)" -ErrorAction SilentlyContinue
  if (-not $process) {
    return [pscustomobject]@{
      ProcessId   = $connection.OwningProcess
      ProcessName = $null
      CommandLine = $null
    }
  }

  return [pscustomobject]@{
    ProcessId   = $process.ProcessId
    ProcessName = $process.Name
    CommandLine = $process.CommandLine
  }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent (Split-Path -Parent $scriptDir)

if ($Mode -eq "java") {
  $listener = Get-ListeningProcessInfo -Port $JavaPort
  if ($listener) {
    throw "Java API 端口 $JavaPort 已被占用 (PID=$($listener.ProcessId), Name=$($listener.ProcessName))"
  }

  Write-Host "[switch] 启动 Java API 模式 http://$JavaHost`:$JavaPort"
  & "$scriptDir\run-all.ps1" -HttpHost $JavaHost -HttpPort $JavaPort
  exit $LASTEXITCODE
}

$listener = Get-ListeningProcessInfo -Port $PythonPort
if ($listener) {
  throw "Python API 端口 $PythonPort 已被占用 (PID=$($listener.ProcessId), Name=$($listener.ProcessName))"
}

$pythonRunner = Join-Path $repoRoot "scripts\python\ptt_demo\run_demo.ps1"
if (-not (Test-Path $pythonRunner)) {
  throw "未找到 Python 启动脚本: $pythonRunner"
}

Write-Host "[switch] 启动 Python API 模式 http://$PythonHost`:$PythonPort"
if ($SkipEslCheck) {
  & $pythonRunner -ApiHost $PythonHost -Port $PythonPort -SkipEslCheck
} else {
  & $pythonRunner -ApiHost $PythonHost -Port $PythonPort
}
exit $LASTEXITCODE
