#!/bin/zsh
set -euo pipefail


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VBR_QUALITY="${VBR_QUALITY:-2}"


usage() {
  echo "Usage: $0 /path/to/music-folder"
  echo "       VBR_QUALITY=4 $0 /path/to/music-folder"
  exit 1
}


[[ $# -eq 1 ]] || usage
INPUT="$1"
[[ -d "$INPUT" ]] || { echo "Not a directory: $INPUT" >&2; exit 1; }


command -v ffmpeg >/dev/null || { echo "ffmpeg is required. Install with: brew install ffmpeg" >&2; exit 1; }
command -v ffprobe >/dev/null || { echo "ffprobe is required. Install with: brew install ffmpeg" >&2; exit 1; }


ROOT="$INPUT/AudioEdits"
MP3="$ROOT/mp3"
MANIFESTS="$ROOT/manifests"
LOGS="$ROOT/logs"
mkdir -p "$MP3" "$MANIFESTS" "$LOGS"
STAMP="$(date '+%Y%m%d-%H%M%S')"
LOG="$LOGS/audio-edits-$STAMP.log"
JSON="$MANIFESTS/audio-edits-$STAMP.json"
CSV="$MANIFESTS/audio-edits-$STAMP.csv"


exec > >(tee -a "$LOG") 2>&1


# Supported source formats. AAC may be .aac or AAC audio inside .m4a/.mp4.
EXTS=(flac alac wav aiff aif m4a mp4 aac ogg oga)


# Build find arguments (zsh compatible)
find_args=( "$INPUT" -type f \( )
for i in "${!EXTS[@]}"; do
  if [[ $i -eq 0 ]]; then
    find_args+=( -iname "*.${EXTS[$i]}" )
  else
    find_args+=( -o -iname "*.${EXTS[$i]}" )
  fi
done
find_args+=( \) -print0 )


# zsh-compatible file reading (replaces bash mapfile)
FILES=()
while IFS= read -r -d '' file; do
  FILES+=("$file")
done < <(find "${find_args[@]}" | sort -z)


if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "No supported audio files found in: $INPUT"
  exit 0
fi


printf 'source,source_codec,source_bitrate_kbps,source_sample_rate_hz,source_channels,variant,transform,output,output_size_bytes,duration_seconds\n' > "$CSV"
printf '[\n' > "$JSON"
FIRST=1
COUNT=0


json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))'
}


probe_field() {
  local file="$1" field="$2"
  ffprobe -v error -select_streams a:0 -show_entries "stream=$field" -of default=noprint_wrappers=1:nokey=1 "$file" 2>/dev/null | head -n1
}


probe_codec() { probe_field "$1" codec_name; }
probe_bitrate() {
  local v
  v="$(probe_field "$1" bit_rate || true)"
  [[ "$v" =~ ^[0-9]+$ ]] && echo $((v/1000)) || echo ""
}


# We use rubberband when available for true speed+pitch edits; otherwise
# fall back to atempo (tempo-only), with an explicit warning in the log.
HAS_RUBBERBAND=0
if ffmpeg -hide_banner -filters 2>/dev/null | grep -q 'rubberband'; then HAS_RUBBERBAND=1; fi


# Transform definitions: name|factor|mode
EDITS=(
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


for FILE in "${FILES[@]}"; do
  REL="${FILE#$INPUT/}"
  BASE="$(basename "$FILE")"
  NAME="${BASE%.*}"
  CODEC="$(probe_codec "$FILE" || true)"
  BITRATE="$(probe_bitrate "$FILE" || true)"
  SR="$(probe_field "$FILE" sample_rate || true)"
  CH="$(probe_field "$FILE" channels || true)"
  DURATION="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FILE" 2>/dev/null | head -n1 || true)"


  echo
  echo "=========================================="
  echo "Source: $REL"
  echo "Codec: ${CODEC:-unknown} | bitrate: ${BITRATE:-VBR/unknown} kbps | ${SR:-?} Hz | ${CH:-?} ch"
  echo "=========================================="


  for EDIT in "${EDITS[@]}"; do
    IFS='|' read -r LABEL FACTOR MODE <<< "$EDIT"
    OUTDIR="$MP3/$(echo "$LABEL" | tr '[:upper:]' '[:lower:]')"
    mkdir -p "$OUTDIR"
    BASE_OUT="$OUTDIR/${NAME} [$LABEL]"


    if [[ "$MODE" == "speed_pitch" && "$HAS_RUBBERBAND" -eq 1 ]]; then
      FILTER="rubberband=tempo=$FACTOR:pitch=$FACTOR"
      ACTUAL_MODE="$MODE"
    elif [[ "$MODE" == "tempo_only" ]]; then
      FILTER="atempo=$FACTOR"
      ACTUAL_MODE="$MODE"
    else
      FILTER="atempo=$FACTOR"
      ACTUAL_MODE="tempo_only_fallback"
      echo "WARNING: rubberband unavailable; $LABEL uses tempo-only fallback."
    fi


    echo "→ $LABEL (${FACTOR}x; $ACTUAL_MODE)"
    ffmpeg -hide_banner -loglevel error -y \
      -i "$FILE" \
      -map 0:a:0 -map_metadata 0 -map_chapters -1 \
      -filter:a "$FILTER" \
      -c:a libmp3lame -q:a "$VBR_QUALITY" \
      -id3v2_version 3 -write_id3v1 1 \
      "${BASE_OUT}.mp3"


    # Get file size
    SIZE="$(stat -f '%z' "${BASE_OUT}.mp3")"


    SAFE_SOURCE="$(printf '%s' "$REL" | json_escape)"
    SAFE_CODEC="$(printf '%s' "$CODEC" | json_escape)"
    SAFE_OUTPUT="$(printf '%s' "${BASE_OUT#$ROOT/}" | json_escape)"
    if [[ $FIRST -eq 0 ]]; then printf ',\n' >> "$JSON"; fi
    FIRST=0
    printf '  {"source":%s,"source_codec":%s,"source_bitrate_kbps":%s,"source_sample_rate_hz":%s,"source_channels":%s,"variant":%s,"transform":%s,"output":%s,"output_size_bytes":%s,"duration_seconds":%s}' \
      "$SAFE_SOURCE" "$SAFE_CODEC" "${BITRATE:-null}" "${SR:-null}" "${CH:-null}" \
      "$(printf '%s' "$LABEL" | json_escape)" "$FACTOR" "$SAFE_OUTPUT" "$SIZE" "${DURATION:-null}" >> "$JSON"


    printf '"%s","%s","%s","%s","%s","%s","%s","%s",%s,%s\n' \
      "${REL//\"/\"\"}" "$CODEC" "${BITRATE:-}" "${SR:-}" "${CH:-}" "$LABEL" "$FACTOR" \
      "${BASE_OUT#$ROOT/}" "$SIZE" "${DURATION:-}" >> "$CSV"
    COUNT=$((COUNT+1))
  done
done


printf '\n]\n' >> "$JSON"


echo
echo "=========================================="
echo "COMPLETE: $COUNT MP3 edits"
echo "=========================================="
echo "Output:     $ROOT"
echo "JSON:       $JSON"
echo "CSV:        $CSV"
echo "Log:        $LOG"
echo "VBR quality: $VBR_QUALITY"
if [[ "$HAS_RUBBERBAND" -eq 1 ]]; then
  echo "Pitch/speed: rubberband enabled"
else
  echo "Pitch/speed: tempo-only fallback (install an ffmpeg build with rubberband for true pitch shifts)"
fi