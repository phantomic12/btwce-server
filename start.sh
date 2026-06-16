#!/bin/sh
# start.sh — launch the BTWCE Minecraft server.
#
# Self-bootstrapping: on first run it downloads every runtime file
# (the Mojang 1.6.4 server jar from launcher.mojang.com, 11 library
# jars from the legacy-fabric and fabricmc maven repos, and the BTWCE
# mod from the Modrinth CDN), then launches the server headless.
#
# Requires:
#   - Java 17+ on the system (BTWCE 3.1.0 declares depends: java >=17 <=21)
#   - bash 4+ (we re-exec under bash because the rest of the script uses
#     bash features — Pelican-style hosts that call `sh start.sh` still work)
#   - curl, awk, sha1sum, sha512sum
#   - about 80 MB free disk (Mojang jar + libs + the 47 MB mod jar)
#
# Re-runs are instant: each file is only downloaded if it's missing.

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
for tool in curl awk sha1sum sha512sum; do
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
echo "[1/5] Using Java: $("$JAVA_BIN" -version 2>&1 | head -1)"

# --- pinned sources / checksums ---
# Bump these when upgrading Legacy Fabric or libraries.
#
# Mojang: 1.6.4 server jar. The SHA1 is the URL's path segment — Mojang
# distributes by-content-addressed, so the SHA1 is the integrity check.
MOJANG_URL="https://launcher.mojang.com/v1/objects/050f93c1f3fe9e2052398f7bd6aca10c63d64a87/server.jar"
MOJANG_SHA1="050f93c1f3fe9e2052398f7bd6aca10c63d64a87"
MOJANG_FILE="downloads/mojang-1.6.4-server.jar"

# BTWCE mod is fetched from the Modrinth CDN rather than a GitHub
# release so the repo doesn't have to carry a 47 MB binary. To upgrade,
# find the new version on https://modrinth.com/mod/btwce/versions, then
# bump MOD_VERSION_ID, MOD_FILENAME, and MOD_SHA512. The project ID and
# version ID are visible in the version's JSON (also served by
# https://api.modrinth.com/v2/project/btwce/version).
MOD_PROJECT_ID="PiC4CKoa"
MOD_VERSION_ID="Pbz5N4Ul"
MOD_VERSION="3.1.0"
MOD_FILENAME="btwce-${MOD_VERSION}.jar"
MOD_FILE="mods/${MOD_FILENAME}"
MOD_URL="https://cdn.modrinth.com/data/${MOD_PROJECT_ID}/versions/${MOD_VERSION_ID}/${MOD_FILENAME}"
MOD_SHA512="c51bfd3822ba7beff2c9973fce163d7bb6ba0d7082471b37dc63ca1b5b8772c7070a2fd1cd3344aaddd9d31b31ea3ff8f76469e37a4490147546a60c8d29dfa7"

# Libraries: (maven_host | local_path) pairs. The URL is built as
# https://<host>/<local_path_minus_libraries_prefix>. The SHA1 is fetched
# live from the maven repo's `<url>.sha1` sidecar — same TOFU trust model
# as the source jar. Bump these by changing the version segment.
#
# Host split is by maven group:
#   * net.fabricmc.*  and  org.ow2.asm.*  → maven.fabricmc.net
#   * net.legacyfabric.*  and  org.lwjgl.*  → maven.legacyfabric.net
LIBS=(
  "fabricmc.net|libraries/net/fabricmc/fabric-loader/0.19.3/fabric-loader-0.19.3.jar"
  "fabricmc.net|libraries/net/fabricmc/sponge-mixin/0.17.3+mixin.0.8.7/sponge-mixin-0.17.3+mixin.0.8.7.jar"
  "legacyfabric.net|libraries/net/legacyfabric/intermediary/1.6.4/intermediary-1.6.4.jar"
  "legacyfabric.net|libraries/org/lwjgl/lwjgl/lwjgl-platform/2.9.4+legacyfabric.17/lwjgl-platform-2.9.4+legacyfabric.17-natives-linux.jar"
  "legacyfabric.net|libraries/org/lwjgl/lwjgl/lwjgl/2.9.4+legacyfabric.17/lwjgl-2.9.4+legacyfabric.17.jar"
  "legacyfabric.net|libraries/org/lwjgl/lwjgl/lwjgl_util/2.9.4+legacyfabric.17/lwjgl_util-2.9.4+legacyfabric.17.jar"
  "fabricmc.net|libraries/org/ow2/asm/asm-analysis/9.10.1/asm-analysis-9.10.1.jar"
  "fabricmc.net|libraries/org/ow2/asm/asm-commons/9.10.1/asm-commons-9.10.1.jar"
  "fabricmc.net|libraries/org/ow2/asm/asm-tree/9.10.1/asm-tree-9.10.1.jar"
  "fabricmc.net|libraries/org/ow2/asm/asm-util/9.10.1/asm-util-9.10.1.jar"
  "fabricmc.net|libraries/org/ow2/asm/asm/9.10.1/asm-9.10.1.jar"
)

