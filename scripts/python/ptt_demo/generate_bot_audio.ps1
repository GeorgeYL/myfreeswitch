param(
    [string]$OutputDir = "$PSScriptRoot\bot_audio"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Speech
if (-not (Test-Path $OutputDir)) {
    New-Item -Path $OutputDir -ItemType Directory | Out-Null
}

$tts = New-Object System.Speech.Synthesis.SpeechSynthesizer
$tts.Rate = 0

$items = @(
    @{ File = 'qa_schedule.wav'; Text = 'Training schedule reminder. Please follow your coach instructions.' },
    @{ File = 'qa_safety.wav'; Text = 'Safety reminder. Keep distance and use channel discipline.' },
    @{ File = 'qa_help.wav'; Text = 'Support reminder. Please raise your hand and wait for the coach.' },
    @{ File = 'qa_default.wav'; Text = 'Robot reply. Your question has been received.' }
)

foreach ($item in $items) {
    $target = Join-Path $OutputDir $item.File
    $tts.SetOutputToWaveFile($target)
    $tts.Speak($item.Text)
    $tts.SetOutputToNull()
    Write-Host "Generated: $target"
}
