# Audio Edit Factory — macOS

## Install

```bash
brew install ffmpeg
```

Make both scripts executable:

```bash
chmod +x audio-edit-factory.sh Audio-Edit-Factory.command
```

## Use

1. Create a folder containing FLAC, ALAC, WAV, AIFF or M4A files.
2. Drag the folder onto `Audio-Edit-Factory.command`.
3. A new `AudioEdits` folder is created inside the source folder.

Output:

```text
AudioEdits/
├── mp3/
│   ├── nightcore/
│   ├── daycore/
│   ├── morningcore/
│   ├── speedup/
│   ├── slowdown/
│   ├── tempofast/
│   └── temposlow/
├── manifests/
│   ├── audio-edits-*.json
│   └── audio-edits-*.csv
└── logs/
    └── audio-edits-*.log
```

## Edit definitions

- Nightcore: 1.20× speed + pitch
- Daycore: 0.85× speed + pitch
- Morningcore: 0.90× speed + pitch
- Speedup: 1.10× speed + pitch
- Slowdown: 0.90× speed + pitch
- TempoFast: 1.20× tempo, pitch preserved
- TempoSlow: 0.85× tempo, pitch preserved

## Change compression

Default:

```bash
VBR_QUALITY=2
```

Smaller files:

```bash
VBR_QUALITY=4 ./audio-edit-factory.sh "/path/to/folder"
```

For an especially compact library:

```bash
VBR_QUALITY=5 ./audio-edit-factory.sh "/path/to/folder"
```

LAME's VBR quality scale is inverse: lower number = higher quality/larger files.

## Change edit speeds

Examples:

```bash
NIGHTCORE=1.25
DAYCORE=0.80
MORNINGCORE=0.92
```

The original files are never overwritten or modified.

## Important

This pipeline does not create a WAV/AIFF intermediate because FFmpeg decodes the lossless source directly into its processing pipeline. That avoids an unnecessary temporary file while retaining the lossless source as the master.
