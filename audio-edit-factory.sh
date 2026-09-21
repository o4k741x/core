#!/bin/bash
# Audio Edit Factory for macOS
# Drag a folder containing FLAC / ALAC / WAV / AIFF / M4A files onto this file.
# Requires: ffmpeg + ffprobe + Python 3

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INPUT="${1:-}"

if [[ -z "$INPUT" ]]; then
  echo "Drag an audio folder onto this .command file, or run:"
  echo "  $0 /path/to/audio-folder"
  read -r -p "Press Enter to exit..."
  exit 1
fi

if [[ ! -d "$INPUT" ]]; then
  echo "ERROR: Not a folder: $INPUT"
  read -r -p "Press Enter to exit..."
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "ERROR: ffmpeg not found."
  echo "Install with: brew install ffmpeg"
  read -r -p "Press Enter to exit..."
  exit 1
fi

if ! command -v ffprobe >/dev/null 2>&1; then
  echo "ERROR: ffprobe not found."
  echo "Install with: brew install ffmpeg"
  read -r -p "Press Enter to exit..."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 not found."
  read -r -p "Press Enter to exit..."
  exit 1
fi

# ---------------- CONFIG ----------------

VBR_QUALITY="${VBR_QUALITY:-2}"

# Speed + pitch
NIGHTCORE="${NIGHTCORE:-1.25}"
NIGHTCORE_ALT="${NIGHTCORE_ALT:-1.20}"

DAYCORE="${DAYCORE:-0.80}"
DAYCORE_ALT="${DAYCORE_ALT:-0.85}"

MORNINGCORE="${MORNINGCORE:-0.90}"
MORNINGCORE_ALT="${MORNINGCORE_ALT:-0.75}"

SPEDUP="${SPEDUP:-1.200}"
SPEDUP_ALT="${SPEDUP_ALT:-1.220}"
SPEDUP_ALT_2="${SPEDUP_ALT_2:-1.340}"

SLOWDOWN="${SLOWDOWN:-0.95}"
SLOWDOWN_ALT="${SLOWDOWN_ALT:-0.80}"
SLOWDOWN_ALT_2="${SLOWDOWN_ALT_2:-0.85}"

# Tempo only: pitch preserved
TEMPOFAST="${TEMPOFAST:-1.20}"
TEMPOFAST_ALT="${TEMPOFAST_ALT:-1.240}"
TEMPOFAST_ALT_2="${TEMPOFAST_ALT_2:-1.420}"

TEMPOSLOW="${TEMPOSLOW:-0.85}"
TEMPOSLOW_ALT="${TEMPOSLOW_ALT:-0.75}"
TEMPOSLOW_ALT_2="${TEMPOSLOW_ALT_2:-0.65}"

# -----------------------------------------

STAMP="$(date '+%Y%m%d-%H%M%S')"
ROOT="$INPUT/AudioEdits"

mkdir -p \
  "$ROOT/mp3/nightcore" \
  "$ROOT/mp3/nightcore_alt" \
  "$ROOT/mp3/daycore" \
  "$ROOT/mp3/daycore_alt" \
  "$ROOT/mp3/morningcore" \
  "$ROOT/mp3/morningcore_alt" \
  "$ROOT/mp3/speedup" \
  "$ROOT/mp3/speedup_alt" \
  "$ROOT/mp3/speedup_alt_2" \
  "$ROOT/mp3/slowdown" \
  "$ROOT/mp3/slowdown_alt" \
  "$ROOT/mp3/slowdown_alt_2" \
  "$ROOT/mp3/tempofast" \
  "$ROOT/mp3/tempofast_alt" \
  "$ROOT/mp3/tempofast_alt_2" \
  "$ROOT/mp3/temposlow" \
  "$ROOT/mp3/temposlow_alt" \
  "$ROOT/mp3/temposlow_alt_2" \
  "$ROOT/manifests" \
  "$ROOT/logs"

JSON="$ROOT/manifests/audio-edits-$STAMP.json"
CSV="$ROOT/manifests/audio-edits-$STAMP.csv"
LOG="$ROOT/logs/audio-edits-$STAMP.log"

