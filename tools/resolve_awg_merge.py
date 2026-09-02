#!/usr/bin/env python3
"""Resolve git merge-file conflicts for Freedom AWG sync (English fork + bivlked).

Usage: resolve_awg_merge.py <target version, e.g. 5.31.0>
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

TARGET_VERSION = "0.0.0"

CONFLICT_RE = re.compile(
    r"^<<<<<<< .*?\n(.*?)^=======\n(.*?)^>>>>>>> .*?\n",
    re.MULTILINE | re.DOTALL,
)

CYRILLIC = re.compile(r"[\u0400-\u04FF]")


def has_cyrillic(s: str) -> bool:
    return bool(CYRILLIC.search(s))


def is_header_block(ours: str, theirs: str) -> bool:
    return "Author:" in ours or "Автор:" in theirs or "Version:" in ours or "Версия:" in theirs


def is_version_only(ours: str, theirs: str) -> bool:
    return "AWG_COMMON_VERSION" in ours + theirs or "SCRIPT_VERSION" in ours + theirs


def theirs_has_new_symbols(theirs: str, ours: str) -> bool:
    fn = set(re.findall(r"^(?:function |[a-z_][a-z0-9_]*\(\))", theirs, re.M))
    new_defs = re.findall(r"^([a-z_][a-z0-9_]*)\(\)", theirs, re.M)
    ours_text = ours
    return any(d not in ours_text for d in new_defs if d.startswith("awg_") or d.startswith("_awg_"))


def prefer_theirs_functionality(ours: str, theirs: str) -> bool:
    markers = (
        "awg_normalize_csv",
        "awg_warn_interface_disruption",
        "awg_record_device_params",
        "awg_ssh_client_addr",
        "KEEP_PACKAGES",
        "paste -sd, -",
        "awg_warn_multiline",
    )
    return any(m in theirs and m not in ours for m in markers)


def english_log_block(ours: str) -> bool:
    return not has_cyrillic(ours) and ("log" in ours or "die " in ours or "echo " in ours)


def resolve_block(ours: str, theirs: str, filename: str) -> str:
    ours = ours.rstrip("\n") + "\n"
    theirs = theirs.rstrip("\n") + "\n"

    if is_header_block(ours, theirs):
        # Freedom English header; version bumped later by branding script
        out = ours
        # Version fields bumped later by apply_freedom_awg_branding.sh
        out = re.sub(r"Version: [\d.]+", f"Version: {TARGET_VERSION}", out)
        out = re.sub(r'AWG_COMMON_VERSION="[\d.]+"', f'AWG_COMMON_VERSION="{TARGET_VERSION}"', out)
        out = re.sub(r'SCRIPT_VERSION="[\d.]+"', f'SCRIPT_VERSION="{TARGET_VERSION}"', out)
        return out

    if prefer_theirs_functionality(ours, theirs):
        return theirs

    if english_log_block(ours) and not theirs_has_new_symbols(theirs, ours):
        return ours

    if has_cyrillic(theirs) and not has_cyrillic(ours):
        if theirs_has_new_symbols(theirs, ours) or len(theirs) > len(ours) * 1.2:
            return theirs
        return ours

    if len(theirs) > len(ours):
        return theirs
    return ours


def resolve_file(path: Path) -> int:
    text = path.read_text(encoding="utf-8")
    n = 0

    def repl(m: re.Match) -> str:
        nonlocal n
        n += 1
        return resolve_block(m.group(1), m.group(2), path.name)

    resolved = CONFLICT_RE.sub(repl, text)
    if "<<<<<<<" in resolved:
        raise SystemExit(f"Unresolved conflicts remain in {path}")
    # newline="" keeps LF on Windows; the SHA256 pins in install_freedom.sh
    # must match the LF blob that GitHub serves to the VPS.
    path.write_text(resolved, encoding="utf-8", newline="")
    return n


def main() -> None:
    global TARGET_VERSION
    if len(sys.argv) > 1:
        TARGET_VERSION = sys.argv[1].lstrip("v")
    elif os.environ.get("AWG_TARGET_VERSION"):
        TARGET_VERSION = os.environ["AWG_TARGET_VERSION"].lstrip("v")
    else:
        raise SystemExit("usage: resolve_awg_merge.py <target version, e.g. 5.31.0>")

    root = Path(__file__).resolve().parents[1]
    total = 0
    for name in ("awg_common.sh", "manage_amneziawg.sh"):
        p = root / name
        c = resolve_file(p)
        print(f"Resolved {c} conflicts in {name}")
        total += c
    print(f"Total: {total}")


if __name__ == "__main__":
    main()
