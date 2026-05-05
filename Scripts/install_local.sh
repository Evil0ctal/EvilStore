#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# push build/EvilStore.tipa to a test iPhone
#
# default mode opens Finder so the user can AirDrop manually.
# ssh mode requires OpenSSH on the device (optional; not required by TrollStore).
#
# usage:
#   Scripts/install_local.sh
#   Scripts/install_local.sh ssh root@iphone.local /var/mobile/Downloads/
set -euo pipefail
TIPA="${1:-build/EvilStore.tipa}"
[[ -f "$TIPA" ]] || { echo "tipa not found: $TIPA — run Scripts/build_tipa.sh first"; exit 1; }
TIPA="$(realpath "$TIPA")"

if [[ "${1:-}" == "ssh" ]]; then
    HOST="$2"; DEST="$3"
    scp "$TIPA" "$HOST:$DEST"
    echo "scp ok: $HOST:$DEST -- open in Filza to install"
else
    open -a "Finder" "$(dirname "$TIPA")"
    echo "in Finder: right-click EvilStore.tipa -> Share -> AirDrop -> iPhone"
fi