echo "Audio Edit Factory" | tee "$LOG"
echo "Input: $INPUT" | tee -a "$LOG"
echo "Output: $ROOT" | tee -a "$LOG"
echo "VBR quality: $VBR_QUALITY" | tee -a "$LOG"
echo "" | tee -a "$LOG"

MANIFEST_TMP="$(mktemp -t audio_edits_manifest.XXXXXX)"
MANIFEST_FILES="$MANIFEST_TMP.files"
PROGRESS_FILE="$MANIFEST_TMP.progress"

cleanup() {
  rm -f "$MANIFEST_TMP" "$MANIFEST_FILES" "$PROGRESS_FILE"
}

trap cleanup EXIT INT TERM

find "$INPUT" -type f \( \
  -iname '*.flac' -o \
  -iname '*.alac' -o \
  -iname '*.wav' -o \
  -iname '*.aiff' -o \
  -iname '*.aif' -o \
  -iname '*.m4a' \
\) ! -path "$ROOT/*" -print0 > "$MANIFEST_FILES"

COUNT=0
SUCCESS=0
FAILED=0

draw_progress_bar() {
  local percent="$1"
  local width=32
  local filled
  local empty

  [[ "$percent" -lt 0 ]] && percent=0
  [[ "$percent" -gt 100 ]] && percent=100

  filled=$((width * percent / 100))
  empty=$((width - filled))

  printf "\r    ["
  printf "%${filled}s" "" | tr ' ' '#'
  printf "%${empty}s" "" | tr ' ' '-'
  printf "] %3d%%" "$percent"
}

get_duration_us() {
  local src="$1"

  ffprobe \
    -v error \
    -select_streams a:0 \
    -show_entries format=duration \
    -of default=nw=1:nk=1 \
    "$src" 2>>"$LOG" |
    awk '{
      if ($1 ~ /^[0-9.]+$/) {
        printf "%.0f", $1 * 1000000
      }
    }'
}

get_sample_rate() {
  local src="$1"

  ffprobe \
    -v error \
    -select_streams a:0 \
    -show_entries stream=sample_rate \
    -of default=nw=1:nk=1 \
    "$src" 2>>"$LOG" |
    head -n 1
}

run_ffmpeg_with_progress() {
  local src="$1"
  local out="$2"
  local filter="$3"
  local duration_us="$4"

  local ffmpeg_pid
  local key
  local value
  local current_us
  local percent
  local last_percent="-1"
  local result

  : > "$PROGRESS_FILE"

  ffmpeg \
    -hide_banner \
    -loglevel error \
    -nostats \
    -stats_period 0.5 \
    -progress "$PROGRESS_FILE" \
    -y \
    -i "$src" \
    -map 0:a:0 \
    -map 0:v? \
    -map_metadata 0 \
    -map_chapters -1 \
    -filter:a "$filter" \
    -c:a libmp3lame \
    -q:a "$VBR_QUALITY" \
    -id3v2_version 3 \
    -write_id3v1 1 \
    -c:v copy \
    -disposition:v attached_pic \
    "$out" \
    2>>"$LOG" &

  ffmpeg_pid=$!

  while kill -0 "$ffmpeg_pid" 2>/dev/null; do
    if [[ -s "$PROGRESS_FILE" ]]; then
      while IFS='=' read -r key value; do
        case "$key" in
          out_time_us|out_time_ms)
            current_us="$value"

            if [[ "$duration_us" =~ ^[0-9]+$ ]] &&
               [[ "$duration_us" -gt 0 ]] &&
               [[ "$current_us" =~ ^[0-9]+$ ]]; then

              percent="$(
                awk \
                  -v current="$current_us" \
                  -v total="$duration_us" \
                  'BEGIN {
                    p=(current / total) * 100
                    if (p < 0) p=0
                    if (p > 100) p=100
                    printf "%.0f", p
                  }'
              )"

              if [[ "$percent" != "$last_percent" ]]; then
                draw_progress_bar "$percent"
                last_percent="$percent"
              fi
            fi
            ;;

          progress)
            if [[ "$value" == "end" ]]; then
              draw_progress_bar 100
              printf "\n"
            fi
            ;;
        esac
      done < "$PROGRESS_FILE"

      : > "$PROGRESS_FILE"
    fi

    sleep 0.2
  done

  wait "$ffmpeg_pid"
  result=$?

  if [[ "$result" -ne 0 ]]; then
    printf "\n"
  fi

  return "$result"
}

