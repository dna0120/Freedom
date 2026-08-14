# Upstream sources

Freedom is a fork-plus-extension. Runtime binaries are upgraded in place on the VPS. Installer source from bivlked is **never auto-merged**.

| Source | What Freedom uses | How updates land |
|---|---|---|
| [bivlked/amneziawg-installer](https://github.com/bivlked/amneziawg-installer) | AWG install/manage scripts | Manual cherry-pick after `tools/check_upstream.sh` |
| [angristan/wireguard-install](https://github.com/angristan/wireguard-install) | Menu UX reference | Read-only; no code import |
| [XTLS/Xray-core](https://github.com/XTLS/Xray-core) | Xray binary | VPS `--update` / menu 22 |
| [apernet/hysteria](https://github.com/apernet/hysteria) | Hysteria2 binary | VPS `--update` / menu 22 |

Pinned AWG installer tag lives in [`upstream/manifest.json`](upstream/manifest.json) (`bivlked-awg.pinned_tag`) and as `UPSTREAM_AWG_PIN` in `install_freedom.sh`. Current pin: **v5.21.2**.

## Maintainer check

```bash
bash tools/check_upstream.sh
```

- Exit `0`: every tracked source matches its pin (or has no pin).
- Exit `2`: at least one source has a newer release/commit.
- Writes [`upstream/REPORT.md`](upstream/REPORT.md). For bivlked, also snapshots files under `upstream/vendor/bivlked/<tag>/` and prints a `diff` summary (pinned tag vs latest).

A weekly GitHub Action opens or updates the issue titled `Upstream updates available`.

## Cherry-pick a bivlked release

1. Run `bash tools/check_upstream.sh` and read `upstream/REPORT.md`.
2. Open the vendor snapshot for the new tag and the unified diff vs the pinned tag.
3. Port only the relevant fixes into `install_freedom.sh` / `awg_common.sh` / `manage_amneziawg.sh`. Do not copy the upstream installer wholesale — Freedom already carries Xray, Hysteria2, the stack picker, CDN, DNS/MTU/BBR prompts.
4. Bump `pinned_tag` in `upstream/manifest.json` and `UPSTREAM_AWG_PIN` / `SCRIPT_VERSION` in the installer if you are aligning version numbers.
5. Recompute helper SHA256 pins in `install_freedom.sh`.
6. Re-run `bash tools/check_upstream.sh` (expect exit 0 for bivlked).

## VPS update (does not merge bivlked)

```bash
sudo bash install_freedom.sh --check-updates
sudo bash install_freedom.sh --update
```

Or menu option **22**. This refreshes Freedom helper scripts (SHA256-verified), upgrades Xray/Hysteria binaries, and **reports** AmneziaWG apt package updates without running `apt upgrade` (DKMS/reboot risk).
