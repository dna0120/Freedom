# Upstream sources

Freedom is a fork-plus-extension. **GitHub Actions** keeps observed upstream releases fresh and opens automated PRs. **VPS** updates stay manual (`--update` / menu 22).

| Source | What Freedom uses | How updates land |
|---|---|---|
| [bivlked/amneziawg-installer](https://github.com/bivlked/amneziawg-installer) | AWG install/manage scripts | Daily CI: three-way merge of upstream's `*_en.sh` + Freedom overlay → PR → auto-merge when sync succeeds |
| [angristan/wireguard-install](https://github.com/angristan/wireguard-install) | Menu UX reference | Read-only; no code import |
| [XTLS/Xray-core](https://github.com/XTLS/Xray-core) | Xray binary | `latest_observed` in manifest (CI daily); VPS `--update` installs binary |
| [apernet/hysteria](https://github.com/apernet/hysteria) | Hysteria2 binary | Same as Xray |

Pinned AWG installer tag: [`upstream/manifest.json`](upstream/manifest.json) (`bivlked-awg.pinned_tag`) and `UPSTREAM_AWG_PIN` in `install_freedom.sh`. Current pin: **v5.31.0**.

## Automated GitHub sync (daily)

Workflow: [`.github/workflows/upstream-check.yml`](.github/workflows/upstream-check.yml) (cron `0 6 * * *` UTC + manual dispatch).

1. Runs `tools/check_upstream.sh` → `upstream/REPORT.md`; opens/updates issue **Upstream updates available** when a pinned source is behind.
2. Runs `tools/sync_upstream_pr.sh`:
   - Refreshes `latest_observed` for Xray, Hysteria2, and bivlked in `upstream/manifest.json`.
   - When bivlked has a newer tag: vendor snapshots under `upstream/vendor/bivlked/<tag>/`, **three-way merges** upstream's `awg_common_en.sh` / `manage_amneziawg_en.sh` into Freedom's copies (falling back to taking upstream wholesale), re-applies the Freedom overlay and branding, bumps `UPSTREAM_AWG_PIN` / `SCRIPT_VERSION` / `FREEDOM_VERSION`, recomputes SHA256 pins.
3. Pushes branch `auto/upstream-sync` (always, with `contents: write`).
4. Tries to open/update a PR via `gh` (optional; needs the repo setting below). If PR creation is blocked, the workflow still **succeeds** — use the **compare link** in the job summary to open a PR manually.
5. After opening/updating the PR, Upstream automation **dispatches** [Upstream sync CI](.github/workflows/upstream-pr-ci.yml) via `workflow_dispatch` (events caused by `GITHUB_TOKEN` do not start `pull_request` / `pull_request_target` runs reliably).
6. Upstream sync CI validates the sync branch and **squash-merges** when green. [Upstream auto-merge](.github/workflows/upstream-auto-merge.yml) remains as manual recovery only.

**Repo settings (auto-open PR):** GitHub → **Settings → Actions → General → Workflow permissions** → **Read and write permissions** + tick **Allow GitHub Actions to create and approve pull requests**. Without this, push still works; open PR from: `https://github.com/dna0120/Freedom/compare/main...auto/upstream-sync`

**If an old bot PR is stuck on `action_required`:** close it and re-run **Upstream automation**, or approve the stale **CI** run once; new PRs use Upstream sync CI instead.

If AWG sync fails, the PR still records the failure in `upstream/SYNC_PR_BODY.md` and **skips the pin bump** — fix the overlay, merge once manually, then daily CI resumes.

## Why the AWG helpers track `*_en.sh`

bivlked publishes each helper twice: the Russian original and an official English translation (`awg_common_en.sh`, `manage_amneziawg_en.sh`). Freedom tracks the **English** ones.

That matters more than it sounds. Freedom used to keep its own hand-made English translation of the Russian files, which meant every upstream tag conflicted on nearly every comment and log line — the two translations said the same thing in different words. Conflict resolution then had to guess, and it guessed wrong: the v5.30/v5.31 catch-up silently dropped upstream's `timeout 10` guards on `awg show` while letting two Russian strings through into user-facing output.

Tracking `*_en.sh` removes the translation from the equation. Freedom's entire delta is now the rule table in [`tools/apply_freedom_awg_overlay.py`](tools/apply_freedom_awg_overlay.py):

- branding (author, repository, self-update URLs, `install_freedom.sh` instead of `install_amneziawg_en.sh`)
- `MTU` default **1420** rather than upstream's 1280
- operator-configurable client DNS via `CLIENT_DNS_1` / `CLIENT_DNS_2`, plus `ENABLE_BBR` in the config allowlist

Each rule is an exact string swap that is idempotent when already applied and **fails the sync** when upstream rewords the surrounding code. A red CI run is the point: a customisation that vanishes quietly ships a wrong MTU or the wrong DNS to every client.

The sync may also replace a helper with upstream's copy wholesale, which would erase any edit the overlay does not know about. A drift guard runs first and refuses to sync in that case:

```bash
python3 tools/apply_freedom_awg_overlay.py --drift upstream/vendor/bivlked/<pin>
```

So when a sync fails, the fix is almost always to update the matching rule in that file — **never** to hand-edit the helpers.

## AWG catch-up (when auto sync fails)

```bash
bash tools/manual_awg_merge.sh v5.31.0 v5.32.0   # <current pin> <target tag>
```

It vendors both `*_en.sh` snapshots, three-way merges, re-applies the overlay and branding, then bumps `UPSTREAM_AWG_PIN` / `SCRIPT_VERSION` / `FREEDOM_VERSION` / `pinned_tag` and the SHA256 pins. On conflict it stops and prints the wholesale-copy commands, since upstream's side is the safe resolution.

**Line endings matter.** `.gitattributes` stores `*.sh` as `eol=lf`, and the VPS verifies the SHA256 of the raw GitHub blob. The pin helpers therefore hash the **LF form**, not the local file — do not replace that with a plain `sha256sum`.

## Maintainer check (local)

```bash
bash tools/check_upstream.sh
bash tools/sync_upstream_pr.sh   # dry-run: exit 0 = no changes, 3 = would open PR
```

- Exit `0`: every tracked pin matches (or informational-only).
- Exit `2`: at least one pinned source has a newer release.
- Exit `3` from `sync_upstream_pr.sh`: working tree changed.

## Manual cherry-pick (when the overlay needs work)

1. Read `upstream/REPORT.md` and the vendor diff under `upstream/vendor/bivlked/`.
2. Update the failing rule in `tools/apply_freedom_awg_overlay.py`, then re-run `tools/manual_awg_merge.sh`.
3. Port any `install_freedom.sh` changes by hand — that file is Freedom's own, not a fork.
4. Re-run `bash tools/check_upstream.sh` (expect exit 0 for bivlked).

## VPS update (manual; does not merge bivlked on the server)

```bash
sudo bash install_freedom.sh --check-updates
sudo bash install_freedom.sh --update
```

Or menu option **22**. This refreshes Freedom helper scripts (SHA256-verified), upgrades Xray/Hysteria binaries, and **reports** AmneziaWG apt package updates without running `apt upgrade` (DKMS/reboot risk).
