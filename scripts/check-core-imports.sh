#!/bin/bash
# Fails when a core-bound file imports a UI or Apple Music framework.
#
# Core-bound files move into the ShflCore package, which may import only
# Foundation, Observation and SwiftData. Run from anywhere in the repo:
#   scripts/check-core-imports.sh
set -euo pipefail

cd "$(dirname "$0")/.."

core_paths=(
    Shfl/Domain
    Shfl/Data
    Shfl/ViewModels
    Shfl/Services/Scrobbling
)

forbidden='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|var|func)[[:space:]]+)?(SwiftUI|UIKit|AppKit|MusicKit|MediaPlayer)([.[:space:]]|$)'

# Core-bound files allowed a forbidden import until a scheduled PR removes it;
# name that PR beside each path.
known_exceptions=()

is_known_exception() {
    local file=$1
    local exception
    for exception in ${known_exceptions[@]+"${known_exceptions[@]}"}; do
        [[ "$file" == "$exception" ]] && return 0
    done
    return 1
}

violations=0
while IFS= read -r -d '' file; do
    if matches=$(grep -nE "$forbidden" "$file"); then
        if is_known_exception "$file"; then
            continue
        fi
        while IFS= read -r line; do
            echo "$file:$line"
        done <<< "$matches"
        violations=$((violations + 1))
    fi
done < <(find "${core_paths[@]}" -name '*.swift' -print0 | sort -z)

if (( violations > 0 )); then
    echo "error: $violations core-bound file(s) import SwiftUI, UIKit, AppKit, MusicKit or MediaPlayer." >&2
    exit 1
fi

echo "Core imports OK."