process_variant() {
  local src="$1"
  local variant="$2"
  local factor="$3"
  local mode="$4"
  local outdir="$ROOT/mp3/$variant"

  mkdir -p "$outdir"

  local filename
  local name
  local out
  local sample_rate
  local duration_us
  local filter

  filename="$(basename "$src")"
  name="${filename%.*}"
  out="$outdir/$name +$variant +$mode @+$factor+mp3.mp3"

  sample_rate="$(get_sample_rate "$src")"
  duration_us="$(get_duration_us "$src")"

  if [[ -z "$sample_rate" ]]; then
    echo "ERROR: Could not determine sample rate: $src" | tee -a "$LOG"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "failed" "$src" "$variant" "$out" "$factor" "$mode" \
      "0" "0" "" >> "$MANIFEST_TMP"

    FAILED=$((FAILED + 1))
    return 1
  fi

  if [[ -z "$duration_us" ]]; then
    duration_us=0
  fi

  case "$mode" in
    pitch)
      filter="asetrate=${sample_rate}*${factor},aresample=${sample_rate}"
      ;;

    tempo)
      filter="atempo=${factor}"
      ;;

    *)
      echo "ERROR: unknown mode $mode" | tee -a "$LOG"

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "failed" "$src" "$variant" "$out" "$factor" "$mode" \
        "0" "0" "" >> "$MANIFEST_TMP"

      FAILED=$((FAILED + 1))
      return 1
      ;;
  esac

  echo "  → $variant | factor=$factor | mode=$mode" | tee -a "$LOG"

  if run_ffmpeg_with_progress "$src" "$out" "$filter" "$duration_us"; then
    local inbytes
    local outbytes
    local ratio
    local duration

    inbytes="$(stat -f '%z' "$src" 2>/dev/null || echo 0)"
    outbytes="$(stat -f '%z' "$out" 2>/dev/null || echo 0)"

    ratio="0"

    if [[ "$inbytes" -gt 0 ]]; then
      ratio="$(
        awk -v a="$outbytes" -v b="$inbytes" \
          'BEGIN {printf "%.4f", a/b}'
      )"
    fi

    duration="$(
      ffprobe \
        -v error \
        -show_entries format=duration \
        -of default=nw=1:nk=1 \
        "$out" 2>/dev/null || echo ""
    )"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "success" "$src" "$variant" "$out" "$factor" "$mode" \
      "$inbytes" "$outbytes" "$duration" >> "$MANIFEST_TMP"

    SUCCESS=$((SUCCESS + 1))

    echo "    completed | output ratio=$ratio" | tee -a "$LOG"
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "failed" "$src" "$variant" "$out" "$factor" "$mode" \
      "0" "0" "" >> "$MANIFEST_TMP"

    FAILED=$((FAILED + 1))
    echo "    FAILED: $variant" | tee -a "$LOG"
  fi
}

