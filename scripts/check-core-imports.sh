#!/bin/bash
# Fails when a ShflCore source imports anything but Foundation, Observation
# or SwiftData.
#
# The package can't enforce this on its own: ShflCore declares no
# dependencies, but Apple's system frameworks (SwiftUI, UIKit, AppKit,
# MusicKit, MediaPlayer…) are importable from any target. Run from anywhere
# in the repo:
#   scripts/check-core-imports.sh
set -euo pipefail

cd "$(dirname "$0")/.."

core_sources=Packages/ShflKit/Sources/ShflCore

allowed='Foundation|Observation|SwiftData'

# Any import, including attributed (`@preconcurrency import`), scoped
# (`import struct SwiftUI.Color`) and submodule (`import UIKit.UIColor`) forms.
# Captures the top-level module name.
import_line='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|var|func|let|actor)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)'

violations=0
while IFS= read -r -d '' file; do
    while IFS= read -r match; do
        [[ -z "$match" ]] && continue
        line=${match#*:}
        module=$(sed -E "s/${import_line}.*/\4/" <<< "$line")
        if ! [[ "$module" =~ ^($allowed)$ ]]; then
            echo "$file:$match"
            violations=$((violations + 1))
        fi
    done <<< "$(grep -nE "$import_line" "$file" || true)"
done < <(find "$core_sources" -name '*.swift' -print0 | sort -z)

if (( violations > 0 )); then
    echo "error: $violations import(s) in ShflCore outside Foundation, Observation and SwiftData." >&2
    exit 1
fi

echo "Core imports OK."
