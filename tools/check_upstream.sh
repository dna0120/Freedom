#!/bin/bash
# Check Freedom's upstream sources against pinned versions.
# Exit 0 = up to date (or informational-only sources moved but unpinned)
# Exit 2 = pinned source has a newer release (bivlked / angristan pin mismatch)
# Exit 1 = tool/network error
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$ROOT/upstream/manifest.json"
REPORT="$ROOT/upstream/REPORT.md"
VENDOR="$ROOT/upstream/vendor"
UA="Freedom-upstream-check (+https://github.com/dna0120/Freedom)"

if [[ ! -f "$MANIFEST" ]]; then
    echo "ERROR: missing $MANIFEST" >&2
    exit 1
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: need $1" >&2; exit 1; }; }
need curl
_py=""
for _cand in python3 python py; do
    if command -v "$_cand" >/dev/null 2>&1; then
        if [[ "$_cand" == "py" ]]; then
            if py -3 -c "import json" >/dev/null 2>&1; then
                python3() { py -3 "$@"; }
                _py=1
                break
            fi
        elif "$_cand" -c "import json" >/dev/null 2>&1; then
            if [[ "$_cand" != "python3" ]]; then
                python3() { "$_cand" "$@"; }
            fi
            _py=1
            break
        fi
    fi
done
if [[ -z "$_py" ]]; then
    echo "ERROR: need a working Python 3 with json" >&2
    exit 1
fi

gh_json() {
    local url="$1"
    curl -fsSL --max-time 30 -H "User-Agent: $UA" -H "Accept: application/vnd.github+json" "$url"
}

latest_release_tag() {
    local repo="$1"
    gh_json "https://api.github.com/repos/${repo}/releases/latest" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))'
}

latest_commit() {
    local repo="$1" branch="${2:-master}"
    gh_json "https://api.github.com/repos/${repo}/commits/${branch}" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("sha",""))'
}

manifest_get() {
    python3 - "$MANIFEST" <<'PY'
import json, sys
from pathlib import Path
data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for s in data.get("sources", []):
    files = ",".join(s.get("files") or [])
    print("|".join([
        s.get("id",""),
        s.get("name",""),
        s.get("repo",""),
        s.get("track",""),
        s.get("pinned_tag",""),
        s.get("pinned_commit",""),
        s.get("branch","master"),
        files,
    ]))
PY
}

freedom_version() {
    python3 - "$MANIFEST" <<'PY'
import json, sys
from pathlib import Path
print(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")).get("freedom_version",""))
PY
}

download_bivlked_files() {
    local tag="$1" dest="$2"
    local f
    mkdir -p "$dest"
    for f in install_amneziawg_en.sh awg_common.sh manage_amneziawg.sh; do
        curl -fsSL --max-time 60 -o "$dest/$f" \
            "https://raw.githubusercontent.com/bivlked/amneziawg-installer/${tag}/${f}" \
            || echo "WARN: failed to fetch $f @$tag" >&2
    done
}

updates=0
errors=0
FV="$(freedom_version)"
NOW="$(date -u +'%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)"

{
    echo "# Upstream report"
    echo ""
    echo "Generated: \`$NOW\`"
    echo "Freedom script version: \`$FV\`"
    echo ""
    echo "| Source | Track | Pinned | Latest | Status |"
    echo "|---|---|---|---|---|"
} > "$REPORT"

BIVLKED_PIN=""
BIVLKED_LATEST=""

while IFS='|' read -r id name repo track pinned_tag pinned_commit branch files; do
    [[ -n "$id" ]] || continue
    latest=""
    status="ok"
    pin_display="—"
    latest_display="—"

    case "$track" in
        releases)
            if ! latest="$(latest_release_tag "$repo")"; then
                status="error"
                errors=1
                latest=""
            fi
            pin_display="${pinned_tag:-unpinned}"
            latest_display="${latest:-?}"
            if [[ -n "$pinned_tag" && -n "$latest" && "$latest" != "$pinned_tag" ]]; then
                status="UPDATE"
                updates=1
            elif [[ -z "$pinned_tag" && -n "$latest" ]]; then
                status="info"
            fi
            ;;
        commits)
            if ! latest="$(latest_commit "$repo" "$branch")"; then
                status="error"
                errors=1
                latest=""
            fi
            pin_display="${pinned_commit:-HEAD}"
            latest_display="${latest:0:12}"
            if [[ -n "$pinned_commit" && "$pinned_commit" != "HEAD" && -n "$latest" && "$latest" != "$pinned_commit" ]]; then
                status="UPDATE"
                updates=1
            else
                status="info"
            fi
            ;;
        *)
            status="error"
            errors=1
            ;;
    esac

    echo "| ${name} (\`${repo}\`) | ${track} | \`${pin_display}\` | \`${latest_display}\` | **${status}** |" >> "$REPORT"

    if [[ "$id" == "bivlked-awg" ]]; then
        BIVLKED_PIN="$pinned_tag"
        BIVLKED_LATEST="$latest"
    fi
done < <(manifest_get)

if [[ -n "$BIVLKED_PIN" && -n "$BIVLKED_LATEST" ]]; then
    pin_dir="$VENDOR/bivlked/$BIVLKED_PIN"
    new_dir="$VENDOR/bivlked/$BIVLKED_LATEST"
    download_bivlked_files "$BIVLKED_PIN" "$pin_dir"
    if [[ "$BIVLKED_LATEST" != "$BIVLKED_PIN" ]]; then
        download_bivlked_files "$BIVLKED_LATEST" "$new_dir"
        {
            echo ""
            echo "## bivlked diff \`${BIVLKED_PIN}\` → \`${BIVLKED_LATEST}\`"
            echo ""
            echo '```'
            diff -ruN "$pin_dir" "$new_dir" | head -n 400 || true
            echo '```'
            echo ""
            echo "Truncated to 400 lines. Full snapshots: \`$pin_dir\` and \`$new_dir\`."
        } >> "$REPORT"
    fi
fi

{
    echo ""
    echo "## Notes"
    echo ""
    echo "- Do **not** copy bivlked \`install_amneziawg_en.sh\` wholesale — Freedom uses \`install_freedom.sh\`."
    echo "- Daily CI applies bivlked→bivlked diffs onto English AWG helpers; see [UPSTREAM.md](../UPSTREAM.md)."
    echo "- Xray / Hysteria \`latest_observed\` is informational; VPS \`--update\` refreshes those binaries."
} >> "$REPORT"

echo "Wrote $REPORT"
if [[ "$errors" -ne 0 && "$updates" -eq 0 ]]; then
    exit 1
fi
if [[ "$updates" -ne 0 ]]; then
    echo "Upstream updates available."
    exit 2
fi
echo "Upstream pins are current."
exit 0
