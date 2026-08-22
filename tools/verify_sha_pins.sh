#!/bin/bash
# Verify SHA256 pins in install_freedom.sh match committed helper scripts.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$ROOT/install_freedom.sh"
PROJECT_REPO="${PROJECT_REPO:-dna0120/Freedom}"
FREEDOM_REF="${FREEDOM_REF:-main}"
RAW_BASE="https://raw.githubusercontent.com/${PROJECT_REPO}/${FREEDOM_REF}"

declare -A FILES=(
    [COMMON_SCRIPT_SHA256]="$ROOT/awg_common.sh"
    [MANAGE_SCRIPT_SHA256]="$ROOT/manage_amneziawg.sh"
    [XRAY_COMMON_SCRIPT_SHA256]="$ROOT/xray_common.sh"
    [XRAY_MANAGE_SCRIPT_SHA256]="$ROOT/manage_xray.sh"
    [HY2_COMMON_SCRIPT_SHA256]="$ROOT/hysteria_common.sh"
    [HY2_MANAGE_SCRIPT_SHA256]="$ROOT/manage_hysteria.sh"
)

declare -A RAW_NAMES=(
    [COMMON_SCRIPT_SHA256]="awg_common.sh"
    [MANAGE_SCRIPT_SHA256]="manage_amneziawg.sh"
    [XRAY_COMMON_SCRIPT_SHA256]="xray_common.sh"
    [XRAY_MANAGE_SCRIPT_SHA256]="manage_xray.sh"
    [HY2_COMMON_SCRIPT_SHA256]="hysteria_common.sh"
    [HY2_MANAGE_SCRIPT_SHA256]="manage_hysteria.sh"
)

extract_pin() {
    sed -n "s/^$1=\"\\([^\"]*\\)\".*/\\1/p" "$INSTALLER"
}

fail=0
for var in "${!FILES[@]}"; do
    expected="$(extract_pin "$var")"
    file="${FILES[$var]}"
    actual="$(sha256sum "$file" | awk '{print $1}')"
    if [[ "$expected" != "$actual" ]]; then
        echo "MISMATCH $var: pin=$expected file=$actual" >&2
        fail=1
        continue
    fi
    echo "OK $var (local disk)"

    if command -v curl >/dev/null 2>&1; then
        raw="${RAW_BASE}/${RAW_NAMES[$var]}"
        tmp="$(mktemp)"
        if curl -fsSL --max-time 30 "$raw" -o "$tmp" 2>/dev/null; then
            raw_hash="$(sha256sum "$tmp" | awk '{print $1}')"
            if [[ "$raw_hash" != "$actual" ]]; then
                echo "WARN $var: local file differs from raw.githubusercontent.com ($FREEDOM_REF) — check line endings before push" >&2
                echo "      local=$actual raw=$raw_hash" >&2
                fail=1
            else
                echo "OK $var (raw GitHub ref ${FREEDOM_REF})"
            fi
        else
            echo "SKIP $var raw fetch (offline or ref not published yet)" >&2
        fi
        rm -f "$tmp"
    fi
done

exit "$fail"
