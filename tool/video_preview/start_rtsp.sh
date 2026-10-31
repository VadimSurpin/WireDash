#!/usr/bin/env bash
set -euo pipefail
# A synthetic, authenticated H.264 stream. Runs on GitHub, never on a DVR.
mkdir -p build/video-preview
cd build/video-preview
curl --fail --location --retry 3 --output mediamtx.tar.gz \
  https://github.com/bluenviron/mediamtx/releases/download/v1.21.3/mediamtx_v1.21.3_linux_amd64.tar.gz
python3 - <<'PY'
from pathlib import Path
import hashlib,tarfile
archive=Path('mediamtx.tar.gz')
assert hashlib.file_digest(archive.open('rb'),'sha256').hexdigest() == '0a2ea7eba96023631efa1bea7804823a9145b043b6646a8a05798d4ac24ed635'
with tarfile.open(archive) as package:
    package.extract('mediamtx',filter='data')
PY
cat > mediamtx.yml <<'YAML'
logLevel: info
rtsp: yes
rtspAddress: :8554
rtspTransports: [tcp]
rtspAuthMethods: [digest]
rtmp: no
hls: no
webrtc: no
srt: no
authInternalUsers:
  - user: publisher
    pass: publish-test
    permissions:
      - action: publish
        path: camera
  - user: viewer
    pass: viewer-test
    permissions:
      - action: read
        path: camera
paths:
  camera:
YAML
./mediamtx mediamtx.yml > mediamtx.log 2>&1 &
echo "$!" > mediamtx.pid
python3 - <<'PY'
import socket,time
for attempt in range(30):
    try:
        with socket.create_connection(('127.0.0.1',8554),timeout=1): break
    except OSError: time.sleep(.5)
else: raise RuntimeError('RTSP server failed to start')
PY
ffmpeg -hide_banner -loglevel warning -re -f lavfi -i 'testsrc2=size=320x180:rate=8' \
  -an -c:v libx264 -preset ultrafast -tune zerolatency -pix_fmt yuv420p -g 8 \
  -f rtsp -rtsp_transport tcp rtsp://publisher:publish-test@127.0.0.1:8554/camera \
  > ffmpeg.log 2>&1 &
echo "$!" > ffmpeg.pid
