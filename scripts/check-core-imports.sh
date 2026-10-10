#!/bin/bash
# Fails when a ShflKit target imports a module outside its allowed list, or
# when the iOS app reaches past AppModel to MusicKit or an adapter.
#
# The package can't enforce this on its own: Apple's system frameworks
# (SwiftUI, UIKit, AppKit, MusicKit, MediaPlayer…) are importable from any
# target whatever it declares. Run from anywhere in the repo:
#   scripts/check-core-imports.sh
set -euo pipefail

cd "$(dirname "$0")/.."

sources=Packages/ShflKit/Sources

# Each target's allowed imports. Keep in step with Package.swift's
# dependencies; a target missing here fails the check.
allowed_for() {
    case "$1" in
        ShflCore) echo 'Foundation|Observation|SwiftData' ;;
        ShflAppleMusic) echo 'Foundation|Observation|Combine|MusicKit|ShflCore' ;;
        ShflAppleMusicUI) echo 'Foundation|Observation|SwiftUI|MusicKit|ShflCore|ShflAppleMusic' ;;
        ShflLastFM) echo 'Foundation|Observation|CryptoKit|Network|Security|ShflCore' ;;
        ShflDeterministic) echo 'Foundation|Synchronization|ShflCore' ;;
        ShflComposition) echo 'Foundation|Observation|SwiftData|ShflCore|ShflAppleMusic|ShflLastFM|ShflDeterministic' ;;
        ShflTestSupport) echo 'Foundation|XCTest' ;;
        *) return 1 ;;
    esac
}

# Matches attributed, scoped and submodule imports; captures the top-level module.
import_line='^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]+((typealias|struct|class|enum|protocol|var|func|let|actor)[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)'

violations=0

# Prints each import in the files under $1 whose module doesn't match $2.
check_imports() {
    local dir=$1 allowed=$2 file match line module
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
    done < <(find "$dir" -name '*.swift' -print0 | sort -z)
}

for dir in "$sources"/*/; do
    target=$(basename "$dir")
    if ! allowed=$(allowed_for "$target"); then
        echo "$dir: no allowed-import list for $target"
        violations=$((violations + 1))
        continue
    fi
    check_imports "$dir" "$allowed"
done

# The app reaches MusicKit only through ShflAppleMusicUI's views, and the
# adapters only through AppModel.
check_imports Shfl 'Foundation|Observation|SwiftUI|UIKit|MediaPlayer|AuthenticationServices|Vortex|ShflCore|ShflAppleMusicUI|ShflLastFM|ShflDeterministic|ShflComposition'
while IFS= read -r match; do
    [[ -z "$match" ]] && continue
    echo "$match"
    violations=$((violations + 1))
done <<< "$(grep -rnwE 'MusicKitTransport|AppleMusicService|LastFMTransport|DeterministicMusicService' Shfl --include='*.swift' || true)"

if (( violations > 0 )); then
    echo "error: $violations disallowed import(s) or adapter reference(s)." >&2
    exit 1
fi

echo "Imports OK."
