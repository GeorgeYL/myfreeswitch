param(
    [string]$BaseUrl = "http://127.0.0.1:8090"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Checking health..."
$health = Invoke-RestMethod -Method Get -Uri "$BaseUrl/health"
$health | ConvertTo-Json -Depth 5

Write-Host "Checking logs endpoint..."
$logs = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/logs"
"log_count=$($logs.Count)"

Write-Host "Triggering bot reply for site=1 channel=1..."
$body = @{ site = 1; channel = 1; question = "need safety reminder" } | ConvertTo-Json
$reply = Invoke-RestMethod -Method Post -Uri "$BaseUrl/api/bot/reply" -ContentType "application/json" -Body $body
$reply | ConvertTo-Json -Depth 5

Write-Host "Smoke test finished."
