#!/bin/bash
# One-time manual AWG catch-up when the daily CI sync cannot apply cleanly.
#
# Usage: manual_awg_merge.sh <current pin> <target tag>
#   e.g. manual_awg_merge.sh v5.30.0 v5.31.0
#
# Freedom's AWG helpers are an English fork of bivlked's Russian scripts, so a
# plain delta patch never applies. This walks the documented path instead:
# three-way merge -> conflict resolver -> log translation -> branding -> pins.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PIN="${1:?usage: manual_awg_merge.sh <current pin> <target tag>}"
LATEST="${2:?usage: manual_awg_merge.sh <current pin> <target tag>}"
VENDOR="$ROOT/upstream/vendor/bivlked"
PYTHON="${PYTHON:-python3}"
FILES=(awg_common.sh manage_amneziawg.sh)

mkdir -p "$VENDOR/$PIN" "$VENDOR/$LATEST"
for f in "${FILES[@]}"; do
    curl -fsSL -o "$VENDOR/$PIN/$f" \
        "https://raw.githubusercontent.com/bivlked/amneziawg-installer/${PIN}/${f}"
    curl -fsSL -o "$VENDOR/$LATEST/$f" \
        "https://raw.githubusercontent.com/bivlked/amneziawg-installer/${LATEST}/${f}"
done

for f in "${FILES[@]}"; do
    cp "$f" "${f}.bak"
    set +e
    git merge-file "$f" "$VENDOR/$PIN/$f" "$VENDOR/$LATEST/$f"
    rc=$?
    set -e
    conflicts=$(grep -c '^<<<<<<<' "$f" 2>/dev/null || true)
    echo "merge-file $f: exit=$rc conflicts=${conflicts:-0}"
done

if grep -q '^<<<<<<<' "${FILES[@]}" 2>/dev/null; then
    "$PYTHON" "$ROOT/tools/resolve_awg_merge.py" "$LATEST"
fi

if grep -q '^<<<<<<<' "${FILES[@]}" 2>/dev/null; then
    echo "ERROR: unresolved conflicts remain — resolve by hand before continuing" >&2
    exit 1
fi

"$PYTHON" "$ROOT/tools/translate_awg_logs.py"
bash "$ROOT/tools/apply_freedom_awg_branding.sh" "$LATEST"
"$PYTHON" "$ROOT/tools/finish_awg_merge.py" "$LATEST"

rm -f "${FILES[@]/%/.bak}"

for f in "${FILES[@]}" install_freedom.sh; do
    bash -n "$f"
done

# Cyrillic left in a user-facing string means translate_awg_logs.py needs a new
# entry; comments are allowed to keep the upstream wording.
if grep -nE '(log_|_diag_line|die |echo ).*[\xd0-\xd1]' "${FILES[@]}"; then
    echo "WARN: untranslated Russian strings above — add them to translate_awg_logs.py" >&2
fi

echo "Manual AWG merge complete: $PIN -> $LATEST"
