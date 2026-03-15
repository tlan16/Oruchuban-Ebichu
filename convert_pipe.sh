#!/usr/bin/env bash

# Usage Examples:
## find . -name "*.mp4" -type f | parallel --ungroup convert_pipe.sh {} {.}.mp4
## ./convert_pipe.sh input.mp4 output.mp4

set -e

if [ "$#" -ne 2 ]; then
  echo "Usage: ./convert_pipe.sh input.mp4 output.mp4"
  exit 1
fi

# Dry run handling
DRY_RUN=${DRY_RUN:-false}

# handle --dry-run as first arg (optional)
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  shift
fi

if [ "$#" -ne 2 ]; then
  echo "Usage: ./convert_pipe.sh [--dry-run] input.mp4 output.mp4"
  exit 1
fi

if [ "${DRY_RUN}" != false ]; then
  echo "[DRY RUN] enabled"
fi

echo "Input: $(realpath "$1")"
echo "Output: $(realpath "$2")"

input_video_codec="$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "${1}")"
input_audio_codec="$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "${1}")"
OUTPUT_EXT="${2##*.}"
TEMP_FILE="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)"."${OUTPUT_EXT}"

# validation
if [ "${OUTPUT_EXT}" = "" ]; then
  echo "Invalid output of ${2}, skipping ..."
  return 1
fi

echo "Start converting \"$(basename "$1")\" to temp file: ${TEMP_FILE}"
echo ""

# Detech supported encoders
support_av1_qsv=false
support_hevc_nvenc=false
support_hevc_videotoolbox=false

encoders="$(ffmpeg -encoders 2>/dev/null)"

if echo "$encoders" | grep -q '^[^ ]* V.* av1_qsv '; then
  support_av1_qsv=true
fi
if echo "$encoders" | grep -q '^[^ ]* V.* hevc_nvenc '; then
  support_hevc_nvenc=true
fi
if echo "$encoders" | grep -q '^[^ ]* V.* hevc_videotoolbox '; then
  support_hevc_videotoolbox=true
fi

echo "Capabilities: av1_qsv=${support_av1_qsv}, hevc_nvenc=${support_hevc_nvenc}, hevc_videotoolbox=${support_hevc_videotoolbox}"

# Select video codec
# If input is already AV1 and av1_qsv is available → copy video (no re-encode)
if [ "${input_video_codec}" = "av1" ] && [ "${support_av1_qsv}" = true ]; then
  codec_video="copy"
  video_extra_args=()
  echo "Input is already AV1 and AV1 QSV is available → video copy (no re-encode)"

else
  # Normal encoder preference
  if [ "${support_av1_qsv}" = true ]; then
    codec_video="av1_qsv"
    AV1_GQ="${AV1_GQ:-30}"
    video_extra_args=(-pix_fmt p010le -preset slow -global_quality:v "${AV1_GQ}")
    echo "Using av1_qsv (Intel Arc AV1)"
  elif [ "${support_hevc_nvenc}" = true ]; then
    codec_video="hevc_nvenc"
    video_extra_args=(-preset slow -q:v 19)
    echo "Using hevc_nvenc (NVIDIA H.265)"
  elif [ "${support_hevc_videotoolbox}" = true ]; then
    codec_video="hevc_videotoolbox"
    video_extra_args=(-q:v 75)
    echo "Using hevc_videotoolbox (macOS H.265)"
  else
    codec_video="libx265"
    video_extra_args=(-crf 23)
    echo "Using libx265 (CPU H.265)"
  fi

  # Optional: HEVC passthrough when we are not doing an AV1 pass
  if [ "${input_video_codec}" = "hevc" ] && [ "${codec_video}" != "av1_qsv" ]; then
    codec_video="copy"
    video_extra_args=()
    echo "Input is already HEVC and we are not forcing AV1 → video copy"
  fi
fi

# Select audio codec
codec_audio="libopus"
# Reasonable default for stereo TV/anime: ~64 kbps Opus VBR
audio_extra_args=(-b:a 20k -vbr on -application audio)

if [ "${input_audio_codec}" = "opus" ]; then
  codec_audio="copy"
  audio_extra_args=()
  echo "Input audio is Opus → audio copy"
else
  echo "Input audio is ${input_audio_codec} → re-encode to Opus (libopus @ 64k VBR)"
fi

echo "Final: codec_video=${codec_video}, codec_audio=${codec_audio}"
echo "Video extra args: ${video_extra_args[*]}"
echo "Audio extra args: ${audio_extra_args[*]}"

if [ "${DRY_RUN}" = false ]; then
  ffmpeg -hide_banner \
    -i "${1}" \
    -c:v "${codec_video}" "${video_extra_args[@]}" \
    -c:a "${codec_audio}" "${audio_extra_args[@]}" \
    -y \
    "${TEMP_FILE}"

  mv -v "${TEMP_FILE}" "${2}"
else
  echo "[DRY RUN] Skipping encode and move"
fi

