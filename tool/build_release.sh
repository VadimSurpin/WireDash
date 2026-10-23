#!/usr/bin/env bash
# Build a signed release artifact for WireDash.
#
# Requires android/key.properties + android/zigdash-release.jks (both gitignored;
# see android/app/build.gradle.kts for how they're consumed). If key.properties
# is absent the build falls back to debug signing.
#
# --no-tree-shake-icons is REQUIRED: the app builds IconData from runtime values
# (user-selectable dashboard/panel icons), which release icon tree-shaking rejects.
#
# Usage:
#   tool/build_release.sh apk     # -> build/app/outputs/flutter-apk/app-release.apk
#   tool/build_release.sh bundle  # -> build/app/outputs/bundle/playRelease/app-play-release.aab (Play Store)
#   tool/build_release.sh github  # -> build/github-release/wiredash-<version>-<abi>.apk
#                                 #    per-ABI APKs for GitHub releases and IzzyOnDroid;
set -euo pipefail
cd "$(dirname "$0")/.."

# The Play build carries billing for ZigDash Pro (history-2.7.md). Pro shows
# only once ZIGDASH_PRO_LIVE=1 (the payments profile and product exist).
PLAY=(--dart-define=ZIGDASH_FLAVOR=play)
if [[ "${ZIGDASH_PRO_LIVE:-}" == 1 ]]; then PLAY+=(--dart-define=ZIGDASH_PRO_LIVE=true); fi

TARGET="${1:-apk}"
if [[ "$TARGET" == github ]]; then
  tool/flutter build apk --release --split-per-abi --no-tree-shake-icons \
    --flavor foss --dart-define=ZIGDASH_FLAVOR=foss
  VERSION="$(sed -n 's/^version: \([^+]*\).*/\1/p' pubspec.yaml)"
  OUT=build/github-release; rm -rf "$OUT"; mkdir -p "$OUT"
  for abi in arm64-v8a armeabi-v7a x86_64; do
    cp "build/app/outputs/flutter-apk/app-$abi-foss-release.apk" "$OUT/wiredash-$VERSION-$abi.apk"
  done
  (cd "$OUT" && shasum -a 256 *.apk > SHA256SUMS)
  ls -la "$OUT"; exit 0
fi
case "$TARGET" in
  apk)    tool/flutter build apk --release --no-tree-shake-icons --flavor play "${PLAY[@]}" ;;
  bundle) tool/flutter build appbundle --release --no-tree-shake-icons --flavor play "${PLAY[@]}" ;;
  *) echo "usage: $0 [apk|bundle|github]"; exit 2 ;;
esac
