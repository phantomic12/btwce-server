#!/bin/sh
# start.sh — launch the BTWCE Minecraft server.
#
# Self-bootstrapping: on first run it downloads a small runtime bundle
# (Legacy Fabric 0.19.3 + 11 libraries + Mojang's 1.6.4 server jar) from
# the project's GitHub release, then launches the server headless.
#
# Requires:
#   - Java 17+ on the system (BTWCE 3.1.0 declares depends: java >=17 <=21)
#   - bash 4+ (we re-exec under bash because the rest of the script uses
#     bash features — Pelican-style hosts that call `sh start.sh` still work)
#   - curl, tar, awk, unzip
#   - about 30 MB free disk (bundle + extracted)
#
# Re-runs are instant: the bundle is only downloaded if files are missing.

# POSIX-sh trampoline: re-exec under bash if we're not already running
# under it. Pelican (and some other panels) invoke this script as
# `sh start.sh`, which on Debian is dash and rejects bashisms like
# `set -o pipefail`. This makes the script portable.
if [ -z "${BTWCE_STARTED:-}" ]; then
  export BTWCE_STARTED=1
  if [ -z "${BASH_VERSION:-}" ]; then
    # Try bash, fall back to ash/bash anywhere on PATH
    for _b in /bin/bash /usr/bin/bash /usr/local/bin/bash bash; do
      if command -v "$_b" >/dev/null 2>&1 || [ -x "$_b" ]; then
        exec "$_b" "$0" "$@"
      fi
    done
    echo "ERROR: bash is required but not found. Install bash and re-run." >&2
    exit 1
  fi
fi

# From here on, we're guaranteed to be in bash.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# --- preflight: required tools ---
for tool in curl tar awk unzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' is required but not installed. Install it and re-run." >&2
    exit 1
  fi
done

# --- preflight: Java 17+ ---
find_java_17() {
  local candidate=""
  if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
    candidate="$JAVA_HOME/bin/java"
  elif [[ -n "${BTWCE_JAVA:-}" && -x "$BTWCE_JAVA" ]]; then
    candidate="$BTWCE_JAVA"
  else
    candidate=$(ls -d /usr/lib/jvm/*/bin/java /opt/*/bin/java 2>/dev/null \
                  | sort -r | head -1 || true)
  fi
  if [[ -z "$candidate" ]] && command -v java >/dev/null 2>&1; then
    candidate="$(command -v java)"
  fi
  echo "$candidate"
}

JAVA_BIN="$(find_java_17)"
if [[ -z "$JAVA_BIN" ]] || [[ ! -x "$JAVA_BIN" ]]; then
  cat >&2 <<EOF
ERROR: No Java binary found.

BTWCE 3.1.0 requires Java 17-21. Install one of:

  Debian/Ubuntu:  sudo apt install openjdk-17-jre-headless
  Fedora/RHEL:    sudo dnf install java-17-openjdk-headless
  macOS:          brew install openjdk@17

Then either set JAVA_HOME, or BTWCE_JAVA, or put java on your PATH.
EOF
  exit 1
fi

JAVA_MAJOR=$("$JAVA_BIN" -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
if [[ -z "$JAVA_MAJOR" || "$JAVA_MAJOR" -lt 17 ]]; then
  echo "ERROR: $JAVA_BIN is Java $JAVA_MAJOR — BTWCE 3.1.0 requires Java 17-21." >&2
  exit 1
fi
if [[ "$JAVA_MAJOR" -gt 21 ]]; then
  echo "WARNING: $JAVA_BIN is Java $JAVA_MAJOR — BTWCE declares depends: java <=21." >&2
fi
echo "[1/3] Using Java: $("$JAVA_BIN" -version 2>&1 | head -1)"

# --- preflight: runtime files ---
# We need: downloads/mojang-1.6.4-server.jar, libraries/, fabric-server-launch.jar
# The mod is already in mods/btwce-3.1.0.jar (it's in the repo).
NEED_BUNDLE=0
[[ -f "downloads/mojang-1.6.4-server.jar" ]] || NEED_BUNDLE=1
[[ -d "libraries/net/fabricmc/fabric-loader" ]] || NEED_BUNDLE=1
[[ -f "fabric-server-launch.jar" ]] || NEED_BUNDLE=1

if [[ $NEED_BUNDLE -eq 1 ]]; then
  echo "[2/3] Runtime files missing, downloading bundle from GitHub release..."

  BUNDLE_VERSION="v1.0.0"
  BUNDLE_URL="https://github.com/phantomic12/btwce-server/releases/download/${BUNDLE_VERSION}/libraries-bundle.tar.xz"
  BUNDLE_SHA256="6267d0d942b375f12ce5eadd63c29f8643ab7f49c0647eeeac7c16632e9eabf4"
  TMP_TAR="$(mktemp --suffix=.tar.xz)"

  if ! curl -fL --retry 3 --connect-timeout 15 -o "$TMP_TAR" "$BUNDLE_URL"; then
    echo "ERROR: failed to download $BUNDLE_URL" >&2
    rm -f "$TMP_TAR"
    exit 1
  fi

  # Verify checksum (sha256sum is part of coreutils, always present)
  if ! echo "$BUNDLE_SHA256  $TMP_TAR" | sha256sum -c - >/dev/null 2>&1; then
    echo "ERROR: bundle checksum mismatch — refusing to extract" >&2
    rm -f "$TMP_TAR"
    exit 1
  fi

  echo "  extracting..."
  tar -xJf "$TMP_TAR"
  rm -f "$TMP_TAR"
  echo "  done."
else
  echo "[2/3] Runtime files present, skipping download."
fi

# Sanity check: if the launch jar is missing for some reason, fail loud
for f in downloads/mojang-1.6.4-server.jar fabric-server-launch.jar mods/btwce-3.1.0.jar; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: required file missing after bootstrap: $f" >&2
    exit 1
  fi
done

# --- launch ---
echo "[3/3] Starting BTWCE server (MC 1.6.4 + Legacy Fabric 0.19.3 + BTWCE 3.1.0)..."
echo "      console is in this terminal. Type 'help' for commands. Ctrl+C stops."
echo
mkdir -p logs
exec "$JAVA_BIN" \
  -Djava.awt.headless=true \
  -Dfabric.gameJarPath=downloads/mojang-1.6.4-server.jar \
  -Xms1G -Xmx4G \
  -XX:+UseG1GC \
  -XX:+ParallelRefProcEnabled \
  -XX:MaxGCPauseMillis=200 \
  -XX:+UnlockExperimentalVMOptions \
  -XX:+DisableExplicitGC \
  -XX:+AlwaysPreTouch \
  -XX:G1NewSizePercent=30 \
  -XX:G1MaxNewSizePercent=40 \
  -XX:G1HeapRegionSize=8M \
  -XX:G1ReservePercent=20 \
  -XX:InitiatingHeapOccupancyPercent=15 \
  -XX:SurvivorRatio=32 \
  -XX:+PerfDisableSharedMem \
  -XX:MaxTenuringThreshold=1 \
  -jar fabric-server-launch.jar nogui
