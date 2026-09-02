#!/usr/bin/env python3
"""Finish a manual AWG merge: bump pins, manifest and SHA256 hashes.

Usage: finish_awg_merge.py <bivlked tag, e.g. v5.31.0>
"""
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALLER = ROOT / "install_freedom.sh"
MANIFEST = ROOT / "upstream/manifest.json"

FILES = {
    "COMMON_SCRIPT_SHA256": ROOT / "awg_common.sh",
    "MANAGE_SCRIPT_SHA256": ROOT / "manage_amneziawg.sh",
    "XRAY_COMMON_SCRIPT_SHA256": ROOT / "xray_common.sh",
    "XRAY_MANAGE_SCRIPT_SHA256": ROOT / "manage_xray.sh",
    "HY2_COMMON_SCRIPT_SHA256": ROOT / "hysteria_common.sh",
    "HY2_MANAGE_SCRIPT_SHA256": ROOT / "manage_hysteria.sh",
}

ARTIFACTS = (
    "awg_common.sh.orig",
    "manage_amneziawg.sh.orig",
    "awg_common.sh.bak",
    "manage_amneziawg.sh.bak",
    "awg_common.sh.rej",
    "manage_amneziawg.sh.rej",
)


def bump_patch(version: str) -> str:
    parts = version.split(".")
    parts[-1] = str(int(parts[-1]) + 1)
    return ".".join(parts)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: finish_awg_merge.py <bivlked tag, e.g. v5.31.0>")
    tag = sys.argv[1]
    if not tag.startswith("v"):
        tag = "v" + tag
    ver = tag[1:]

    text = INSTALLER.read_text(encoding="utf-8")
    current_fv = re.search(r'^FREEDOM_VERSION="([^"]*)"', text, flags=re.M)
    if not current_fv:
        raise SystemExit("FREEDOM_VERSION not found in install_freedom.sh")
    new_fv = bump_patch(current_fv.group(1))

    text = re.sub(r'^SCRIPT_VERSION="[^"]*"', f'SCRIPT_VERSION="{ver}"', text, count=1, flags=re.M)
    text = re.sub(r'^UPSTREAM_AWG_PIN="[^"]*"', f'UPSTREAM_AWG_PIN="{tag}"', text, count=1, flags=re.M)
    text = re.sub(r'^FREEDOM_VERSION="[^"]*"', f'FREEDOM_VERSION="{new_fv}"', text, count=1, flags=re.M)
    text = re.sub(r"^# Version: .*", f"# Version: {ver}", text, count=1, flags=re.M)

    for var, path in FILES.items():
        # Hash the LF form: .gitattributes stores *.sh with eol=lf, and the VPS
        # verifies against the raw.githubusercontent blob, not the local file.
        digest = hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()
        text = re.sub(rf'^{var}="[^"]*"', f'{var}="{digest}"', text, count=1, flags=re.M)
        print(f"Updated {var}={digest}")
    INSTALLER.write_text(text, encoding="utf-8", newline="")

    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    data["freedom_version"] = new_fv
    for source in data.get("sources", []):
        if source.get("id") == "bivlked-awg":
            source["pinned_tag"] = tag
            source["latest_observed"] = tag
    MANIFEST.write_text(
        json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline=""
    )
    print(f"Manifest: pin={tag}, freedom={new_fv}")

    for name in ARTIFACTS:
        path = ROOT / name
        if path.exists():
            path.unlink()
            print(f"Removed {name}")


if __name__ == "__main__":
    main()
