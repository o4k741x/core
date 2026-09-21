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
  exit 1
fi

command -v ffmpeg >/dev/null 2>&1 || { echo "ERROR: ffmpeg not found. Install with: brew install ffmpeg"; exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "ERROR: ffprobe not found. Install with: brew install ffmpeg"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found."; exit 1; }

# ---------------- CONFIG ----------------
VBR_QUALITY="${VBR_QUALITY:-2}"     # LAME: 0 highest, 2 excellent, 4/5 smaller
NIGHTCORE="${NIGHTCORE:-1.25}"      # faster + higher pitch
NIGHTCORE_ALT="${NIGHTCORE_ALT:-1.20}"      # faster + higher pitch
DAYCORE="${DAYCORE:-0.80}"          # slower + lower pitch
DAYCORE_ALT="${DAYCORE_ALT:-0.85}"          # slower + lower pitch
MORNINGCORE="${MORNINGCORE:-0.75}"  # slower + lower pitch
MORNINGCORE_ALT="${MORNINGCORE_ALT:-0.90}"  # slower + lower pitch
SPEDUP="${SPEDUP:-1.20}"          # faster + higher pitch
SLOWDOWN="${SLOWDOWN:-0.8}"        # slower + lower pitch
BPMFAST="${BPMFAST:-1.20}"      # faster, pitch preserved
BPMSLOW="${BPMSLOW:-0.85}"      # slower, pitch preserved
# -----------------------------------------

STAMP="$(date '+%Y%m%d-%H%M%S')"
ROOT="$INPUT/AudioEdits"
mkdir -p "$ROOT"/{mp3/nightcore,mp3/nightcore_alt,mp3/daycore,mp3/daycore_alt,mp3/morningcore,mp3/morningcore_alt,mp3/speedup,mp3/slowdown,mp3/bpmfast,mp3/bpmslow,manifests,logs}

JSON="$ROOT/manifests/audio-edits-$STAMP.json"
CSV="$ROOT/manifests/audio-edits-$STAMP.csv"
LOG="$ROOT/logs/audio-edits-$STAMP.log"

echo "Audio Edit Factory" | tee "$LOG"
echo "Input: $INPUT" | tee -a "$LOG"
echo "Output: $ROOT" | tee -a "$LOG"
echo "VBR quality: $VBR_QUALITY" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# Write a tab-delimited manifest stream; Python converts it to JSON + CSV.
MANIFEST_TMP="$(mktemp -t audio_edits_manifest.XXXXXX)"
trap 'rm -f "$MANIFEST_TMP"' EXIT

find "$INPUT" -type f \( \
  -iname '*.flac' -o -iname '*.alac' -o -iname '*.wav' -o \
  -iname '*.aiff' -o -iname '*.aif' -o -iname '*.m4a' \
\) ! -path "$ROOT/*" -print0 > "$MANIFEST_TMP.files"

COUNT=0
SUCCESS=0
FAILED=0

process_variant() {
  local src="$1"
  local variant="$2"
  local factor="$3"
  local mode="$4"
  local outdir="$ROOT/mp3/$variant"

  local filename name out
  filename="$(basename "$src")"
  name="${filename%.*}"
  out="$outdir/$name +$variant +$mode @+$factor+mp3.mp3"

  # ffmpeg's asetrate trick gives classic speed+pitch behavior:
  # factor > 1 = faster/higher pitch; factor < 1 = slower/lower pitch.
  local filter
  case "$mode" in
    pitch)
      filter="asetrate=44100*$factor,aresample=44100"
      ;;
    tempo)
      filter="atempo=$factor"
      ;;
    *)
      echo "ERROR: unknown mode $mode" | tee -a "$LOG"
      return 1
      ;;
  esac

  echo "  → $variant" | tee -a "$LOG"

  # -map 0:a:0 selects the first audio stream.
  # -map 0:v? keeps embedded artwork when the source exposes it.
  # -map_metadata 0 copies tags.
  # -c:v copy preserves cover art without re-encoding it.
  # -q:a 2 = LAME VBR high-quality/space-efficient setting.
  if ffmpeg -hide_banner -loglevel error -y \
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
      "$out" 2>>"$LOG"; then

    local inbytes outbytes ratio duration
    inbytes="$(stat -f '%z' "$src" 2>/dev/null || echo 0)"
    outbytes="$(stat -f '%z' "$out" 2>/dev/null || echo 0)"
    ratio="0"
    if [[ "$inbytes" -gt 0 ]]; then
      ratio="$(awk -v a="$outbytes" -v b="$inbytes" 'BEGIN {printf "%.4f", a/b}')"
    fi
    duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$out" 2>/dev/null || echo "")"

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "success" "$src" "$variant" "$out" "$factor" "$mode" "$inbytes" "$outbytes" "$duration" >> "$MANIFEST_TMP"
    SUCCESS=$((SUCCESS+1))
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "failed" "$src" "$variant" "$out" "$factor" "$mode" "0" "0" "" >> "$MANIFEST_TMP"
    FAILED=$((FAILED+1))
  fi
}

