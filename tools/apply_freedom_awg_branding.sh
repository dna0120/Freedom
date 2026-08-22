#!/bin/bash
# Re-apply Freedom version fields after applying a bivlked delta patch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?usage: apply_freedom_awg_branding.sh <tag e.g. v5.21.2>}"
VER="${TAG#v}"
DATE="$(date -u +'%Y-%m-%d' 2>/dev/null || date +'%Y-%m-%d')"

for f in "$ROOT/awg_common.sh" "$ROOT/manage_amneziawg.sh"; do
    [[ -f "$f" ]] || continue
    sed -i "s/^# Version: .*/# Version: ${VER}/" "$f"
    sed -i "s/^# Date: .*/# Date: ${DATE}/" "$f"
    sed -i 's|^# Repository: .*|# Repository: https://github.com/dna0120/Freedom|' "$f"
    sed -i 's/^# Author: .*/# Author: @dna0120/' "$f"
done

sed -i "s/^AWG_COMMON_VERSION=\"[^\"]*\"/AWG_COMMON_VERSION=\"${VER}\"/" "$ROOT/awg_common.sh" 2>/dev/null || true
echo "Freedom branding applied for AWG helpers @ ${TAG}"
