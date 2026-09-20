#!/bin/bash
# Audio Edit Factory — OGG experimental encoder enabled
# macOS Bash 3.2 compatible.
# Usage: ./audio-edit-factory-ogg-enabled.sh /path/to/folder

set -u
set -o pipefail

VBR_QUALITY="${VBR_QUALITY:-2}"
OGG_QUALITY="${OGG_QUALITY:-5}"
AAC_BITRATE="${AAC_BITRATE:-256k}"

VARIANTS=(
  'nightcore|1.20|speed_pitch'
  'nightcore alt|1.25|speed_pitch'
  'daycore|0.85|speed_pitch'
  'daycore alt|0.80|speed_pitch'
  'morningcore|0.90|speed_pitch'
  'speedup|1.10|speed_pitch'
  'speedup alt1|1.15|speed_pitch'
  'speedup alt2|1.20|speed_pitch'
  'slowdown|0.90|speed_pitch'
  'tempoFast|1.20|tempo_only'
  'tempoSlow|0.85|tempo_only'
)

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 FILE_OR_FOLDER [FILE_OR_FOLDER ...]"
  exit 1
fi

FFMPEG="$(command -v ffmpeg || true)"
FFPROBE="$(command -v ffprobe || true)"

if [ -z "$FFMPEG" ] || [ -z "$FFPROBE" ]; then
  echo "Error: ffmpeg and ffprobe are required."
  echo "Install them with: brew install ffmpeg"
  exit 1
fi

HAS_RUBBERBAND=0
if "$FFMPEG" -hide_banner -filters 2>/dev/null | grep -Eq '[[:space:]]rubberband[[:space:]]'; then
  HAS_RUBBERBAND=1
fi

echo "=========================================="
echo " AUDIO EDIT FACTORY"
echo "=========================================="
echo "MP3: LAME VBR quality $VBR_QUALITY"
echo "OGG: Vorbis quality $OGG_QUALITY"
echo "M4A: AAC $AAC_BITRATE"
if [ "$HAS_RUBBERBAND" -eq 1 ]; then
  echo "Pitch variants: Rubber Band enabled"
else
  echo "Pitch variants: tempo-only fallback"
fi
echo

safe_bitrate() {
  case "$1" in
    ''|N/A|*[!0-9]*) echo "unknown" ;;
    *) echo "$(( $1 / 1000 ))" ;;
  esac
}

make_filter() {
  FACTOR="$1"
  MODE="$2"
  if [ "$MODE" = "tempo_only" ]; then
    echo "atempo=$FACTOR"
  elif [ "$HAS_RUBBERBAND" -eq 1 ]; then
    echo "rubberband=tempo=1.0:pitch=$FACTOR"
  else
    echo "atempo=$FACTOR"
  fi
}

encode_ogg() {
  FILTER="$1"
  FILE="$2"
  OUT="$3"
  LOG="$4"

  # Homebrew FFmpeg 9 may expose only its native experimental Vorbis
  # encoder. -strict -2 enables that encoder.
  "$FFMPEG" -hide_banner -loglevel error -y \
    -i "$FILE" -vn -map 0:a:0 -map_metadata 0 -map_chapters -1 \
    -af "$FILTER" -f ogg -c:a vorbis -strict -2 -q:a "$OGG_QUALITY" \
    "$OUT" >> "$LOG" 2>&1
  STATUS=$?
  if [ "$STATUS" -eq 0 ] && [ -s "$OUT" ]; then
    return 0
  fi
  rm -f "$OUT"
  return "$STATUS"
}

encode_one() {
  FORMAT="$1"
  FILTER="$2"
  FILE="$3"
  OUT="$4"
  LOG="$5"

  if [ "$FORMAT" = "mp3" ]; then
    "$FFMPEG" -hide_banner -loglevel error -y \
      -i "$FILE" -vn -map 0:a:0 -map_metadata 0 -map_chapters -1 \
      -af "$FILTER" -c:a libmp3lame -q:a "$VBR_QUALITY" \
      "$OUT" >> "$LOG" 2>&1
  elif [ "$FORMAT" = "ogg" ]; then
    encode_ogg "$FILTER" "$FILE" "$OUT" "$LOG"
  else
    "$FFMPEG" -hide_banner -loglevel error -y \
      -i "$FILE" -vn -map 0:a:0 -map_metadata 0 -map_chapters -1 \
      -af "$FILTER" -c:a aac -b:a "$AAC_BITRATE" -movflags +faststart \
      "$OUT" >> "$LOG" 2>&1
  fi
}

