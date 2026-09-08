#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/build_tool.sh [design.toml] [name]

Builds the headless simulator, GUI and oscilloscope for one TOML design.
The generated files are placed in BUILD (default: build-<name>).

Environment:
  RAYLIB_DIR  raylib checkout (default: ../third_party/raylib)
  BUILD_DIR   output directory (relative to LcSim unless absolute)
  CXX, CXXFLAGS, RAYLIB_CFLAGS, RAYLIB_LIBS

Examples:
  scripts/build_tool.sh examples/counter.toml counter
  BUILD_DIR=build-cpu scripts/build_tool.sh examples/cpu65c02.toml cpu65c02
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

DESIGN="${1:-examples/counter.toml}"
NAME="${2:-$(basename "${DESIGN%.*}")}"
RAYLIB_DIR="${RAYLIB_DIR:-$PROJECT_DIR/../third_party/raylib}"
BUILD_DIR="${BUILD_DIR:-build-$NAME}"

if [[ "$DESIGN" != /* ]]; then
  DESIGN="$PROJECT_DIR/$DESIGN"
fi
if [[ "$RAYLIB_DIR" != /* ]]; then
  RAYLIB_DIR="$PROJECT_DIR/$RAYLIB_DIR"
fi
if [[ "$BUILD_DIR" != /* ]]; then
  BUILD_DIR="$PROJECT_DIR/$BUILD_DIR"
fi
if [[ ! -f "$DESIGN" ]]; then
  echo "error: TOML design not found: $DESIGN" >&2
  exit 2
fi

RAYLIB_HEADER="$RAYLIB_DIR/src/raylib.h"
if [[ ! -f "$RAYLIB_HEADER" ]]; then
  echo "error: raylib header not found: $RAYLIB_HEADER" >&2
  echo "       set RAYLIB_DIR to the raylib checkout" >&2
  exit 2
fi

if [[ ! -e "$RAYLIB_DIR/src/libraylib.a" && \
      ! -e "$RAYLIB_DIR/src/libraylib.so" && \
      ! -e "$RAYLIB_DIR/src/libraylib.dylib" ]]; then
  echo "error: raylib library not found under $RAYLIB_DIR/src" >&2
  echo "       build raylib first (expected libraylib.a/.so/.dylib)" >&2
  exit 2
fi

RAYLIB_CFLAGS="${RAYLIB_CFLAGS:--I$RAYLIB_DIR/src}"
RAYLIB_LIBS="${RAYLIB_LIBS:--L$RAYLIB_DIR/src -lraylib -lGL -lm -lpthread -ldl -lrt -lX11}"

echo "design: $DESIGN"
echo "output: $BUILD_DIR"
echo "raylib: $RAYLIB_DIR"
make -C "$PROJECT_DIR" \
  DESIGN="$DESIGN" \
  BUILD="$BUILD_DIR" \
  RAYLIB_DIR="$RAYLIB_DIR" \
  RAYLIB_CFLAGS="$RAYLIB_CFLAGS" \
  RAYLIB_LIBS="$RAYLIB_LIBS" \
  tools

echo "ready:"
echo "  $BUILD_DIR/lcsim"
echo "  $BUILD_DIR/lcsim-gui"