while IFS= read -r -d '' src; do
  COUNT=$((COUNT + 1))

  echo "" | tee -a "$LOG"
  echo "[$COUNT] $(basename "$src")" | tee -a "$LOG"

  # Speed + pitch
  process_variant "$src" "nightcore" "$NIGHTCORE" "pitch"
  process_variant "$src" "nightcore_alt" "$NIGHTCORE_ALT" "pitch"

  process_variant "$src" "daycore" "$DAYCORE" "pitch"
  process_variant "$src" "daycore_alt" "$DAYCORE_ALT" "pitch"

  process_variant "$src" "morningcore" "$MORNINGCORE" "pitch"
  process_variant "$src" "morningcore_alt" "$MORNINGCORE_ALT" "pitch"

  process_variant "$src" "speedup" "$SPEDUP" "pitch"
  process_variant "$src" "speedup_alt" "$SPEDUP_ALT" "pitch"
  process_variant "$src" "speedup_alt_2" "$SPEDUP_ALT_2" "pitch"

  process_variant "$src" "slowdown" "$SLOWDOWN" "pitch"
  process_variant "$src" "slowdown_alt" "$SLOWDOWN_ALT" "pitch"
  process_variant "$src" "slowdown_alt_2" "$SLOWDOWN_ALT_2" "pitch"

  # Tempo only
  process_variant "$src" "tempofast" "$TEMPOFAST" "tempo"
  process_variant "$src" "tempofast_alt" "$TEMPOFAST_ALT" "tempo"
  process_variant "$src" "tempofast_alt_2" "$TEMPOFAST_ALT_2" "tempo"

  process_variant "$src" "temposlow" "$TEMPOSLOW" "tempo"
  process_variant "$src" "temposlow_alt" "$TEMPOSLOW_ALT" "tempo"
  process_variant "$src" "temposlow_alt_2" "$TEMPOSLOW_ALT_2" "tempo"

done < "$MANIFEST_FILES"

export MANIFEST_TMP JSON CSV INPUT ROOT STAMP VBR_QUALITY

python3 <<'PY'
import csv
import json
import os
from pathlib import Path

tmp = Path(os.environ["MANIFEST_TMP"])
json_out = Path(os.environ["JSON"])
csv_out = Path(os.environ["CSV"])

fields = [
    "status",
    "source",
    "variant",
    "output",
    "factor",
    "mode",
    "source_bytes",
    "output_bytes",
    "duration_seconds",
]

rows = []

if tmp.exists():
    for line in tmp.read_text(errors="replace").splitlines():
        parts = line.split("\t")

        if len(parts) != len(fields):
            continue

        item = dict(zip(fields, parts))

        try:
            item["source_bytes"] = int(item["source_bytes"] or 0)
        except ValueError:
            item["source_bytes"] = 0

        try:
            item["output_bytes"] = int(item["output_bytes"] or 0)
        except ValueError:
            item["output_bytes"] = 0

        try:
            item["factor"] = float(item["factor"])
        except ValueError:
            item["factor"] = None

        try:
            item["duration_seconds"] = (
                float(item["duration_seconds"])
                if item["duration_seconds"]
                else None
            )
        except ValueError:
            item["duration_seconds"] = None

        rows.append(item)

payload = {
    "generated_at": os.environ["STAMP"],
    "input_folder": os.environ["INPUT"],
    "output_folder": os.environ["ROOT"],
    "encoder": "LAME via FFmpeg",
    "vbr_quality": int(os.environ["VBR_QUALITY"]),
    "source_policy": "Original source files are never modified.",
    "edits": rows,
}

json_out.write_text(
    json.dumps(payload, indent=2, ensure_ascii=False),
    encoding="utf-8",
)

with csv_out.open("w", newline="", encoding="utf-8") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)

print(f"Manifest: {json_out}")
print(f"CSV:      {csv_out}")
PY

echo "" | tee -a "$LOG"
echo "==============================================" | tee -a "$LOG"
echo "COMPLETE" | tee -a "$LOG"
echo "Source files: $COUNT" | tee -a "$LOG"
echo "MP3 edits:    $SUCCESS succeeded / $FAILED failed" | tee -a "$LOG"
echo "Output:       $ROOT" | tee -a "$LOG"
echo "JSON:         $JSON" | tee -a "$LOG"
echo "CSV:          $CSV" | tee -a "$LOG"
echo "Log:          $LOG" | tee -a "$LOG"
echo "==============================================" | tee -a "$LOG"

osascript \
  -e 'display notification "Audio edit batch finished" with title "Audio Edit Factory"' \
  2>/dev/null || true

read -r -p "Press Enter to close..."