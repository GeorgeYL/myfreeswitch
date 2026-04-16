#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_DIR="$SCRIPT_DIR/bot_audio"
mkdir -p "$AUDIO_DIR"

# Preferred engine order: pico2wave -> espeak-ng -> espeak
has_pico=0
has_espeak_ng=0
has_espeak=0

command -v pico2wave >/dev/null 2>&1 && has_pico=1
command -v espeak-ng >/dev/null 2>&1 && has_espeak_ng=1
command -v espeak >/dev/null 2>&1 && has_espeak=1

if [[ "$has_pico" -eq 0 && "$has_espeak_ng" -eq 0 && "$has_espeak" -eq 0 ]]; then
  echo "ERROR: Neither pico2wave, espeak-ng, nor espeak found. Install one TTS engine first." >&2
  echo "Hint: Ubuntu/Debian -> apt-get install -y libttspico-utils  OR  apt-get install -y espeak-ng" >&2
  echo "Hint: CentOS/RHEL/Stream -> yum install -y espeak-ng  OR  dnf install -y espeak-ng" >&2
  exit 1
fi

render_wav() {
  local text="$1"
  local out="$2"

  if [[ "$has_pico" -eq 1 ]]; then
    pico2wave -l=en-US -w="$out" "$text" >/dev/null 2>&1
    return
  fi

  if [[ "$has_espeak_ng" -eq 1 ]]; then
    espeak-ng -w "$out" "$text" >/dev/null 2>&1
    return
  fi

  espeak -w "$out" "$text" >/dev/null 2>&1
}

render_wav "Today's training starts at 2 PM in Zone 1." "$AUDIO_DIR/qa_schedule.wav"
render_wav "Safety reminder: wear helmet and check channel before speaking." "$AUDIO_DIR/qa_safety.wav"
render_wav "If you need help, hold P T T key and call supervisor on channel 4." "$AUDIO_DIR/qa_help.wav"
render_wav "Sorry, I don't understand the question. Please ask schedule, safety, or help." "$AUDIO_DIR/qa_default.wav"

echo "Bot audio generated in: $AUDIO_DIR"
