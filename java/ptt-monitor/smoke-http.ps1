param(
  [string]$BaseUrl = "http://127.0.0.1:8091"
)

$ErrorActionPreference = "Stop"

Write-Host "[smoke] health"
Invoke-RestMethod -Method Get -Uri "$BaseUrl/health" | ConvertTo-Json

Write-Host "[smoke] health/db"
Invoke-RestMethod -Method Get -Uri "$BaseUrl/health/db" | ConvertTo-Json

Write-Host "[smoke] logs"
Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/logs?limit=10&offset=0" | ConvertTo-Json -Depth 8