process_file() {
  FILE="$1"
  INPUT_ROOT="$2"
  ROOT="$3"
  LOG="$4"

  BASE="$(basename "$FILE")"
  NAME="${BASE%.*}"
  REL="${FILE#$INPUT_ROOT/}"
  REL_DIR="$(dirname "$REL")"
  if [ "$REL_DIR" = "." ]; then OUTROOT="$ROOT"; else OUTROOT="$ROOT/$REL_DIR"; fi
  mkdir -p "$OUTROOT/mp3" "$OUTROOT/ogg" "$OUTROOT/m4a"

  CODEC="$($FFPROBE -v error -select_streams a:0 -show_entries stream=codec_name -of default=nw=1:nk=1 "$FILE" 2>/dev/null | head -1)"
  RAW_RATE="$($FFPROBE -v error -select_streams a:0 -show_entries stream=bit_rate -of default=nw=1:nk=1 "$FILE" 2>/dev/null | head -1)"
  RATE="$(safe_bitrate "$RAW_RATE")"

  echo "------------------------------------------"
  echo "$REL"
  echo "codec=${CODEC:-unknown} bitrate=${RATE}kbps"
  echo "------------------------------------------"

  for ROW in "${VARIANTS[@]}"; do
    LABEL="${ROW%%|*}"
    REST="${ROW#*|}"
    FACTOR="${REST%%|*}"
    MODE="${REST#*|}"
    FILTER="$(make_filter "$FACTOR" "$MODE")"

    for FORMAT in mp3 ogg m4a; do
      case "$FORMAT" in
        mp3) OUT="$OUTROOT/mp3/$NAME [$LABEL].mp3" ;;
        ogg) OUT="$OUTROOT/ogg/$NAME [$LABEL].ogg" ;;
        m4a) OUT="$OUTROOT/m4a/$NAME [$LABEL].m4a" ;;
      esac

      echo "Creating $FORMAT / $LABEL"
      encode_one "$FORMAT" "$FILTER" "$FILE" "$OUT" "$LOG"
      STATUS=$?
      if [ "$STATUS" -eq 0 ] && [ -s "$OUT" ]; then
        echo "  ✓ $OUT"
      else
        echo "  ✗ FAILED: $FORMAT / $LABEL"
        echo "FAILED exit=$STATUS format=$FORMAT label=$LABEL output=$OUT" >> "$LOG"
        rm -f "$OUT"
      fi
    done
  done
  echo
}

process_input() {
  INPUT="$1"
  if [ -f "$INPUT" ]; then
    case "$INPUT" in *.flac|*.FLAC) ;; *) echo "Skipping non-FLAC file: $INPUT"; return 0 ;; esac
    INPUT_ROOT="$(dirname "$INPUT")"
    ROOT="$INPUT_ROOT/AudioEdits"
    mkdir -p "$ROOT/logs"
    LOG="$ROOT/logs/audio-edit-$(date '+%Y%m%d-%H%M%S').log"
    : > "$LOG"
    process_file "$INPUT" "$INPUT_ROOT" "$ROOT" "$LOG"
    return 0
  fi

  if [ ! -d "$INPUT" ]; then echo "Skipping missing path: $INPUT"; return 0; fi
  INPUT_ROOT="$INPUT"
  ROOT="$INPUT/AudioEdits"
  mkdir -p "$ROOT/logs"
  LOG="$ROOT/logs/audio-edit-$(date '+%Y%m%d-%H%M%S').log"
  : > "$LOG"
  FOUND=0
  while IFS= read -r FILE || [ -n "$FILE" ]; do
    [ -n "$FILE" ] || continue
    FOUND=1
    process_file "$FILE" "$INPUT_ROOT" "$ROOT" "$LOG"
  done <<EOF
$(find "$INPUT" -type f -iname '*.flac' ! -path "$ROOT/*" ! -name '._*' -print)
EOF
  [ "$FOUND" -eq 1 ] || echo "No FLAC files found in: $INPUT"
}

for ARG in "$@"; do process_input "$ARG"; done

echo "=========================================="
echo " COMPLETE"
echo "=========================================="
