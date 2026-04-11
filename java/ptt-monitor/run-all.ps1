param(
  [string]$PgUrl = "jdbc:postgresql://127.0.0.1:5432/ptt_demo",
  [string]$PgUser = "postgres",
  [string]$PgPassword = "postgres",
  [string]$PgConninfo = "host=127.0.0.1 port=5432 dbname=ptt_demo user=postgres password=postgres",
  [string]$EslHost = "127.0.0.1",
  [int]$EslPort = 8021,
  [string]$EslPassword = "ClueCon",
  [string]$FsDomain = "127.0.0.1",
  [string]$RecordingsDir = "D:/03_rocktech/source/freeswitch/x64/Release/recordings",
  [string]$HttpHost = "0.0.0.0",
  [int]$HttpPort = 8091
)

$ErrorActionPreference = "Stop"

function Resolve-CommandPath($name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd) {
    return $cmd.Source
  }

  return $null
}

function Resolve-JavaTool($toolName) {
  $toolCmd = Resolve-CommandPath $toolName
  if ($toolCmd) {
    return $toolCmd
  }

  if ($env:JAVA_HOME) {
    $candidate = Join-Path $env:JAVA_HOME "bin\$toolName.exe"
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return $null
}

$javaCmd = Resolve-JavaTool "java"
$javacCmd = Resolve-JavaTool "javac"
$mvnCmd = Resolve-CommandPath "mvn"

if (-not $javaCmd) {
  throw "Missing command: java"
}

if (-not $javacCmd) {
  throw "Missing command: javac"
}

if (-not $mvnCmd) {
  $localMaven = Join-Path $PSScriptRoot ".tools\apache-maven-3.9.9\bin\mvn.cmd"
  if (Test-Path $localMaven) {
    $mvnCmd = $localMaven
  } else {
    throw "Missing command: mvn"
  }
}

$esl = Test-NetConnection -ComputerName $EslHost -Port $EslPort -WarningAction SilentlyContinue
if (-not $esl.TcpTestSucceeded) {
  throw "ESL not reachable: ${EslHost}:$EslPort"
}

$env:PG_URL = $PgUrl
$env:PG_USER = $PgUser
$env:PG_PASSWORD = $PgPassword
$env:PG_CONNINFO = $PgConninfo
$env:ESL_HOST = $EslHost
$env:ESL_PORT = "$EslPort"
$env:ESL_PASSWORD = $EslPassword
$env:FS_DOMAIN = $FsDomain
$env:RECORDINGS_DIR = $RecordingsDir
$env:HTTP_ENABLE = "true"
$env:HTTP_HOST = $HttpHost
$env:HTTP_PORT = "$HttpPort"

Set-Location $PSScriptRoot
& $mvnCmd -DskipTests package
if ($LASTEXITCODE -ne 0) {
  throw "Maven build failed"
}

$jarPath = Join-Path $PSScriptRoot "target\ptt-monitor-1.0.0-all.jar"
if (-not (Test-Path $jarPath)) {
  throw "Missing packaged jar: $jarPath"
}

& $javaCmd -jar $jarPath
