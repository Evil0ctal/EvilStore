#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# build EvilStore and package as a TrollStore-installable .tipa
#
# usage:
#   Scripts/build_tipa.sh                     # Release -> build/EvilStore.tipa
#   Scripts/build_tipa.sh --debug             # Debug build
#   Scripts/build_tipa.sh --output PATH       # custom output path
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CONFIG="Release"
OUTPUT="$REPO_ROOT/build/EvilStore.tipa"
SCHEME="EvilStore"
PROJECT="$REPO_ROOT/EvilStore.xcodeproj"
ENTITLEMENTS="$REPO_ROOT/EvilStore/Resources/entitlements.plist"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --debug) CONFIG="Debug"; shift ;;
        --output) OUTPUT="$2"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 1 ;;
    esac
done

command -v ldid >/dev/null || { echo "ldid missing; brew install ldid"; exit 1; }
[[ -f "$ENTITLEMENTS" ]] || { echo "entitlements not found: $ENTITLEMENTS"; exit 1; }

# regenerate .xcodeproj from project.yml so the project is reproducible
if [[ ! -d "$PROJECT" ]] || [[ project.yml -nt "$PROJECT" ]]; then
    command -v xcodegen >/dev/null || { echo "xcodegen missing; brew install xcodegen"; exit 1; }
    echo "==> xcodegen generate"
    xcodegen generate --quiet
fi

DERIVED="$REPO_ROOT/build/DerivedData"
ARCHIVE="$REPO_ROOT/build/EvilStore.xcarchive"
STAGE="$REPO_ROOT/build/stage"
mkdir -p "$REPO_ROOT/build"
rm -rf "$ARCHIVE" "$STAGE"

echo "==> archive ($CONFIG)"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED" \
    -archivePath "$ARCHIVE" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    archive | (command -v xcbeautify >/dev/null && xcbeautify || cat)

APP_SRC="$ARCHIVE/Products/Applications/EvilStore.app"
[[ -d "$APP_SRC" ]] || { echo "EvilStore.app not in archive"; exit 1; }

echo "==> stage Payload/"
mkdir -p "$STAGE/Payload"
cp -R "$APP_SRC" "$STAGE/Payload/EvilStore.app"

echo "==> ldid fakesign with entitlements"
ldid -S"$ENTITLEMENTS" "$STAGE/Payload/EvilStore.app/EvilStore"

# fakesign every embedded Mach-O so SPM frameworks (ZIPFoundation, etc.)
# pass amfi at launch. detection is by magic bytes — Mach-O signatures
# are feedface, feedfacf, cefaedfe, cffaedfe, cafebabe (fat binary).
sign_macho_in() {
    local root="$1"
    [[ -d "$root" ]] || return 0
    while IFS= read -r -d '' f; do
        local magic
        magic=$(xxd -p -l 4 "$f" 2>/dev/null || true)
        case "$magic" in
            feedface|feedfacf|cefaedfe|cffaedfe|cafebabe)
                echo "    sign $f"
                ldid -S "$f"
                ;;
        esac
    done < <(find "$root" -type f -print0)
}

sign_macho_in "$STAGE/Payload/EvilStore.app/Frameworks"
sign_macho_in "$STAGE/Payload/EvilStore.app/PlugIns"

echo "==> zip -> $OUTPUT"
mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT"
( cd "$STAGE" && zip -qr "$OUTPUT" Payload )

echo "ok: $OUTPUT"
ls -lh "$OUTPUT"
