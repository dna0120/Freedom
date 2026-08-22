# Upstream sources

Freedom is a fork-plus-extension. **GitHub Actions** keeps observed upstream releases fresh and opens automated PRs. **VPS** updates stay manual (`--update` / menu 22).

| Source | What Freedom uses | How updates land |
|---|---|---|
| [bivlked/amneziawg-installer](https://github.com/bivlked/amneziawg-installer) | AWG install/manage scripts | Daily CI: bivlked→bivlked diff onto English helpers → PR → auto-merge when CI passes |
| [angristan/wireguard-install](https://github.com/angristan/wireguard-install) | Menu UX reference | Read-only; no code import |
| [XTLS/Xray-core](https://github.com/XTLS/Xray-core) | Xray binary | `latest_observed` in manifest (CI daily); VPS `--update` installs binary |
| [apernet/hysteria](https://github.com/apernet/hysteria) | Hysteria2 binary | Same as Xray |

Pinned AWG installer tag: [`upstream/manifest.json`](upstream/manifest.json) (`bivlked-awg.pinned_tag`) and `UPSTREAM_AWG_PIN` in `install_freedom.sh`. Current pin: **v5.21.2**.

## Automated GitHub sync (daily)

Workflow: [`.github/workflows/upstream-check.yml`](.github/workflows/upstream-check.yml) (cron `0 6 * * *` UTC + manual dispatch).

1. Runs `tools/check_upstream.sh` → `upstream/REPORT.md`; opens/updates issue **Upstream updates available** when a pinned source is behind.
2. Runs `tools/sync_upstream_pr.sh`:
   - Refreshes `latest_observed` for Xray, Hysteria2, and bivlked in `upstream/manifest.json`.
   - When bivlked has a newer tag: vendor snapshots under `upstream/vendor/bivlked/<tag>/`, applies the **bivlked old→new diff** onto Freedom’s English `awg_common.sh` / `manage_amneziawg.sh`, re-applies branding, bumps `UPSTREAM_AWG_PIN` / `SCRIPT_VERSION` / `FREEDOM_VERSION`, recomputes SHA256 pins.
3. Pushes branch `auto/upstream-sync` (always, with `contents: write`).
4. Tries to open/update a PR via `gh` (optional; needs the repo setting below). If PR creation is blocked, the workflow still **succeeds** — use the **compare link** in the job summary to open a PR manually.
5. **[Upstream sync CI](.github/workflows/upstream-pr-ci.yml)** (`pull_request_target`) runs checks on bot-opened PRs **without** the `action_required` approval gate that blocks normal `pull_request` CI.
6. **[Upstream auto-merge](.github/workflows/upstream-auto-merge.yml)** squash-merges the PR when Upstream sync CI passes (do not enable auto-merge manually in the same job — checks are not registered yet).

**Repo settings (auto-open PR):** GitHub → **Settings → Actions → General → Workflow permissions** → **Read and write permissions** + tick **Allow GitHub Actions to create and approve pull requests**. Without this, push still works; open PR from: `https://github.com/dna0120/Freedom/compare/main...auto/upstream-sync`

**If an old bot PR is stuck on `action_required`:** close it and re-run **Upstream automation**, or approve the stale **CI** run once; new PRs use Upstream sync CI instead.

If an AWG patch fails, the PR still records the failure in `upstream/SYNC_PR_BODY.md` and skips the pin bump — maintainer cherry-picks manually.

## Maintainer check (local)

```bash
bash tools/check_upstream.sh
bash tools/sync_upstream_pr.sh   # dry-run: exit 0 = no changes, 3 = would open PR
```

- Exit `0`: every tracked pin matches (or informational-only).
- Exit `2`: at least one pinned source has a newer release.
- Exit `3` from `sync_upstream_pr.sh`: working tree changed.

## Manual cherry-pick (when CI patch fails)

1. Read `upstream/REPORT.md` and vendor diff under `upstream/vendor/bivlked/`.
2. Port fixes into `install_freedom.sh` / `awg_common.sh` / `manage_amneziawg.sh`.
3. Bump `pinned_tag`, `UPSTREAM_AWG_PIN`, `SCRIPT_VERSION`, `FREEDOM_VERSION`, SHA256 pins.
4. Re-run `bash tools/check_upstream.sh` (expect exit 0 for bivlked).

## VPS update (manual; does not merge bivlked on the server)

```bash
sudo bash install_freedom.sh --check-updates
sudo bash install_freedom.sh --update
```

Or menu option **22**. This refreshes Freedom helper scripts (SHA256-verified), upgrades Xray/Hysteria binaries, and **reports** AmneziaWG apt package updates without running `apt upgrade` (DKMS/reboot risk).
