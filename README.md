# BTWCE Minecraft Server

A one-command self-bootstrapping Minecraft 1.6.4 server running
**Better Than Wolves: Community Edition** 3.1.0 on **Legacy Fabric** 0.19.3.

```bash
./start.sh
```

That's it. `start.sh` will:

1. Find a Java 17+ binary on the system
2. Download a runtime bundle (~14 MB) from the GitHub release
   (Legacy Fabric + 11 libraries + Mojang's 1.6.4 server jar + the
   manifest-only launch jar)
3. Verify the bundle checksum
4. Extract it
5. Launch the server on port 25565, headless

Re-runs are instant — the bundle is only downloaded once, then kept locally.

The BTWCE mod itself is committed in `mods/btwce-3.1.0.jar` (the
unmodified upstream release from Modrinth).

## What you get

| | |
|---|---|
| Minecraft | 1.6.4 |
| Mod loader | Legacy Fabric 0.19.3 (pinned in v1.0.0 release) |
| Mod | Better Than Wolves: Community Edition 3.1.0 |
| Java | Whatever you have installed (must be 17-21) |
| RAM default | 1G min, 4G max (edit `start.sh` to change) |
| Port | 25565 |
| GUI | none — headless AWT, `nogui` flag |

## Files in this repo

```
start.sh               # one-shot: download bundle if needed, then launch
console.sh             # same as start.sh, interactive console
stop.sh                # graceful shutdown (RCON + signals)
backup.sh              # tarball world/ into backups/ (prune to 24)
server.properties      # server config (motd, difficulty, port, ...)
eula.txt               # eula=true
mods/btwce-3.1.0.jar   # the mod itself
README.md
LICENSE                # MIT
```

Files **not** in the repo (downloaded from the GitHub release on first run):

```
downloads/mojang-1.6.4-server.jar
libraries/             # fabric loader + transitive deps
fabric-server-launch.jar
install-info.json
```

Created at runtime by the server itself:

```
world/                 # the world (created on first server run)
logs/                  # logs/latest.log etc.
backups/               # backup.sh output
```

## Java version requirement

BTWCE 3.1.0 declares `depends: java >=17 <=21` in its `fabric.mod.json`
and uses mixin companion plugins that only load on Java 17+. If you try
to launch on Java 8 (the historical MC 1.6.4 default), fabric will
reject the mod with "Incompatible mods found!".

Install a Java 17+ JRE and either:
- set `JAVA_HOME=/path/to/jdk-17` (recommended)
- set `BTWCE_JAVA=/path/to/java`
- or put `java` on your `PATH`

`start.sh` walks `/usr/lib/jvm/*` and `/opt/*` to find a JRE.

## Headless / no GUI popups

* `-Djava.awt.headless=true` — refuses to open any Swing/AWT window
* `nogui` final argument — disables MC's in-game GUI

If fabric's `CrashDialog` ever wants to pop up, AWT will silently fail
because the JVM is running in headless mode.

## Running on Pelican Panel (or any `sh start.sh` host)

Pelican invokes the startup script as `sh start.sh` rather than
`/bin/bash start.sh`, so the script is parsed by whatever `/bin/sh`
points to (dash on Debian-based Pelican images, ash on Alpine, etc.).
That rejects bash-only syntax like `set -o pipefail`.

The script handles this transparently: the first lines detect the shell
and re-exec under `bash` if available. The same script works for:

* direct invocation: `./start.sh` (or `bash start.sh`)
* Pelican: configured to run `sh start.sh` (the default for a custom
  startup command) — the script trampolines to bash on its own

## How the bundle works

The GitHub release `v1.0.0` has a `libraries-bundle.tar.xz` asset
containing the runtime files:

```
libraries/             # Legacy Fabric 0.19.3 + 11 transitive deps
downloads/mojang-1.6.4-server.jar
fabric-server-launch.jar  # 485-byte manifest-only jar with folded Class-Path
install-info.json
```

On first run, `start.sh` downloads this bundle, sha256-verifies it
against the embedded checksum, and `tar -xJf`s it in place. Subsequent
runs skip the download entirely.

To upgrade the loader or libraries, create a new release with a new
bundle, then bump `BUNDLE_VERSION` and `BUNDLE_SHA256` in `start.sh`.

## Client side

Connect from a Minecraft 1.6.4 client with the same BTWCE 3.1.0 mod
installed. The client mod jar is the same file as `mods/btwce-3.1.0.jar`
(it's required on both client and server).

* Download: <https://modrinth.com/mod/btwce/versions>
* Wiki: <https://wiki.btwce.com/>
* Discord: <https://discord.btwce.com/>

## Customizing server.properties

The committed `server.properties` is a sane default. **Change
`rcon.password`** before exposing the server to a network. Key fields:

| Key | Value | Note |
|---|---|---|
| `motd` | `§c§lBTWCE §r§8\| §eBetter Than Wolves: Community Edition` | |
| `server-port` | `25565` | |
| `difficulty` | `2` | normal |
| `online-mode` | `true` | set `false` for cracked/LAN |
| `allow-flight` | `true` | required by some BTWCE mechanics |
| `max-tick-time` | `180000` | higher than vanilla for slow chunk gen |
| `enable-rcon` | `true` | used by `stop.sh` |
| `rcon.password` | `changeme` | **change this** |
| `snooper-enabled` | `false` | opt out of Mojang telemetry |

## Cron-friendly backups

```cron
0 * * * * /path/to/btwce-server/backup.sh >> /path/to/btwce-server/logs/backup.log 2>&1
```

`backup.sh` keeps the most recent 24 snapshots in `backups/`.

## License

MIT. The BTWCE mod is CC-BY-4.0 (`mods/btwce-3.1.0.jar` is the
unmodified upstream release from <https://modrinth.com/mod/btwce>).
