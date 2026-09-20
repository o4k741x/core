from pathlib import Path

script = r'''#!/bin/bash
# ==============================================================
# AUDIO EDIT FACTORY v1 — macOS
# FLAC -> MP3 / OGG Vorbis / AAC
# Menu-driven speed/core edits
#
# Requires:
#   brew install ffmpeg
#
# Usage:
#   chmod +x audio-edit-factory.sh
#   ./audio-edit-factory.sh
#
# Notes:
#   - FLAC is always treated as the source/master.
#   - MP3 uses LAME VBR quality 0 (-V0).
#   - OGG uses Vorbis quality 10 (-q:a 10).
#   - AAC uses 320 kbps in an M4A container.
#   - Speed edits use FFmpeg's atempo filter: tempo changes,
#     pitch is preserved.
# ==============================================================

set -u
set -o pipefail

VERSION="v1"

# ---------- Terminal colors ----------
if [ -t 1 ]; then
    BOLD="$(printf '\033[1m')"
    CYAN="$(printf '\033[36m')"
    GREEN="$(printf '\033[32m')"
    YELLOW="$(printf '\033[33m')"
    RED="$(printf '\033[31m')"
    RESET="$(printf '\033[0m')"
else
    BOLD=""
    CYAN=""
    GREEN=""
    YELLOW=""
    RED=""
    RESET=""
fi

# ---------- Dependency check ----------
if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "${RED}ffmpeg is not installed.${RESET}"
    echo
    echo "Install it with:"
    echo "  brew install ffmpeg"
    exit 1
fi

FFMPEG="$(command -v ffmpeg)"

# ---------- Defaults ----------
INPUT_DIR=""
OUTPUT_DIR=""
FORMATS="mp3 ogg aac"
EDIT_NAME="normal"
SPEED="1.00"

# ---------- Functions ----------

header() {
    clear 2>/dev/null || true
    echo "=========================================="
    echo " AUDIO EDIT FACTORY ${VERSION}"
    echo "=========================================="
    echo "FLAC -> MP3 / OGG / AAC"
    echo "MP3 : LAME VBR -V0"
    echo "OGG : Vorbis quality 10"
    echo "AAC : 320 kbps"
    echo "Pitch: preserved during speed edits"
    echo "=========================================="
    echo
}

choose_input() {
    while :; do
        printf "Enter the folder containing your FLAC files:\n> "
        IFS= read -r INPUT_DIR

        # Remove surrounding quotes commonly pasted from Finder.
        case "$INPUT_DIR" in
            \"*\") INPUT_DIR="${INPUT_DIR#\"}"; INPUT_DIR="${INPUT_DIR%\"}" ;;
            \'*\') INPUT_DIR="${INPUT_DIR#\'}"; INPUT_DIR="${INPUT_DIR%\'}" ;;
        esac

        # Expand a leading ~.
        case "$INPUT_DIR" in
            "~"/*) INPUT_DIR="$HOME/${INPUT_DIR#~/}" ;;
        esac

        # Remove trailing slash except for root.
        if [ "$INPUT_DIR" != "/" ]; then
            INPUT_DIR="${INPUT_DIR%/}"
        fi

        if [ ! -d "$INPUT_DIR" ]; then
            echo "${YELLOW}Folder not found.${RESET}"
            echo
            continue
        fi

        local count
        count="$(find "$INPUT_DIR" -maxdepth 1 -type f \( \
            -iname '*.flac' \
            \) -print | wc -l | tr -d ' ')"

        if [ "${count:-0}" -eq 0 ]; then
            echo "${YELLOW}No FLAC files were found in that folder.${RESET}"
            echo
            continue
        fi

        echo
        echo "${GREEN}Found ${count} FLAC file(s).${RESET}"
        break
    done
}

choose_formats() {
    echo
    echo "=========================================="
    echo " OUTPUT FORMAT"
    echo "=========================================="
    echo
    echo "  1) MP3 only"
    echo "  2) OGG Vorbis only"
    echo "  3) AAC only"
    echo "  4) MP3 + OGG"
    echo "  5) MP3 + AAC"
    echo "  6) OGG + AAC"
    echo "  7) MP3 + OGG + AAC"
    echo
    printf "Choose [7]: "
    IFS= read -r choice
    choice="${choice:-7}"

    case "$choice" in
        1) FORMATS="mp3" ;;
        2) FORMATS="ogg" ;;
        3) FORMATS="aac" ;;
        4) FORMATS="mp3 ogg" ;;
        5) FORMATS="mp3 aac" ;;
        6) FORMATS="ogg aac" ;;
        7) FORMATS="mp3 ogg aac" ;;
        *)
            echo "${YELLOW}Invalid choice. Using MP3 + OGG + AAC.${RESET}"
            FORMATS="mp3 ogg aac"
            ;;
    esac
}

choose_edit() {
    echo
    echo "=========================================="
    echo " SPEED / CORE EDIT"
    echo "=========================================="
    echo
    echo "  1) Normal          1.00x"
    echo "  2) Nightcore       1.25x"
    echo "  3) Morningcore     0.85x"
    echo "  4) Speed-up        1.10x"
    echo "  5) Slow-down       0.90x"
    echo "  6) Double-time     2.00x"
    echo "  7) Half-time       0.50x"
    echo "  8) Custom"
    echo
    printf "Choose [1]: "
    IFS= read -r choice
    choice="${choice:-1}"

    case "$choice" in
        1)
            EDIT_NAME="normal"
            SPEED="1.00"
            ;;
        2)
            EDIT_NAME="nightcore"
            SPEED="1.25"
            ;;
        3)
            EDIT_NAME="morningcore"
            SPEED="0.85"
            ;;
        4)
            EDIT_NAME="speedup"
            SPEED="1.10"
            ;;
        5)
            EDIT_NAME="slowdown"
            SPEED="0.90"
            ;;
        6)
            EDIT_NAME="doubletime"
            SPEED="2.00"
            ;;
        7)
            EDIT_NAME="halftime"
            SPEED="0.50"
            ;;
        8)
            EDIT_NAME="custom"
            while :; do
                printf "Enter speed multiplier (0.50 - 2.00): "
                IFS= read -r SPEED

                if awk -v s="$SPEED" 'BEGIN {
                    exit !(s >= 0.50 && s <= 2.00)
                }'; then
                    break
                fi

                echo "${YELLOW}Please enter a number between 0.50 and 2.00.${RESET}"
            done
            ;;
        *)
            echo "${YELLOW}Invalid choice. Using Normal.${RESET}"
            EDIT_NAME="normal"
            SPEED="1.00"
            ;;
    esac
}

choose_output() {
    local default_dir="${INPUT_DIR}/AudioEdits"

    echo
    printf "Output folder [%s]:\n> " "$default_dir"
    IFS= read -r OUTPUT_DIR
    OUTPUT_DIR="${OUTPUT_DIR:-$default_dir}"

    case "$OUTPUT_DIR" in
        \"*\") OUTPUT_DIR="${OUTPUT_DIR#\"}"; OUTPUT_DIR="${OUTPUT_DIR%\"}" ;;
        \'*\') OUTPUT_DIR="${OUTPUT_DIR#\'}"; OUTPUT_DIR="${OUTPUT_DIR%\'}" ;;
    esac

    case "$OUTPUT_DIR" in
        "~"/*) OUTPUT_DIR="$HOME/${OUTPUT_DIR#~/}" ;;
    esac

    mkdir -p "$OUTPUT_DIR"
}

# FFmpeg atempo supports 0.5-2.0 per filter.
# Our menu intentionally stays inside that range, so no
# duration/sample-rate arithmetic is necessary.
build_filter() {
    if [ "$SPEED" = "1.00" ]; then
        AUDIO_FILTER=""
    else
        AUDIO_FILTER="atempo=${SPEED}"
    fi
}

encode_mp3() {
    input="$1"
    output="$2"

    if [ -n "$AUDIO_FILTER" ]; then
        "$FFMPEG" -hide_banner -loglevel error -y \
            -i "$input" \
            -map_metadata 0 \
            -vn \
            -af "$AUDIO_FILTER" \
            -c:a libmp3lame \
            -q:a 0 \
            "$output"
    else
        "$FFMPEG" -hide_banner -loglevel error -y \
            -i "$input" \
            -map_metadata 0 \
            -vn \
            -c:a libmp3lame \
            -q:a 0 \
            "$output"
    fi
}

encode_ogg() {
    input="$1"
    output="$2"

    if [ -n "$AUDIO_FILTER" ]; then
        "$FFMPEG" -hide_banner -loglevel error -y \
            -i "$input" \
            -map_metadata 0 \
            -vn \
            -af "$AUDIO_FILTER" \
            -c:a libvorbis \
            -q:a 10 \
            "$output"
    else
        "$FFMPEG" -hide_banner -loglevel error -y \
            -i "$input" \
            -map_metadata 0 \
            -vn \
            -c:a libvorbis \
            -q:a 10 \
            "$output"
    fi
}

encode_aac() {
    input="$1"
    output="$2"

    if [ -n "$AUDIO_FILTER" ]; then
        "$FFMPEG" -hide_banner -loglevel error -y \
            -i "$input" \
            -map_metadata 0 \
            -vn \
            -af "$AUDIO_FILTER" \
            -c:a aac \
            -b:a 320k \
            "$output"
    else
        "$FFMPEG" -hide_banner -loglevel error -y \
            -i "$input" \
            -map_metadata 0 \
            -vn \
            -c:a aac \
            -b:a 320k \
            "$output"
    fi
}

encode_file() {
    input="$1"
    format="$2"
    base="$3"

    case "$format" in
        mp3)
            output="${OUTPUT_DIR}/${base}.mp3"
            echo "    MP3 -> $(basename "$output")"
            encode_mp3 "$input" "$output"
            ;;
        ogg)
            output="${OUTPUT_DIR}/${base}.ogg"
            echo "    OGG -> $(basename "$output")"
            encode_ogg "$input" "$output"
            ;;
        aac)
            # AAC is stored as M4A because raw .aac is less convenient
            # for metadata and general music-library use.
            output="${OUTPUT_DIR}/${base}.m4a"
            echo "    AAC -> $(basename "$output")"
            encode_aac "$input" "$output"
            ;;
        *)
            return 1
            ;;
    esac
}

process_files() {
    local successful=0
    local failed=0
    local input
    local filename
    local stem
    local base
    local format

    echo
    echo "=========================================="
    echo " PROCESSING"
    echo "=========================================="
    echo

    # Avoid shell word-splitting of filenames by using find + while.
    while IFS= read -r -d '' input; do
        filename="$(basename "$input")"
        stem="${filename%.*}"

        if [ "$EDIT_NAME" = "normal" ]; then
            base="$stem"
        else
            base="${stem}-${EDIT_NAME}"
        fi

        echo "${CYAN}▶ ${filename}${RESET}"

        for format in $FORMATS; do
            if encode_file "$input" "$format" "$base"; then
                echo "      ${GREEN}✓ Complete${RESET}"
                successful=$((successful + 1))
            else
                echo "      ${RED}✗ Failed (${format})${RESET}"
                failed=$((failed + 1))
            fi
        done

        echo
    done < <(find "$INPUT_DIR" -maxdepth 1 -type f -iname '*.flac' -print0)

    echo "=========================================="
    echo " COMPLETE"
    echo "=========================================="
    echo "Successful outputs : ${successful}"
    echo "Failed outputs     : ${failed}"
    echo
    echo "Output:"
    echo "  ${OUTPUT_DIR}"
    echo "=========================================="
}

main() {
    header
    choose_input
    choose_formats
    choose_edit
    choose_output
    build_filter

    echo
    echo "=========================================="
    echo " SUMMARY"
    echo "=========================================="
    echo "Input : ${INPUT_DIR}"
    echo "Output: ${OUTPUT_DIR}"
    echo "Edit  : ${EDIT_NAME}"
    echo "Speed : ${SPEED}x"
    echo "Formats: ${FORMATS}"
    echo "=========================================="
    echo
    printf "Start processing? [Y/n]: "
    IFS= read -r confirm
    confirm="${confirm:-Y}"

    case "$confirm" in
        Y|y|yes|YES|Yes)
            ;;
        *)
            echo "Cancelled."
            exit 0
            ;;
    esac

    mkdir -p "$OUTPUT_DIR"
    process_files
}

main "$@"
'''

path = Path("/mnt/data/audio-edit-factory-v1.sh")
path.write_text(script, encoding="utf-8")
path.chmod(0o755)

# Also make a small README with the exact invocation.
readme = r'''# Audio Edit Factory v1

## Install

```bash
brew install ffmpeg