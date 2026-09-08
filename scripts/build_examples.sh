#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="${BUILD_ROOT:-$PROJECT_DIR}"
if [[ "$BUILD_ROOT" != /* ]]; then
  BUILD_ROOT="$PROJECT_DIR/$BUILD_ROOT"
fi

BUILD_DIR="$BUILD_ROOT/build-counter" \
  "$SCRIPT_DIR/build_tool.sh" examples/counter.toml counter
BUILD_DIR="$BUILD_ROOT/build-cpu65c02" \
  "$SCRIPT_DIR/build_tool.sh" examples/cpu65c02.toml cpu65c02

cat <<EOF
Built example tools:
  $BUILD_ROOT/build-counter/lcsim-gui
  $BUILD_ROOT/build-cpu65c02/lcsim-gui

Run a GUI tool with, for example:
  $BUILD_ROOT/build-cpu65c02/lcsim-gui --technology lvc
EOF
