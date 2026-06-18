#!/usr/bin/env bash
# install.sh — build and install the full nomos-studio stack.
#
# Usage:
#   ./install.sh                        # installs to ~/.local/nomos-studio
#   PREFIX=/opt/nomos-studio ./install.sh
#
# What it builds and installs:
#   JVM chain:  nomos-maths → nomos-topology → alembic → nous uberjar
#   C++ chain:  nous-sidecar binary
#               aion binary (via cmake --preset release)
#   Script:     bin/nomos-studio → PREFIX/bin/nomos-studio
#
# Requirements:
#   - lein on PATH (Leiningen)
#   - JAVA_HOME set (or /opt/homebrew/opt/openjdk auto-detected)
#   - cmake ≥ 3.20 on PATH
#   - C++20 compiler (Clang 15+ or GCC 12+)
#
# The script is idempotent: re-running rebuilds and re-installs everything.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$(dirname "$SCRIPT_DIR")"
PREFIX="${PREFIX:-$HOME/.local/nomos-studio}"

if [[ -z "${JAVA_HOME:-}" ]]; then
    if [[ -d /opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home ]]; then
        export JAVA_HOME=/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home
    fi
fi

log() { printf '\033[1;34m[nomos-studio]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[nomos-studio] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

command -v lein  >/dev/null || die "lein not found — install Leiningen"
command -v cmake >/dev/null || die "cmake not found — install CMake ≥ 3.20"
[[ -n "${JAVA_HOME:-}" ]]  || die "JAVA_HOME not set and could not be detected"

log "Installing to: $PREFIX"
log "JAVA_HOME:     $JAVA_HOME"
mkdir -p "$PREFIX/bin" "$PREFIX/lib/nous"

# ---------------------------------------------------------------------------
# JVM chain — lein install in dependency order, then nous uberjar
# ---------------------------------------------------------------------------

lein_install() {
    local dir="$1" name="$2"
    log "lein install: $name"
    (cd "$SRC_DIR/$dir" && lein install) || die "lein install failed for $name"
}

lein_install nomos-maths    nomos-maths
lein_install nomos-topology nomos-topology
lein_install alembic        alembic

log "lein uberjar: nous"
(cd "$SRC_DIR/nous" && lein uberjar) || die "lein uberjar failed for nous"

NOUS_JAR=$(ls "$SRC_DIR/nous/target/uberjar/nous-"*"-standalone.jar" 2>/dev/null | head -1)
[[ -f "$NOUS_JAR" ]] || die "nous standalone jar not found after uberjar"

log "Installing nous jar → $PREFIX/lib/nous/nous-standalone.jar"
install -m 644 "$NOUS_JAR" "$PREFIX/lib/nous/nous-standalone.jar"

# ---------------------------------------------------------------------------
# C++ — nous-sidecar
# ---------------------------------------------------------------------------

log "cmake configure: nous-sidecar"
cmake -S "$SRC_DIR/nous" \
      -B "$SRC_DIR/nous/build" \
      -DCMAKE_BUILD_TYPE=Release \
    || die "cmake configure failed for nous-sidecar"

log "cmake build: nous-sidecar"
cmake --build "$SRC_DIR/nous/build" --parallel \
    || die "cmake build failed for nous-sidecar"

SIDECAR_BIN="$SRC_DIR/nous/build/cpp/nous-sidecar/nous-sidecar"
[[ -f "$SIDECAR_BIN" ]] || die "nous-sidecar binary not found at $SIDECAR_BIN"

log "Installing nous-sidecar → $PREFIX/bin/nous-sidecar"
install -m 755 "$SIDECAR_BIN" "$PREFIX/bin/nous-sidecar"

# ---------------------------------------------------------------------------
# C++ — aion
# ---------------------------------------------------------------------------

log "cmake configure: aion"
cmake -S "$SRC_DIR/aion" \
      --preset release \
      -DCMAKE_INSTALL_PREFIX="$PREFIX" \
    || die "cmake configure failed for aion"

log "cmake build: aion"
cmake --build "$SRC_DIR/aion/build/release" --parallel \
    || die "cmake build failed for aion"

log "cmake install: aion → $PREFIX/bin/aion"
cmake --install "$SRC_DIR/aion/build/release" \
    || die "cmake install failed for aion"

# ---------------------------------------------------------------------------
# Start script — copy checked-in bin/nomos-studio to PREFIX
# ---------------------------------------------------------------------------

log "Installing start script → $PREFIX/bin/nomos-studio"
install -m 755 "$SCRIPT_DIR/bin/nomos-studio" "$PREFIX/bin/nomos-studio"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------

log ""
log "Install complete."
log ""
log "  $PREFIX/bin/aion"
log "  $PREFIX/bin/nous-sidecar"
log "  $PREFIX/bin/nomos-studio"
log "  $PREFIX/lib/nous/nous-standalone.jar"
log ""
log "Add $PREFIX/bin to your PATH, then run: nomos-studio"
