#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026 Evil0ctal <evil0ctal1985@gmail.com>
#
# run swiftformat + swiftlint + SPDX header check
# missing tools are skipped silently so pre-commit hooks don't break setups
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if command -v swiftformat >/dev/null; then
    swiftformat --lint EvilStore EvilStoreTests
else
    echo "skip: swiftformat not found (brew install swiftformat)"
fi

if command -v swiftlint >/dev/null; then
    swiftlint lint --quiet
else
    echo "skip: swiftlint not found (brew install swiftlint)"
fi

# SPDX header check — every tracked source file must declare GPL-2.0
fail=0
check_header() {
    local f="$1"
    head -3 "$f" | grep -q "SPDX-License-Identifier: GPL-2.0" \
        || { echo "missing SPDX header: $f"; fail=1; }
}

while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    [[ -f "$f" ]] || continue
    check_header "$f"
done < <(
    git ls-files \
        'EvilStore/**/*.swift' \
        'EvilStore/**/*.h' \
        'EvilStore/**/*.m' \
        'EvilStoreTests/**/*.swift' \
        'Scripts/*.sh' 2>/dev/null
)

if [[ $fail -ne 0 ]]; then
    echo "lint failed: missing SPDX headers"
    exit 1
fi

echo "lint ok"
