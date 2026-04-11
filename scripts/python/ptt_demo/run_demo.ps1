param(
    [string]$ApiHost = "0.0.0.0",
    [int]$Port = 8090,
    [string]$EslHost = "127.0.0.1",
    [int]$EslPort = 8021,
    [string]$EslPassword = "ClueCon",
    [string]$FsDomain = "127.0.0.1",
    [string]$RecordingsDir = "C:/freeswitch/recordings",
    [switch]$SkipEslCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-TcpPort {
    param(
        [Parameter(Mandatory = $true)][string]$TargetHost,
        [Parameter(Mandatory = $true)][int]$Port,
        [int]$TimeoutMs = 1500
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            return $false
        }
        $client.EndConnect($iar)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Get-ListeningProcessInfo {
    param(
        [Parameter(Mandatory = $true)][int]$Port
    )

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
Set-Location $scriptDir

if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    throw "python is not found in PATH"
}

if (-not $SkipEslCheck) {
    if (-not (Test-TcpPort -TargetHost $EslHost -Port $EslPort)) {
        throw "ESL endpoint $EslHost`:$EslPort is unreachable. Please start FreeSWITCH and ensure mod_event_socket is listening before running this script."
    }
}

if (-not (Test-Path ".venv/Scripts/python.exe")) {
    Write-Host "Creating virtual environment..."
    python -m venv .venv
}

Write-Host "Installing dependencies..."
& .\.venv\Scripts\python.exe -m pip install --upgrade pip
& .\.venv\Scripts\python.exe -m pip install -r requirements.txt

Write-Host "Generating bot audio files..."
& .\generate_bot_audio.ps1

$env:ESL_HOST = $EslHost
$env:ESL_PORT = "$EslPort"
$env:ESL_PASSWORD = $EslPassword
$env:FS_DOMAIN = $FsDomain
$env:RECORDINGS_DIR = $RecordingsDir

$existingListener = Get-ListeningProcessInfo -Port $Port
if ($existingListener) {
    if ($existingListener.CommandLine -and $existingListener.CommandLine.Contains("uvicorn ptt_demo_service:app")) {
        Write-Host "Demo API is already running on ${ApiHost}:$Port (PID $($existingListener.ProcessId))."
        return
    }

    $processSummary = if ($existingListener.ProcessName) {
        "$($existingListener.ProcessName) (PID $($existingListener.ProcessId))"
    } else {
        "PID $($existingListener.ProcessId)"
    }

    throw "API port $Port is already in use by $processSummary. Stop that process or pass a different -Port value."
}

Write-Host "Starting demo API on ${ApiHost}:$Port ..."
& .\.venv\Scripts\python.exe -m uvicorn ptt_demo_service:app --host $ApiHost --port $Port
