#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# bump marketing + build version in Configuration/Version.xcconfig
#
# usage:
#   Scripts/bump_version.sh patch        # 0.1.0 -> 0.1.1
#   Scripts/bump_version.sh minor        # 0.1.x -> 0.2.0
#   Scripts/bump_version.sh major        # 0.x.x -> 1.0.0
#   Scripts/bump_version.sh 1.2.3        # explicit
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$REPO_ROOT/Configuration/Version.xcconfig"

current_marketing() {
    grep '^MARKETING_VERSION' "$VERSION_FILE" | awk -F= '{gsub(/ /,"",$2); print $2}'
}
current_build() {
    grep '^CURRENT_PROJECT_VERSION' "$VERSION_FILE" | awk -F= '{gsub(/ /,"",$2); print $2}'
}

bump_field() {
    local v="$1" field="$2"
    IFS=. read -r maj min pat <<<"$v"
    case "$field" in
        major) echo "$((maj + 1)).0.0" ;;
        minor) echo "${maj}.$((min + 1)).0" ;;
        patch) echo "${maj}.${min}.$((pat + 1))" ;;
    esac
}

cur="$(current_marketing)"
build="$(current_build)"

case "${1:-}" in
    major|minor|patch) new="$(bump_field "$cur" "$1")" ;;
    [0-9]*.[0-9]*.[0-9]*) new="$1" ;;
    *) echo "usage: $0 {major|minor|patch|X.Y.Z}"; exit 1 ;;
esac

new_build=$((build + 1))

sed -i.bak \
    -e "s/^MARKETING_VERSION.*/MARKETING_VERSION         = $new/" \
    -e "s/^CURRENT_PROJECT_VERSION.*/CURRENT_PROJECT_VERSION   = $new_build/" \
    "$VERSION_FILE"
rm -f "$VERSION_FILE.bak"

echo "version: $cur -> $new (build $build -> $new_build)"
