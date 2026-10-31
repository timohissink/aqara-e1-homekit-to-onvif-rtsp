#!/usr/bin/env bash
# Check resolution, aspect ratio and decode errors of a go2rtc RTSP stream.
# Usage: RTSP_USER=rtspviewer RTSP_PASSWORD=... ./stream_check.sh 192.168.1.10 camera1 [seconds]
# The URL (with credentials) is never printed.
set -uo pipefail
HOST="${1:?go2rtc host}"; STREAM="${2:?stream name}"; SECS="${3:-20}"
enc(){ python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$1"; }
URL="rtsp://$(enc "${RTSP_USER:-}"):$(enc "${RTSP_PASSWORD:-}")@$HOST:8554/$STREAM?video"
redact(){ sed -E 's#rtsp://[^ ]*#rtsp://<redacted>#g'; }

echo "== $STREAM: codec / resolution / SAR / DAR (N/A = square pixels)"
timeout 30 ffprobe -v error -rtsp_transport tcp -select_streams v \
  -show_entries stream=codec_name,profile,width,height,sample_aspect_ratio,display_aspect_ratio \
  -of default=nw=1 "$URL" 2>&1 | redact

echo "== $STREAM: decode for ${SECS}s"
OUT="$(timeout $((SECS+30)) ffmpeg -hide_banner -loglevel error -stats -rtsp_transport tcp -i "$URL" -t "$SECS" -an -f null - 2>&1 | tr '\r' '\n' | redact)"
echo "decode errors : $(grep -cE 'error while decoding|concealing' <<<"$OUT")"
echo "last stats    : $(grep -oE 'frame= *[0-9]+ fps= *[0-9.]+' <<<"$OUT" | tail -1)"
echo "(a few errors right after connecting, before the first keyframe, are normal)"
