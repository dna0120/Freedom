#!/usr/bin/env python3
"""Re-apply Freedom's customisations on top of bivlked's English AWG helpers.

Freedom tracks bivlked's official `*_en.sh` variants, so the only delta is this
file: branding, the 1420 MTU default, and operator-configurable client DNS.

Every rule is an exact string swap that must resolve to one of three states:
already applied (idempotent), applicable, or **missing** — in which case the
script fails loudly. That is deliberate: a silently dropped customisation is far
worse than a red CI run, because it ships a wrong config to every client.

Usage: apply_freedom_awg_overlay.py [--check]
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FREEDOM_RAW = "https://raw.githubusercontent.com/dna0120/Freedom/main"

# (file, description, upstream text, Freedom text)
RULES: list[tuple[str, str, str, str]] = [
    # --- branding -------------------------------------------------------
    (
        "awg_common.sh",
        "author header",
        "# Author: @bivlked\n",
        "# Author: @dna0120\n",
    ),
    (
        "awg_common.sh",
        "repository header",
        "# Repository: https://github.com/bivlked/amneziawg-installer\n",
        "# Repository: https://github.com/dna0120/Freedom\n",
    ),
    (
        "manage_amneziawg.sh",
        "author header",
        "# Author: @bivlked\n",
        "# Author: @dna0120\n",
    ),
    (
        "manage_amneziawg.sh",
        "repository header",
        "# Repository: https://github.com/bivlked/amneziawg-installer\n",
        "# Repository: https://github.com/dna0120/Freedom\n",
    ),
    (
        "manage_amneziawg.sh",
        "self-update hint points at Freedom, which serves the helpers",
        "  wget -O $AWG_DIR/manage_amneziawg.sh https://raw.githubusercontent.com/bivlked/amneziawg-installer/v$want/manage_amneziawg_en.sh\n"
        "  wget -O $COMMON_SCRIPT_PATH https://raw.githubusercontent.com/bivlked/amneziawg-installer/v$want/awg_common_en.sh\n",
        f"  wget -O $AWG_DIR/manage_amneziawg.sh {FREEDOM_RAW}/manage_amneziawg.sh\n"
        f"  wget -O $COMMON_SCRIPT_PATH {FREEDOM_RAW}/awg_common.sh\n",
    ),
    (
        "manage_amneziawg.sh",
        "installer name (Freedom ships install_freedom.sh)",
        'die "Installation files not found. Run install_amneziawg_en.sh."',
        'die "Installation files not found. Run install_freedom.sh."',
    ),
    (
        "manage_amneziawg.sh",
        "help text drops the upstream-only ADVANCED.en.md reference",
        '    echo "  --json                Machine-readable JSON output (most commands; details in ADVANCED.en.md)"',
        '    echo "  --json                Machine-readable JSON output (most commands)"',
    ),
    # --- 1420 MTU default ------------------------------------------------
    # Freedom targets consumer links behind PPPoE/CGNAT where 1420 is the
    # WireGuard norm; 1280 costs throughput for no gain here. Jmin/Jmax bounds
    # also mention 1280 but are protocol limits and must stay untouched.
    (
        "awg_common.sh",
        "MSS clamp comment",
        '    # stall against the 1280 tunnel when ICMP "frag needed" is filtered (PMTU',
        '    # stall against the 1420 tunnel when ICMP "frag needed" is filtered (PMTU',
    ),
    (
        "awg_common.sh",
        "MSS clamp MTU default",
        'local awg_mtu="${AWG_MTU:-1280}"',
        'local awg_mtu="${AWG_MTU:-1420}"',
    ),
    (
        "awg_common.sh",
        "server config MTU default",
        "MTU = ${AWG_MTU:-1280}\n",
        "MTU = ${AWG_MTU:-1420}\n",
    ),
    (
        "awg_common.sh",
        "_validate_mtu comment",
        "# Values outside the range are treated as invalid and dropped (fallback to 1280).",
        "# Values outside the range are treated as invalid and dropped (fallback to 1420).",
    ),
    (
        "awg_common.sh",
        "client MTU resolution comment",
        "    # 1280 fallback. Server config is the source of truth for a running server -",
        "    # 1420 fallback. Server config is the source of truth for a running server -",
    ),
    (
        "awg_common.sh",
        "client MTU rollback comment",
        "    # values (outside 576..9100) at any stage roll back to 1280.",
        "    # values (outside 576..9100) at any stage roll back to 1420.",
    ),
    (
        "awg_common.sh",
        "client MTU fallback",
        "        else\n            mtu=1280\n        fi",
        "        else\n            mtu=1420\n        fi",
    ),
    (
        "awg_common.sh",
        "vpn:// URI MTU fallback",
        'mtu="${mtu:-1280}"',
        'mtu="${mtu:-1420}"',
    ),
    # --- operator-configurable client DNS --------------------------------
    (
        "awg_common.sh",
        "CLIENT_DNS_1/2 and ENABLE_BBR are Freedom keys in awgsetup_cfg.init",
        "AWG_APPLY_MODE|ALLOW_IPV6_TUNNEL|IPV6_SUBNET|SERVER_HAS_NATIVE_IPV6|PREV_AWG_PORT|CLIENT_ISOLATION|CLIENT_ISOLATION_NET|AWG_SERVER_NAME)",
        "AWG_APPLY_MODE|ALLOW_IPV6_TUNNEL|IPV6_SUBNET|SERVER_HAS_NATIVE_IPV6|PREV_AWG_PORT|CLIENT_ISOLATION|CLIENT_ISOLATION_NET|AWG_SERVER_NAME|ENABLE_BBR|CLIENT_DNS_1|CLIENT_DNS_2)",
    ),
    (
        "awg_common.sh",
        "resolve client DNS from config before rendering",
        "    # temp in the client config dir ($AWG_DIR) -> mv = atomic rename.\n"
        "    local tmpfile\n",
        "    local client_dns\n"
        '    if [[ -n "${CLIENT_DNS_1:-}" ]]; then\n'
        '        client_dns="${CLIENT_DNS_1}, ${CLIENT_DNS_2:-$CLIENT_DNS_1}"\n'
        "    else\n"
        '        client_dns="1.1.1.1, 1.0.0.1"\n'
        "    fi\n"
        "\n"
        "    # temp in the client config dir ($AWG_DIR) -> mv = atomic rename.\n"
        "    local tmpfile\n",
    ),
    (
        "awg_common.sh",
        "client config uses the resolved DNS",
        "DNS = 1.1.1.1, 1.0.0.1\nMTU = ${mtu}\n",
        "DNS = ${client_dns}\nMTU = ${mtu}\n",
    ),
]


def main() -> None:
    check_only = "--check" in sys.argv[1:]
    texts = {name: (ROOT / name).read_text(encoding="utf-8") for name in ("awg_common.sh", "manage_amneziawg.sh")}

    applied = skipped = 0
    missing: list[str] = []

    for name, desc, upstream, freedom in RULES:
        text = texts[name]
        if freedom in text:
            skipped += 1
            continue
        if upstream not in text:
            missing.append(f"{name}: {desc}")
            continue
        if text.count(upstream) != 1:
            missing.append(f"{name}: {desc} (matched {text.count(upstream)} times, expected 1)")
            continue
        texts[name] = text.replace(upstream, freedom, 1)
        applied += 1
        print(f"applied  {name}: {desc}")

    if missing:
        print("\nFreedom customisations that no longer match upstream:", file=sys.stderr)
        for item in missing:
            print(f"  - {item}", file=sys.stderr)
        print(
            "\nUpstream reworded or moved these blocks. Update RULES in this file "
            "before shipping, otherwise the customisation is silently lost.",
            file=sys.stderr,
        )
        raise SystemExit(1)

    if check_only:
        print(f"check: {skipped} already applied, {applied} would be applied")
        raise SystemExit(0 if applied == 0 else 1)

    for name, text in texts.items():
        # newline="" keeps LF on Windows so the SHA256 pins match the git blob.
        (ROOT / name).write_text(text, encoding="utf-8", newline="")

    print(f"Freedom overlay: {applied} applied, {skipped} already in place")


if __name__ == "__main__":
    main()
