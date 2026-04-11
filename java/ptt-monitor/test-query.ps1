param(
  [string]$PgUrl = "jdbc:postgresql://127.0.0.1:5432/ptt_demo",
  [string]$PgUser = "postgres",
  [string]$PgPassword = "postgres"
)

$env:PG_URL = $PgUrl
$env:PG_USER = $PgUser
$env:PG_PASSWORD = $PgPassword

Set-Location $PSScriptRoot
mvn -q -DskipTests package
if ($LASTEXITCODE -ne 0) {
  throw "Maven build failed"
}

java -cp ".\target\ptt-monitor-1.0.0.jar" com.rocktech.ptt.QueryCli logs 20 0
