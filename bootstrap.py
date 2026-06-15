#!/usr/bin/env python3
"""
bootstrap.py — download BTWCE server dependencies from scratch.

Run by start.sh on first run. Idempotent: existing files are sha1-verified
and re-downloaded only if they don't match.

This is intentionally a Python script because the URL composition for
lwjgl natives + URL-encoding '+' in versions is fiddly in shell.
"""
import urllib.request, json, hashlib, os, sys, zipfile, shutil, pathlib

ROOT = pathlib.Path(__file__).resolve().parent
LIBS = ROOT / "libraries"
LIBS.mkdir(exist_ok=True)
DOWNLOADS = ROOT / "downloads"
DOWNLOADS.mkdir(exist_ok=True)
MODS = ROOT / "mods"
MODS.mkdir(exist_ok=True)

UA = {"User-Agent": "btwce-server-bootstrap/1.0"}

# Mojang 1.6.4 server jar (sha1 from the official Mojang version manifest)
MOJANG_URL = "https://launcher.mojang.com/v1/objects/050f93c1f3fe9e2052398f7bd6aca10c63d64a87/server.jar"
MOJANG_SHA1 = "050f93c1f3fe9e2052398f7bd6aca10c63d64a87"

# BTWCE 3.1.0 (from Modrinth)
BTWCE_URL = "https://cdn.modrinth.com/data/PiC4CKoa/versions/Pbz5N4Ul/btwce-3.1.0.jar"

# Legacy Fabric meta + maven
LEGACY_META = "https://meta.legacyfabric.net/"
GAME_VERSION = "1.6.4"

def sha1(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()

def fetch(url, dest, expected_sha1=None, label=""):
    if dest.exists():
        if expected_sha1 and sha1(dest) == expected_sha1:
            print(f"  ok cached: {dest.name}")
            return dest
    print(f"  get {label or dest.name}: {url}")
    from urllib.parse import quote
    req = urllib.request.Request(quote(url, safe=":/"), headers=UA)
    with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f)
    if expected_sha1:
        actual = sha1(dest)
        if actual != expected_sha1:
            raise SystemExit(f"sha1 mismatch for {dest}: expected {expected_sha1}, got {actual}")
    return dest

# 1. Mojang 1.6.4 server jar
print("[1] Mojang 1.6.4 server.jar")
fetch(MOJANG_URL, DOWNLOADS / "mojang-1.6.4-server.jar", MOJANG_SHA1, "mojang-1.6.4")

# 2. Latest stable Legacy Fabric loader for 1.6.4
print("[2] Legacy Fabric meta (1.6.4)")
req = urllib.request.Request(f"{LEGACY_META}v2/versions/loader/{GAME_VERSION}", headers=UA)
loaders = json.loads(urllib.request.urlopen(req, timeout=30).read())
stable = next((l for l in loaders if l.get("loader", {}).get("stable")), loaders[0])
loader_version = stable["loader"]["version"]
print(f"  using loader {loader_version}")

# 3. Server launcher JSON (main class + library list)
print("[3] Loader server launcher json")
url = f"{LEGACY_META}v2/versions/loader/{GAME_VERSION}/{loader_version}/server/json"
req = urllib.request.Request(url, headers=UA)
launcher = json.loads(urllib.request.urlopen(req, timeout=30).read())
print(f"  mainClass: {launcher['mainClass']}, libraries: {len(launcher['libraries'])}")

# 4. Download all libraries (with OS-specific natives handling)
print("[4] Libraries")
import platform as _p
os_key = _p.system().lower()
if os_key == "darwin":
    os_key = "osx"
for lib in launcher["libraries"]:
    name = lib["name"]
    parts = name.split(":")
    group, artifact, version = parts[0].replace(".", "/"), parts[1], parts[2]
    base = lib.get("url", "").rstrip("/") + "/"
    classifier = None
    natives = lib.get("natives")
    if natives:
        classifier = natives.get(os_key) or natives.get("linux")
    if classifier:
        rel = f"{group}/{artifact}/{version}/{artifact}-{version}-{classifier}.jar"
    else:
        rel = f"{group}/{artifact}/{version}/{artifact}-{version}.jar"
    fetch(base + rel, LIBS / rel, label=rel.split("/")[-1])

# 5. BTWCE mod
print("[5] BTWCE mod")
fetch(BTWCE_URL, MODS / "btwce-3.1.0.jar", label="btwce-3.1.0")

# 6. install-info.json
print("[6] install-info.json")
(ROOT / "install-info.json").write_text(json.dumps({
    "gameVersion": GAME_VERSION,
    "loaderVersion": loader_version,
    "mainClass": launcher["mainClass"],
    "mod": "btwce-3.1.0",
    "modUrl": "https://modrinth.com/mod/btwce",
    "loaderUrl": "https://legacyfabric.org/",
    "mojangServerSha1": MOJANG_SHA1,
}, indent=2))

print("\nBootstrap complete.")
