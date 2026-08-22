#!/bin/bash
# Regenerate SHA256 pin lines in install_freedom.sh from current helper files.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/install_freedom.sh"

declare -A FILES=(
    [COMMON_SCRIPT_SHA256]="$ROOT/awg_common.sh"
    [MANAGE_SCRIPT_SHA256]="$ROOT/manage_amneziawg.sh"
    [XRAY_COMMON_SCRIPT_SHA256]="$ROOT/xray_common.sh"
    [XRAY_MANAGE_SCRIPT_SHA256]="$ROOT/manage_xray.sh"
    [HY2_COMMON_SCRIPT_SHA256]="$ROOT/hysteria_common.sh"
    [HY2_MANAGE_SCRIPT_SHA256]="$ROOT/manage_hysteria.sh"
)

tmp="$(mktemp)"
cp "$INSTALLER" "$tmp"

for var in "${!FILES[@]}"; do
    hash="$(sha256sum "${FILES[$var]}" | awk '{print $1}')"
    sed -i "s/^${var}=\"[^\"]*\"/${var}=\"${hash}\"/" "$tmp"
    echo "Updated $var=$hash"
done

mv -f "$tmp" "$INSTALLER"
echo "Pins written to $INSTALLER"