while IFS= read -r -d '' src; do
  COUNT=$((COUNT+1))
  echo "" | tee -a "$LOG"
  echo "[$COUNT] $(basename "$src")" | tee -a "$LOG"

  process_variant "$src" "nightcore" "$NIGHTCORE" "pitch"
  process_variant "$src" "nightcore_alt" "$NIGHTCORE_ALT" "pitch"
  process_variant "$src" "daycore" "$DAYCORE" "pitch"
  process_variant "$src" "daycore_alt" "$DAYCORE_ALT" "pitch"
  process_variant "$src" "morningcore" "$MORNINGCORE" "pitch"
  process_variant "$src" "morningcore_alt" "$MORNINGCORE" "pitch"
  process_variant "$src" "speedup" "$SPEDUP" "pitch"
  process_variant "$src" "slowdown" "$SLOWDOWN" "pitch"
  process_variant "$src" "bpmfast" "$BPMFAST" "tempo"
  process_variant "$src" "bpmslow" "$BPMSLOW" "tempo"
done < "$MANIFEST_TMP.files"

export MANIFEST_TMP JSON CSV INPUT ROOT STAMP VBR_QUALITY
python3 <<'PY'
import csv, json, os
from pathlib import Path

tmp = Path(os.environ["MANIFEST_TMP"])
json_out = Path(os.environ["JSON"])
csv_out = Path(os.environ["CSV"])

rows=[]
fields=["status","source","variant","output","factor","mode","source_bytes","output_bytes","duration_seconds"]

if tmp.exists():
    for line in tmp.read_text(errors="replace").splitlines():
        p=line.split("\t")
        if len(p) == len(fields):
            d=dict(zip(fields,p))
            d["source_bytes"]=int(d["source_bytes"] or 0)
            d["output_bytes"]=int(d["output_bytes"] or 0)
            d["factor"]=float(d["factor"])
            d["duration_seconds"]=float(d["duration_seconds"]) if d["duration_seconds"] else None
            rows.append(d)

payload={
    "generated_at": os.environ["STAMP"],
    "input_folder": os.environ["INPUT"],
    "output_folder": os.environ["ROOT"],
    "encoder": "LAME via FFmpeg",
    "vbr_quality": int(os.environ["VBR_QUALITY"]),
    "source_policy": "Original source files are never modified.",
    "edits": rows,
}
json_out.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")

with csv_out.open("w", newline="", encoding="utf-8") as f:
    w=csv.DictWriter(f, fieldnames=fields)
    w.writeheader()
    w.writerows(rows)

print(f"Manifest: {json_out}")
print(f"CSV:      {csv_out}")
PY

rm -f "$MANIFEST_TMP.files"

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

osascript -e 'display notification "Audio edit batch finished" with title "Audio Edit Factory"' 2>/dev/null || true

read -r -p "Press Enter to close..."