# --- helpers ---
# download_checked <url> <sha1> <dest>
# Downloads to a temp file, sha1-verifies, then atomically moves into place.
download_checked() {
  local url="$1" sha1="$2" dest="$3"
  mkdir -p "$(dirname "$dest")"
  local tmp; tmp="$(mktemp --suffix=.part)"
  if ! curl -fL --retry 3 --connect-timeout 30 -o "$tmp" "$url"; then
    echo "ERROR: failed to download $url" >&2
    rm -f "$tmp"
    return 1
  fi
  if ! echo "$sha1  $tmp" | sha1sum -c - >/dev/null 2>&1; then
    echo "ERROR: $dest checksum mismatch (expected sha1 $sha1)" >&2
    rm -f "$tmp"
    return 1
  fi
  mv "$tmp" "$dest"
}

# download_lib <host> <local_path>
# Fetches a maven jar, then fetches its .sha1 sidecar and verifies.
download_lib() {
  local host="$1" path="$2"
  local rel="${path#libraries/}"
  local url="https://maven.${host}/${rel}"
  local sha_url="${url}.sha1"

  mkdir -p "$(dirname "$path")"
  local tmp; tmp="$(mktemp --suffix=.part)"

  if ! curl -fL --retry 3 --connect-timeout 30 -o "$tmp" "$url"; then
    echo "ERROR: failed to download $url" >&2
    rm -f "$tmp"
    return 1
  fi

  local expected_sha
  if ! expected_sha="$(curl -fL --retry 3 --connect-timeout 15 "$sha_url" | awk '{print $1}')" \
     || [[ -z "$expected_sha" ]]; then
    echo "ERROR: failed to fetch $sha_url" >&2
    rm -f "$tmp"
    return 1
  fi

  if ! echo "$expected_sha  $tmp" | sha1sum -c - >/dev/null 2>&1; then
    echo "ERROR: $path checksum mismatch (expected sha1 $expected_sha)" >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$path"
}

# --- [2/5] Mojang server jar ---
if [[ ! -f "$MOJANG_FILE" ]]; then
  echo "[2/5] Mojang 1.6.4 server jar missing, downloading..."
  download_checked "$MOJANG_URL" "$MOJANG_SHA1" "$MOJANG_FILE"
  echo "  done."
else
  echo "[2/5] Mojang 1.6.4 server jar present, skipping download."
fi

# --- [3/5] Libraries (Legacy Fabric + 10 transitive deps) ---
NEED_LIBS=0
for lib in "${LIBS[@]}"; do
  IFS='|' read -r _ path <<< "$lib"
  [[ -f "$path" ]] || { NEED_LIBS=1; break; }
done

if [[ $NEED_LIBS -eq 1 ]]; then
  echo "[3/5] Libraries missing, downloading from maven..."
  installed=0
  for lib in "${LIBS[@]}"; do
    IFS='|' read -r host path <<< "$lib"
    if [[ -f "$path" ]]; then
      continue
    fi
    download_lib "$host" "$path"
    installed=$((installed+1))
  done
  echo "  $installed/${#LIBS[@]} libraries installed."
else
  echo "[3/5] Libraries present, skipping download."
fi

# --- [4/5] BTWCE mod (Modrinth CDN) ---
if [[ ! -f "$MOD_FILE" ]]; then
  echo "[4/5] BTWCE mod missing, downloading from Modrinth CDN..."

  mkdir -p mods
  TMP_JAR="$(mktemp --suffix=.jar)"

  if ! curl -fL --retry 3 --connect-timeout 30 -o "$TMP_JAR" "$MOD_URL"; then
    echo "ERROR: failed to download $MOD_URL" >&2
    rm -f "$TMP_JAR"
    exit 1
  fi

  # Modrinth publishes SHA512 for every file.
  if ! echo "$MOD_SHA512  $TMP_JAR" | sha512sum -c - >/dev/null 2>&1; then
    echo "ERROR: mod checksum mismatch — refusing to install" >&2
    rm -f "$TMP_JAR"
    exit 1
  fi

  mv "$TMP_JAR" "$MOD_FILE"
  echo "  done ($(du -h "$MOD_FILE" | cut -f1) installed)."
else
  echo "[4/5] BTWCE mod present, skipping download."
fi

# Sanity check: every required file must exist after bootstrap.
for f in "$MOJANG_FILE" "$MOD_FILE"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: required file missing after bootstrap: $f" >&2
    exit 1
  fi
done
for lib in "${LIBS[@]}"; do
  IFS='|' read -r _ path <<< "$lib"
  if [[ ! -f "$path" ]]; then
    echo "ERROR: required library missing after bootstrap: $path" >&2
    exit 1
  fi
done

# --- [5/5] Launch ---
# Build the classpath: every library + the Mojang server jar.
# Java's -cp accepts ":"-separated paths on Linux/macOS, ";" on Windows.
# We don't ship a Windows story; the colon separator is fine for the
# targets start.sh is designed for (Linux panel hosts).
CP=""
for lib in "${LIBS[@]}"; do
  IFS='|' read -r _ path <<< "$lib"
  CP="${CP:+$CP:}${path}"
done
CP="${CP}:${MOJANG_FILE}"

echo "[5/5] Starting BTWCE server (MC 1.6.4 + Legacy Fabric 0.19.3 + BTWCE 3.1.0)..."
echo "      console is in this terminal. Type 'help' for commands. Ctrl+C stops."
echo
mkdir -p logs
exec "$JAVA_BIN" \
  -Djava.awt.headless=true \
  -Dfabric.gameJarPath="$MOJANG_FILE" \
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
  -cp "$CP" \
  net.fabricmc.loader.impl.launch.knot.KnotServer \
  nogui
