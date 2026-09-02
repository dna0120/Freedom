#!/bin/bash
# Prepare an automated upstream sync commit (used by GitHub Actions → Pull Request).
#
# - Refreshes observed latest releases for Xray / Hysteria2 in upstream/manifest.json
# - When bivlked has a newer tag: downloads vendor snapshots, applies bivlked→bivlked
#   diffs onto Freedom's English AWG helpers, re-applies branding, bumps pins
#
# Exit 0 = no file changes
# Exit 3 = working tree updated (ready for PR)
# Exit 1 = error
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/upstream/manifest.json"
INSTALLER="$ROOT/install_freedom.sh"
VENDOR="$ROOT/upstream/vendor/bivlked"
BODY="$ROOT/upstream/SYNC_PR_BODY.md"
UA="Freedom-upstream-sync (+https://github.com/dna0120/Freedom)"

need() {
    if command -v "$1" >/dev/null 2>&1; then
        return 0
    fi
    echo "ERROR: need $1 (Ubuntu/Debian: apt install $1)" >&2
    exit 1
}
need curl
need python3
need git
if ! command -v patch >/dev/null 2>&1; then
    echo "ERROR: need patch (Ubuntu/Debian: apt install patch)" >&2
    exit 1
fi

gh_json() {
    curl -fsSL --max-time 30 -H "User-Agent: $UA" -H "Accept: application/vnd.github+json" "$1"
}

latest_release_tag() {
    gh_json "https://api.github.com/repos/$1/releases/latest" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))'
}

extract_installer_var() {
    sed -n "s/^${1}=\"\\([^\"]*\\)\".*/\\1/p" "$INSTALLER"
}

bump_patch_version() {
    python3 - "$1" <<'PY'
import sys
v = sys.argv[1].split(".")
if len(v) != 3 or not all(p.isdigit() for p in v):
    print(v[0] if v else "0.0.1")
else:
    v[-1] = str(int(v[-1]) + 1)
    print(".".join(v))
PY
}

download_bivlked() {
    local tag="$1" dest="$2" f
    mkdir -p "$dest"
    for f in awg_common.sh manage_amneziawg.sh install_amneziawg_en.sh; do
        curl -fsSL --max-time 60 -o "$dest/$f" \
            "https://raw.githubusercontent.com/bivlked/amneziawg-installer/${tag}/${f}" \
            || return 1
    done
}

# Sync Freedom's forked AWG helper with a newer bivlked tag.
# 1) git merge-file three-way (base=pin, ours=Freedom, theirs=new tag)
# 2) overlay: copy bivlked@new, re-apply Freedom customizations from diff(pin, Freedom)
apply_bivlked_sync() {
    local old="$1"
    local new="$2"
    local file="$3"
    local target="$ROOT/$file"
    local oldf="$VENDOR/$old/$file" newf="$VENDOR/$new/$file"
    local bak patchf rej
    [[ -f "$target" && -f "$oldf" && -f "$newf" ]] || return 1

    if diff -q "$oldf" "$newf" >/dev/null 2>&1; then
        echo "No bivlked changes for $file ($old → $new)"
        return 0
    fi

    bak="${target}.sync.bak"
    cp -a "$target" "$bak"

    # --- Strategy A: three-way merge (best for small pin→latest gaps) ---
    cp -a "$bak" "$target"
    set +e
    git merge-file "$target" "$oldf" "$newf"
    local merge_rc=$?
    set -e
    if [[ "$merge_rc" -eq 0 ]]; then
        rm -f "$bak"
        echo "Applied three-way merge to $file ($old → $new)"
        return 0
    fi
    if [[ "$merge_rc" -eq 1 ]] && ! grep -q '^<<<<<<<' "$target" 2>/dev/null; then
        rm -f "$bak"
        echo "Applied three-way merge to $file ($old → $new, minor conflicts auto-resolved)"
        return 0
    fi

    # --- Strategy B: bivlked@new + Freedom overlay (English/branding on top of upstream) ---
    cp -a "$newf" "$target"
    patchf="$(mktemp)"
    diff -u "$oldf" "$bak" > "$patchf" || true
    if [[ -s "$patchf" ]]; then
        set +e
        # --no-backup-if-mismatch: GNU patch otherwise leaves a .orig on any
        # fuzzed/rejected hunk, and `git add -A` in CI commits it.
        patch --forward --batch --fuzz=3 --no-backup-if-mismatch "$target" < "$patchf"
        local patch_rc=$?
        set -e
        rej="${target}.rej"
        if [[ "$patch_rc" -eq 0 && ! -f "$rej" ]]; then
            rm -f "$bak" "$patchf" "${target}.orig"
            echo "Applied overlay sync to $file ($old → $new)"
            return 0
        fi
        rm -f "$rej" "${target}.orig"
    fi

    mv -f "$bak" "$target"
    rm -f "$patchf" "${target}.orig"
    echo "ERROR: AWG sync failed for $file ($old → $new) — three-way and overlay both failed" >&2
    return 1
}

