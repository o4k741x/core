# Audio Edit Factory — macOS

Drag a folder of music onto `Audio-Edit-Factory.command`.

## Inputs

- FLAC
- ALAC / M4A
- WAV
- AIFF / AIF
- AAC (`.aac`)
- AAC inside `.m4a` / `.mp4`
- OGG Vorbis (`.ogg`, `.oga`)

AAC files at 320 kbps are accepted as sources. OGG Vorbis is also accepted. The source codec and detected bitrate are recorded in the JSON/CSV manifest.

## Outputs

Each source gets:

- Nightcore — 1.20× speed + pitch when Rubber Band is available
- Daycore — 0.85× speed + pitch
- Morningcore — 0.90× speed + pitch
- Speedup — 1.10× speed + pitch
- Slowdown — 0.90× speed + pitch
- TempoFast — 1.20× tempo, pitch preserved
- TempoSlow — 0.85× tempo, pitch preserved

All outputs are MP3 VBR using LAME quality 2 by default.

## Install

```bash
brew install ffmpeg
```

For true independent speed + pitch transformations, use an FFmpeg build that contains the `rubberband` filter. The script detects it automatically. Without it, the speed/pitch variants safely fall back to tempo-only processing and log that fact.

## Smaller files

```bash
VBR_QUALITY=4 ./audio-edit-factory.sh /path/to/music
```

Or:

```bash
VBR_QUALITY=5 ./audio-edit-factory.sh /path/to/music
```

Lower LAME VBR quality numbers mean higher quality/larger files.

## Important

The original files are never overwritten. Every MP3 is generated directly from the original source, not from another MP3.
