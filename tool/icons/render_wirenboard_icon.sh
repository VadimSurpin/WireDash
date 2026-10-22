#!/usr/bin/env bash
# Render the selected Wiren Board icon and regenerate platform launcher icons.
# Needs Python 3 with CairoSVG (pip install cairosvg) and the Cairo library.
# ZIGDASH_FLUTTER can select the Flutter executable.
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
# flutter_launcher_icons also replaces service icons. Preserve Quick Settings
# tiles, which need their own monochrome drawable rather than a launcher icon.
cp android/app/src/main/AndroidManifest.xml "$tmp/AndroidManifest.xml"
cleanup() {
  cp "$tmp/AndroidManifest.xml" android/app/src/main/AndroidManifest.xml
  rm -rf "$tmp"
}
trap cleanup EXIT
python3 - <<'PY'
from pathlib import Path
import cairosvg

output = Path('assets/icon/wirenboard-play')
output.mkdir(parents=True, exist_ok=True)
for name in ('icon', 'foreground', 'monochrome'):
    cairosvg.svg2png(
        url=f'tool/icons/wirenboard-play/{name}.svg',
        write_to=str(output / f'{name}.png'),
        output_width=1024,
        output_height=1024,
    )
PY
tool/flutter pub run flutter_launcher_icons
cp assets/icon/wirenboard-play/icon.png fastlane/metadata/android/en-US/images/icon.png
