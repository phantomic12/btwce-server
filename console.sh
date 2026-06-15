#!/usr/bin/env bash
# console.sh — same as start.sh but foreground with stdin forwarded so you
# can issue server commands interactively (list, whitelist add, stop, etc.)
set -euo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"
exec bash ./start.sh < /dev/tty
