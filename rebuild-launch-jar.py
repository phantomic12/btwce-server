#!/usr/bin/env python3
"""
rebuild-launch-jar.py — build the small fabric-server-launch.jar.

The jar contains only a META-INF/MANIFEST.MF whose Class-Path attribute
points to every loader library and the Mojang server jar. Java 17 enforces
the JAR spec's 72-byte line limit on manifest lines strictly, so we
fold the Class-Path into 70-byte chunks with continuation lines starting
with a single space.
"""
import zipfile, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent
LIBS = ROOT / "libraries"
LAUNCH = ROOT / "fabric-server-launch.jar"

entries = sorted("libraries/" + j.relative_to(LIBS).as_posix() for j in LIBS.rglob("*.jar"))
entries.append("downloads/mojang-1.6.4-server.jar")

main_class = "net.fabricmc.loader.impl.launch.knot.KnotServer"

def fold(line, limit=70):
    parts = []
    while len(line) > limit:
        parts.append(line[:limit])
        line = line[limit:]
    parts.append(line)
    return "\r\n ".join(parts)

manifest = "\r\n".join([
    "Manifest-Version: 1.0",
    f"Main-Class: {main_class}",
    fold("Class-Path: " + " ".join(entries)),
    "",
])

if LAUNCH.exists():
    LAUNCH.unlink()
with zipfile.ZipFile(LAUNCH, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.writestr("META-INF/MANIFEST.MF", manifest)

print(f"Wrote {LAUNCH}")
print(f"  mainClass: {main_class}")
print(f"  classpath: {len(entries)} entries")
