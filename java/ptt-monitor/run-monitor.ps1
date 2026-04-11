param(
  [string]$PgUrl = "jdbc:postgresql://127.0.0.1:5432/ptt_demo",
  [string]$PgUser = "postgres",
  [string]$PgPassword = "postgres",
  [string]$EslHost = "127.0.0.1",
  [int]$EslPort = 8021,
  [string]$EslPassword = "ClueCon",
  [string]$FsDomain = "127.0.0.1",
  [string]$RecordingsDir = "D:/03_rocktech/source/freeswitch/x64/Release/recordings",
  [string]$HttpHost = "0.0.0.0",
  [int]$HttpPort = 8091
)

& "$PSScriptRoot\run-all.ps1" `
  -PgUrl $PgUrl `
  -PgUser $PgUser `
  -PgPassword $PgPassword `
  -EslHost $EslHost `
  -EslPort $EslPort `
  -EslPassword $EslPassword `
  -FsDomain $FsDomain `
  -RecordingsDir $RecordingsDir `
  -HttpHost $HttpHost `
  -HttpPort $HttpPort
