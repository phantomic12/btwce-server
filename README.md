# BTWCE Minecraft Server

A one-command self-bootstrapping Minecraft 1.6.4 server running
**Better Than Wolves: Community Edition** 3.1.0 on **Legacy Fabric** 0.19.3.

```bash
./start.sh
```

That's it. On first run, `start.sh` will download:

* A portable Temurin 17 JRE into `~/java-portable/` (no `apt`, no sudo)
* Mojang's official `minecraft_server.1.6.4.jar`
* The Legacy Fabric loader + 11 required libraries
* The BTWCE 3.1.0 mod

Then it launches the server on port 25565.

Re-runs are instant — existing files are SHA1-verified and left alone.

## What you get

| | |
|---|---|
| Minecraft | 1.6.4 |
| Mod loader | Legacy Fabric 0.19.3 (resolved at bootstrap) |
| Mod | Better Than Wolves: Community Edition 3.1.0 |
| Java | Temurin 17 JRE (portable, no system install) |
| RAM default | 1G min, 4G max (edit `start.sh` to change) |
| Port | 25565 |
| GUI | none — headless AWT, `nogui` flag |

## Files in this repo

```
start.sh               # one-shot: bootstrap if needed, then launch
console.sh             # start with interactive console
stop.sh                # graceful shutdown (RCON + signals)
backup.sh              # tarball world/ into backups/ (prune to 24)
bootstrap.py           # downloads all server deps from scratch
rebuild-launch-jar.py  # rebuilds fabric-server-launch.jar manifest
server.properties      # server config (motd, difficulty, port, ...)
eula.txt               # eula=true
mods/btwce-3.1.0.jar   # the mod itself
install-info.json      # version metadata (generated)
README.md              # this file
LICENSE                # MIT
```

Files **not** in the repo (created at runtime by `start.sh`):

```
downloads/mojang-1.6.4-server.jar
libraries/             # fabric loader + transitive deps
world/                 # the world (created on first server run)
logs/                  # logs/latest.log etc.
backups/               # backup.sh output
~/java-portable/       # portable Java
fabric-server-launch.jar
fabric-server-launcher.properties
```

## Client side

Connect from a Minecraft 1.6.4 client with the same BTWCE 3.1.0 mod
installed. The client mod jar is the same file as `mods/btwce-3.1.0.jar`
(it's required on both client and server).

* Download: <https://modrinth.com/mod/btwce/versions>
* Wiki: <https://wiki.btwce.com/>
* Discord: <https://discord.btwce.com/>

## Java version warning

BTWCE 3.1.0 declares `depends: java >=17 <=21` in its `fabric.mod.json` and
uses mixin companion plugins that only load on Java 17+. If you try to
launch on Java 8 (the historical MC 1.6.4 default), fabric will reject the
mod with:

> Incompatible mods found!
> - Mod 'Better Than Wolves: Community Edition' (btw) 3.1.0 requires any
>   version between 17 (inclusive) and 21 (inclusive) of 'OpenJDK 64-Bit
>   Server VM' (java), but only the wrong version is present: 8!

`start.sh` handles this by downloading a portable Temurin 17 JRE on first
run, so you don't have to think about it.

If you want to use a system Java 17+ instead, edit `start.sh` and change
`JAVA_VERSION` + `JAVA_DIR`, or replace `$JAVA_BIN` with your own path.

## Headless / no GUI popups

* `-Djava.awt.headless=true` — refuses to open any Swing/AWT window
* `nogui` final argument — disables MC's in-game GUI
* If fabric's `CrashDialog` ever wants to pop up, you can also pass
  `-Djava.awt.headless=true` (already set) and ensure no DISPLAY is
  reachable; AWT will silently fail instead.

## Updating

Update the mod by replacing `mods/btwce-3.1.0.jar` with a newer version
(grab from <https://modrinth.com/mod/btwce/versions>). To re-resolve the
loader libraries for a newer version of Legacy Fabric:

```bash
rm -rf libraries/ downloads/
./start.sh
```

`bootstrap.py` is idempotent — re-running just SHA1-verifies existing
files and re-downloads if needed.

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
