#!/bin/zsh
cd -- "${0:A:h}" || exit 1
if [[ ! -x .venv/bin/python || ! -f models/whisper-base/model.bin ]]; then
  echo 'Voice setup is incomplete. See README.md.'
  read -r '?Press Enter to close.'
  exit 1
fi
export HF_HUB_OFFLINE=1
export HF_HUB_DISABLE_TELEMETRY=1
.venv/bin/python assistant.py --speak --voice-model models/whisper-base
read -r '?Press Enter to close.'
