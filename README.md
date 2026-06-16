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
3. Download the BTWCE mod jar (~46 MB) from the Modrinth CDN
   (the same upstream release published on Modrinth — see
   <https://modrinth.com/mod/btwce/versions>)
4. Verify both downloads' checksums
5. Extract the bundle and launch the server on port 25565, headless

Re-runs are instant — the bundle and the mod are each only downloaded
once, then kept locally.

The BTWCE mod is **not** committed in the repo; it lives only in
`mods/btwce-3.1.0.jar` after a successful bootstrap, and is
re-downloaded by `start.sh` whenever that file is missing.

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
mods/.gitkeep          # keeps the (otherwise empty) mods/ directory
README.md
LICENSE                # MIT
```

Files **not** in the repo (downloaded on first run by `start.sh`):

```
# from the GitHub release (the runtime bundle)
downloads/mojang-1.6.4-server.jar
libraries/             # fabric loader + transitive deps
fabric-server-launch.jar
install-info.json

# from the Modrinth CDN (the mod)
mods/btwce-3.1.0.jar
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

## How the bootstrap works

`start.sh` does two independent fetches on first run, each with a
versioned checksum, and only re-fetches when the local file is missing.

**1. Runtime bundle — from the GitHub release**

The GitHub release `v1.0.0` has a `libraries-bundle.tar.xz` asset
containing the runtime files:

```
libraries/             # Legacy Fabric 0.19.3 + 11 transitive deps
downloads/mojang-1.6.4-server.jar
fabric-server-launch.jar  # 485-byte manifest-only jar with folded Class-Path
install-info.json
```

On first run, `start.sh` downloads this bundle, sha256-verifies it
against the embedded checksum, and `tar -xJf`s it in place.

**2. BTWCE mod — from the Modrinth CDN**

The mod is fetched directly from
`https://cdn.modrinth.com/data/PiC4CKoa/versions/Pbz5N4Ul/btwce-3.1.0.jar`
(the same file Modrinth publishes for
<https://modrinth.com/mod/btwce/version/3.1.0>) and dropped into
`mods/btwce-3.1.0.jar`. The download is sha512-verified against the
hash Modrinth publishes for that version. To upgrade, find the new
version on <https://modrinth.com/mod/btwce/versions>, then bump
`MOD_VERSION_ID`, `MOD_FILENAME`, and `MOD_SHA512` at the top of
`start.sh`. To force a re-download, delete `mods/btwce-3.1.0.jar`.

To upgrade the runtime bundle, create a new release with a new bundle,
then bump `BUNDLE_VERSION` and `BUNDLE_SHA256` in `start.sh`.

## Client side

Connect from a Minecraft 1.6.4 client with the same BTWCE 3.1.0 mod
installed. The client mod jar is the same file `start.sh` downloads to
`mods/btwce-3.1.0.jar` on the server (it is required on both client
and server). To install the same mod on the client, download it from
Modrinth:

* <https://modrinth.com/mod/btwce/versions>
* <https://wiki.btwce.com/>
* <https://discord.btwce.com/>

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
unmodified upstream release fetched from the Modrinth CDN at
<https://modrinth.com/mod/btwce>).