cd "$ROOT"
CHANGES=0
NOTES=()
set +e

# --- Observed latest releases (informational; VPS --update pulls binaries) ---
XRAY_LATEST="$(latest_release_tag XTLS/Xray-core || true)"
HY2_LATEST="$(latest_release_tag apernet/hysteria || true)"
BIVLKED_LATEST="$(latest_release_tag bivlked/amneziawg-installer || true)"
BIVLKED_PIN="$(python3 - "$MANIFEST" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for s in data.get("sources", []):
    if s.get("id") == "bivlked-awg":
        print(s.get("pinned_tag", ""))
        break
PY
)"

manifest_info_changed="$(
python3 - "$MANIFEST" "$XRAY_LATEST" "$HY2_LATEST" "$BIVLKED_LATEST" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
xray, hy2, biv = sys.argv[2:5]
changed = False
for s in data.get("sources", []):
    if s.get("id") == "xray-core" and xray:
        if s.get("latest_observed") != xray:
            s["latest_observed"] = xray
            changed = True
    if s.get("id") == "hysteria" and hy2:
        if s.get("latest_observed") != hy2:
            s["latest_observed"] = hy2
            changed = True
    if s.get("id") == "bivlked-awg" and biv:
        if s.get("latest_observed") != biv:
            s["latest_observed"] = biv
            changed = True
if changed:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print("1" if changed else "0")
PY
)"
if [[ "$manifest_info_changed" == "1" ]]; then
    CHANGES=1
fi

# --- bivlked AWG helper sync ---
AWG_SYNCED=0
if [[ -n "$BIVLKED_PIN" && -n "$BIVLKED_LATEST" && "$BIVLKED_LATEST" != "$BIVLKED_PIN" ]]; then
    echo "bivlked update: ${BIVLKED_PIN} → ${BIVLKED_LATEST}"
    if ! download_bivlked "$BIVLKED_PIN" "$VENDOR/$BIVLKED_PIN"; then
        NOTES+=("Failed to download bivlked vendor snapshot for \`${BIVLKED_PIN}\`.")
    elif ! download_bivlked "$BIVLKED_LATEST" "$VENDOR/$BIVLKED_LATEST"; then
        NOTES+=("Failed to download bivlked vendor snapshot for \`${BIVLKED_LATEST}\`.")
    else
        awg_ok=1
        for f in awg_common.sh manage_amneziawg.sh; do
            if ! apply_bivlked_sync "$BIVLKED_PIN" "$BIVLKED_LATEST" "$f"; then
                awg_ok=0
                NOTES+=("AWG sync failed for \`$f\` — manual cherry-pick required (see \`upstream/vendor/bivlked/\`).")
                git checkout -- "$f" 2>/dev/null || true
            fi
        done

        if [[ "$awg_ok" -eq 1 ]]; then
            bash "$ROOT/tools/apply_freedom_awg_branding.sh" "$BIVLKED_LATEST" || {
                awg_ok=0
                NOTES+=("Freedom branding step failed after AWG patch.")
                git checkout -- awg_common.sh manage_amneziawg.sh 2>/dev/null || true
            }
        fi
        if [[ "$awg_ok" -eq 1 ]]; then
            VER="${BIVLKED_LATEST#v}"
            sed -i "s/^SCRIPT_VERSION=\"[^\"]*\"/SCRIPT_VERSION=\"${VER}\"/" "$INSTALLER"
            sed -i "s/^UPSTREAM_AWG_PIN=\"[^\"]*\"/UPSTREAM_AWG_PIN=\"${BIVLKED_LATEST}\"/" "$INSTALLER"
            python3 - "$MANIFEST" "$BIVLKED_LATEST" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
