#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$ANDROID_HOME" ]]; then
  echo 'Set ANDROID_HOME to the Android SDK directory.' >&2
  exit 1
fi
command -v go >/dev/null || { echo 'Go 1.26+ is required to build embedded WireGuard.' >&2; exit 1; }
tools_dir="$repo_dir/build/wireguard-tools"
mkdir -p "$tools_dir" "$repo_dir/android/app/libs"
mobile_version=v0.0.0-20261011034528-197770444867
if [[ ! -x "$tools_dir/gomobile" || ! -x "$tools_dir/gobind" || ! -f "$tools_dir/$mobile_version" ]]; then
  GOBIN="$tools_dir" go install "golang.org/x/mobile/cmd/gomobile@$mobile_version"
  GOBIN="$tools_dir" go install "golang.org/x/mobile/cmd/gobind@$mobile_version"
  touch "$tools_dir/$mobile_version"
fi
export PATH="$tools_dir:$PATH"
cd "$repo_dir/native/wireguard"
gomobile bind -target=android/arm,android/arm64,android/amd64 -androidapi=24 \
  -javapkg=pro.surpin.wiredash.wireguard \
  -o "$repo_dir/android/app/libs/wireguard.aar" .
