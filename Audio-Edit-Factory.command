#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ $# -eq 0 ]]; then
  osascript -e 'display dialog "Drop a music folder onto Audio-Edit-Factory.command to generate the MP3 edit library." buttons {"OK"} default button "OK" with title "Audio Edit Factory"' >/dev/null 2>&1 || true
  echo "Drag a folder onto this .command file."
  exit 0
fi

for INPUT in "$@"; do
  if [[ ! -d "$INPUT" ]]; then
    echo "Skipping non-folder: $INPUT"
    continue
  fi
  "$DIR/audio-edit-factory.sh" "$INPUT"
done

echo
echo "Finished. Press Return to close."
read -r _ || true
