#!/bin/bash
# Manual AWG catch-up when the daily CI sync could not complete.
#
# Usage: manual_awg_merge.sh <current pin> <target tag>
#   e.g. manual_awg_merge.sh v5.31.0 v5.32.0
#
# Freedom tracks bivlked's official English helpers (*_en.sh), so this is the
# same path CI takes: three-way merge -> Freedom overlay -> branding -> pins.
# It exists for the case where the merge conflicts and a human has to look.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PIN="${1:?usage: manual_awg_merge.sh <current pin> <target tag>}"
LATEST="${2:?usage: manual_awg_merge.sh <current pin> <target tag>}"
VENDOR="$ROOT/upstream/vendor/bivlked"
PYTHON="${PYTHON:-python3}"
FILES=(awg_common.sh manage_amneziawg.sh)
UPSTREAM=(awg_common_en.sh manage_amneziawg_en.sh)

mkdir -p "$VENDOR/$PIN" "$VENDOR/$LATEST"
for f in "${UPSTREAM[@]}"; do
    curl -fsSL -o "$VENDOR/$PIN/$f" \
        "https://raw.githubusercontent.com/bivlked/amneziawg-installer/${PIN}/${f}"
    curl -fsSL -o "$VENDOR/$LATEST/$f" \
        "https://raw.githubusercontent.com/bivlked/amneziawg-installer/${LATEST}/${f}"
done

for i in "${!FILES[@]}"; do
    f="${FILES[$i]}" u="${UPSTREAM[$i]}"
    set +e
    git merge-file "$f" "$VENDOR/$PIN/$u" "$VENDOR/$LATEST/$u"
    rc=$?
    set -e
    conflicts=$(grep -c '^<<<<<<<' "$f" 2>/dev/null || true)
    echo "merge-file $f: exit=$rc conflicts=${conflicts:-0}"
done

if grep -q '^<<<<<<<' "${FILES[@]}" 2>/dev/null; then
    echo "ERROR: conflicts remain. Freedom carries no code of its own in these" >&2
    echo "files, so the safe resolution is upstream's side; the overlay puts the" >&2
    echo "Freedom rules back. Take upstream wholesale with:" >&2
    for i in "${!FILES[@]}"; do
        echo "  cp $VENDOR/$LATEST/${UPSTREAM[$i]} ${FILES[$i]}" >&2
    done
    echo "then re-run this script's remaining steps by hand." >&2
    exit 1
fi

"$PYTHON" "$ROOT/tools/apply_freedom_awg_overlay.py"
bash "$ROOT/tools/apply_freedom_awg_branding.sh" "$LATEST"
"$PYTHON" "$ROOT/tools/finish_awg_merge.py" "$LATEST"

for f in "${FILES[@]}" install_freedom.sh; do
    bash -n "$f"
done

# bivlked's *_en.sh are fully translated; any Cyrillic means we picked up a
# Russian file by mistake.
if grep -nP '[\xd0-\xd1][\x80-\xbf]' "${FILES[@]}"; then
    echo "ERROR: Cyrillic found — a Russian upstream file leaked in" >&2
    exit 1
fi

echo "Manual AWG merge complete: $PIN -> $LATEST"
