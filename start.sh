#!/usr/bin/env bash
# start.sh — bootstrap (if needed) and launch the BTWCE Minecraft server.
#
# On first run this script will:
#   1. Download a portable Temurin 17 JRE into ~/java-portable/ (no apt)
#   2. Download Mojang's official 1.6.4 server jar
#   3. Download Legacy Fabric 0.19.3 + all required libraries from the
#      legacy-fabric / fabric mavens
#   4. Build a small fabric-server-launch.jar (manifest only, just sets up
#      the classpath)
#   5. Drop the BTWCE 3.1.0 mod into mods/ (if not already there)
# Then it launches the server on port 25565, nogui, headless.
#
# Re-runs are cheap: existing files are left alone.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# --- preflight: required tools ---
for tool in curl tar python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "ERROR: '$tool' is required but not installed. Install it and re-run." >&2
    exit 1
  fi
done

JAVA_VERSION="17.0.13+11"
JAVA_DIR="$HOME/java-portable/jdk-${JAVA_VERSION}-jre"
JAVA_BIN="$JAVA_DIR/bin/java"

# --- 1. Java (portable Temurin 17 JRE) ---
if [[ ! -x "$JAVA_BIN" ]]; then
  echo "[1/4] Java not found at $JAVA_BIN"
  echo "      downloading Temurin 17 JRE portable (~44 MB)..."
  mkdir -p "$HOME/java-portable"
  TMP_TAR="$(mktemp --suffix=.tar.gz)"
  if ! curl -fL --retry 3 --connect-timeout 15 -o "$TMP_TAR" \
    "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jre_x64_linux_hotspot_17.0.13_11.tar.gz"; then
    echo "ERROR: failed to download Java 17. Check internet / firewall." >&2
    rm -f "$TMP_TAR"
    exit 1
  fi
  tar -xzf "$TMP_TAR" -C "$HOME/java-portable"
  rm -f "$TMP_TAR"
  if [[ ! -x "$JAVA_BIN" ]]; then
    echo "ERROR: java binary not at expected path after extraction." >&2
    ls "$HOME/java-portable" >&2
    exit 1
  fi
  echo "      ok: $("$JAVA_BIN" -version 2>&1 | head -1)"
fi

# --- 2. Mojang server jar + fabric libraries + BTWCE mod ---
NEED_BOOTSTRAP=0
[[ ! -f "downloads/mojang-1.6.4-server.jar" ]] && NEED_BOOTSTRAP=1
[[ ! -d "libraries/net/fabricmc/fabric-loader" ]] && NEED_BOOTSTRAP=1
[[ ! -f "mods/btwce-3.1.0.jar" ]] && NEED_BOOTSTRAP=1
if [[ $NEED_BOOTSTRAP -eq 1 ]]; then
  echo "[2/4] Bootstrap needed, running bootstrap.py..."
  python3 bootstrap.py
else
  echo "[2/4] Bootstrap state complete, skipping."
fi

# --- 3. Launch jar (manifest with folded classpath) ---
if [[ ! -f "fabric-server-launch.jar" ]]; then
  echo "[3/4] Rebuilding fabric-server-launch.jar..."
  python3 rebuild-launch-jar.py
else
  echo "[3/4] fabric-server-launch.jar present, skipping."
fi

# --- 4. Launch ---
echo "[4/4] Starting BTWCE server (MC 1.6.4 + Legacy Fabric 0.19.3 + BTWCE 3.1.0)..."
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