tag = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))
for s in data.get("sources", []):
    if s.get("id") == "bivlked-awg":
        s["pinned_tag"] = tag
        s["latest_observed"] = tag
        break
path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
            AWG_SYNCED=1
            CHANGES=1
            NOTES+=("AmneziaWG helpers synced via bivlked delta ${BIVLKED_PIN} → ${BIVLKED_LATEST}.")
        else
            NOTES+=("Skipped AWG pin bump because patch did not apply cleanly.")
        fi
    fi
else
    echo "bivlked pin current (${BIVLKED_PIN:-unknown})."
fi

# --- Freedom patch version + SHA pins (AWG code sync only) ---
if [[ "$AWG_SYNCED" -eq 1 ]]; then
    OLD_FV="$(extract_installer_var FREEDOM_VERSION)"
    NEW_FV="$(bump_patch_version "${OLD_FV:-1.0.0}")"
    sed -i "s/^FREEDOM_VERSION=\"[^\"]*\"/FREEDOM_VERSION=\"${NEW_FV}\"/" "$INSTALLER"
    python3 - "$MANIFEST" "$NEW_FV" <<'PY'
import json, sys
from pathlib import Path
path = Path(sys.argv[1])
fv = sys.argv[2]
data = json.loads(path.read_text(encoding="utf-8"))
if data.get("freedom_version") != fv:
    data["freedom_version"] = fv
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
    bash "$ROOT/tools/update_sha_pins.sh" || {
        echo "WARN: update_sha_pins failed; continuing with manifest/report updates." >&2
    }
fi

if [[ "$CHANGES" -eq 1 ]]; then
    bash "$ROOT/tools/check_upstream.sh" || true
fi

# --- PR body ---
{
    echo "# Automated upstream sync"
    echo ""
    echo "Generated: \`$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)\`"
    echo ""
    echo "| Source | Latest observed | Freedom pin |"
    echo "|---|---|---|"
    echo "| Xray-core | \`${XRAY_LATEST:-?}\` | VPS \`--update\` |"
    echo "| Hysteria2 | \`${HY2_LATEST:-?}\` | VPS \`--update\` |"
    echo "| bivlked AWG | \`${BIVLKED_LATEST:-?}\` | \`${BIVLKED_PIN:-?}\` → sync attempted |"
    echo ""
    if ((${#NOTES[@]})); then
        echo "## Notes"
        for n in "${NOTES[@]}"; do
            echo "- $n"
        done
        echo ""
    fi
    echo "## VPS (manual)"
    echo ""
    echo "\`sudo bash install_freedom.sh --check-updates\` then \`--update\` when you want to apply on the server."
    echo ""
    if [[ -f "$ROOT/upstream/REPORT.md" ]]; then
        echo "## Upstream report"
        echo ""
        cat "$ROOT/upstream/REPORT.md"
    fi
} > "$BODY"

if ! git diff --quiet --exit-code 2>/dev/null; then
    CHANGES=1
fi

if [[ "$CHANGES" -eq 0 ]]; then
    echo "No upstream sync changes."
    exit 0
fi

echo "Upstream sync prepared (freedom bump + pins refreshed)."
exit 3
