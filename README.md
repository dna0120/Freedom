# Freedom

Installer and management menu for **AmneziaWG**, **Xray (VLESS + REALITY / CDN)** and **Hysteria2** on one VPS. angristan-style UX.

English first. [Tiếng Việt](#tiếng-việt) below.

**Work with me** — I take paid jobs for DPI diagnosis, deploy, and keep-alive (not “install the NordVPN app”).

- Email: [dat.tranthanh0919@gmail.com](mailto:dat.tranthanh0919@gmail.com)
- Upwork: **Tran T.** — *Network Engineer | VPN Obfuscation & Infra Specialist*
- Case study: [WireGuard died in Myanmar; AmneziaWG did not](docs/myanmar.md)

This repo is the installer. Live per-country tuning, monitoring, and incident response stay private / paid.

## Requirements

- Ubuntu 24.04 / 25.10 / 26.04 or Debian 12 / 13
- KVM / bare-metal VPS (AmneziaWG needs a kernel module)
- root

## Quick install

**Pinned release (recommended):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/v1.3.1/install_freedom.sh)
```

**Bleeding edge (`main`, can change at any time):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/main/install_freedom.sh)
```

If you are not root:

```bash
curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/v1.3.0/install_freedom.sh -o freedom.sh && sudo bash freedom.sh
```

First run on a clean machine asks what to install:

```
1) AmneziaWG
2) Xray — VLESS+REALITY (Vision/XHTTP/gRPC, optional CDN)
3) Hysteria2
4) AmneziaWG + Xray
5) All three
```

Options 2 or 3 skip AmneziaWG entirely. `--yes` / `--force` skip the prompt and default to AmneziaWG.

## After install

Run the same install command again — it opens a **dynamic management menu** (only stacks you installed; **Update is always last**, not hardcoded as item 22).

### AmneziaWG

- Add / list / revoke clients
- Status, uninstall, reconfigure

### Xray

- Vision + XHTTP + gRPC (REALITY), optional CDN/TLS front (Cloudflare)
- Reconfigure from the menu: CDN on/off, change domain (or `--xray-domain=` / `--xray-cdn-off`)
- REALITY SNI scan; nearby SNI discovery ([Reality-SNI-Finder](https://github.com/ShatakVPN/Reality-SNI-Finder))
- CLI: `sudo bash /root/xray/manage_xray.sh check-sni|discover-sni|add-sni`

### Hysteria2

- QUIC/UDP, masquerade, Salamander OBFS
- `hysteria2://` + YAML + QR

## Useful CLI flags

| Flag | Meaning |
|---|---|
| `--lang=en\|vi` | Menu language |
| `--diagnostic` | Diagnostic report |
| `--check-updates` / `--update` | Check / apply updates |
| `--install-xray` / `--install-hysteria` | Install one stack |
| `--xray-domain=FQDN` / `--hy2-domain=FQDN` | TLS/ACME domain |

```bash
sudo ./install_freedom.sh --install-xray --xray-domain=vpn.example.com
sudo ./install_freedom.sh --check-updates
sudo ./install_freedom.sh --update
```

## Updates

- Helper scripts are re-downloaded with a **mandatory SHA256 pin**; mismatch aborts
- Xray / Hysteria2 binaries upgrade; client UUIDs and passwords are kept
- Includes fixes for: REALITY dest post-quantum, Hysteria cert missing SAN, Cloudflare gRPC CDN ports, certbot deploy-hook
- `FREEDOM_VERSION` = Freedom version; `SCRIPT_VERSION` follows the bivlked AmneziaWG installer

## Layout on the server

| Path | Contents |
|---|---|
| `/root/awg` | AmneziaWG state, clients, backups |
| `/root/xray` | Xray clients, certs, SNI pool |
| `/root/hysteria` | Hysteria2 clients, certs |
| `/etc/amnezia/amneziawg/` | AWG server config |
| `/usr/local/etc/xray/config.json` | Xray config |
| `/etc/hysteria/config.yaml` | Hysteria2 config |

## Backup & restore (AmneziaWG)

```bash
sudo bash /root/awg/manage_amneziawg.sh backup
sudo bash /root/awg/manage_amneziawg.sh restore /root/awg/backups/awg_backup_*.tar.gz
```

Xray / Hysteria: back up `/root/xray` and `/root/hysteria` (clients + `*setup_cfg.init`).

## Security

- Downloaded helpers are **SHA256-pinned**; mismatch stops install/update
- Xray / Hysteria default to **blocking egress to private IPs / localhost / 169.254.169.254** (no accidental open proxy). Set `XRAY_ALLOW_PRIVATE=1` or `HY2_ALLOW_PRIVATE=1` in the setup file if you need LAN access through the VPN
- Let's Encrypt: hook at `/etc/letsencrypt/renewal-hooks/deploy/freedom.sh` reloads Xray/Hysteria after renew

## Which stack for which failure

| Stack | Transport | Typical use |
|---|---|---|
| AmneziaWG | UDP obfuscated WireGuard | Fast; moderate DPI (handshake classified, UDP still open) |
| VLESS REALITY Vision/XHTTP/gRPC | TCP + camouflage | Stealth, active probes |
| CDN XHTTP/gRPC TLS | Domain + Let's Encrypt behind Cloudflare | Hide VPS IP |
| Hysteria2 | QUIC/UDP + OBFS | Throughput, mobile; UDP fully blocked cases |

Worked example: [Myanmar — UDP probe succeeded, WireGuard handshake did not](docs/myanmar.md).

Upstream: [UPSTREAM.md](UPSTREAM.md). License: [LICENSE](LICENSE), [NOTICE](NOTICE).

Maintainer: `bash tools/verify_sha_pins.sh`, `bash tools/check_upstream.sh`, `bash tools/sync_upstream_pr.sh`. GitHub Actions syncs upstream daily (see [UPSTREAM.md](UPSTREAM.md)).

---

# Tiếng Việt

Script cài đặt và quản lý **AmneziaWG**, **Xray (VLESS + REALITY / CDN)** và **Hysteria2** trên cùng một VPS, menu kiểu angristan.

**Thuê triển khai / chẩn đoán DPI:** [dat.tranthanh0919@gmail.com](mailto:dat.tranthanh0919@gmail.com) · Upwork **Tran T.** · [case Myanmar](docs/myanmar.md)

Installer miễn phí. Bộ tham số đang sống theo từng quốc gia, giám sát, và xử lý khi DPI đổi — đó là việc trả phí.

## Yêu cầu

- Ubuntu 24.04 / 25.10 / 26.04 hoặc Debian 12 / 13
- VPS KVM/bare-metal (AmneziaWG cần kernel module)
- Quyền root

## Quick Install

**Khuyến nghị (release ghim):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/v1.3.1/install_freedom.sh)
```

**Bleeding edge (`main`, có thể thay đổi bất cứ lúc nào):**

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/main/install_freedom.sh)
```

Không phải root:

```bash
curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/v1.3.0/install_freedom.sh -o freedom.sh && sudo bash freedom.sh
```

Lần chạy đầu trên máy sạch, script hỏi muốn cài gì:

```
1) AmneziaWG
2) Xray — VLESS+REALITY (Vision/XHTTP/gRPC, tuỳ chọn CDN)
3) Hysteria2
4) AmneziaWG + Xray
5) Cả ba
```

Chọn 2 hoặc 3 thì bỏ qua hoàn toàn phần cài AmneziaWG. Dùng `--yes` hoặc `--force` thì không hỏi và mặc định AmneziaWG.

## Dùng lại sau khi cài

Chạy lại cùng lệnh cài — mở **menu quản lý động**: chỉ hiện stack đã cài; **cập nhật luôn là mục cuối** (không cố định số 22).

### AmneziaWG
- Thêm / list / thu hồi client
- Trạng thái, gỡ, cấu hình lại

### Xray
- Vision + XHTTP + gRPC (REALITY), tuỳ chọn CDN/TLS front (Cloudflare)
- **Cấu hình lại Xray** trong menu: bật/tắt CDN, đổi domain (hoặc `--xray-domain=` / `--xray-cdn-off`)
- Quét SNI REALITY; tìm SNI gần VPS ([Reality-SNI-Finder](https://github.com/ShatakVPN/Reality-SNI-Finder))
- CLI: `sudo bash /root/xray/manage_xray.sh check-sni|discover-sni|add-sni`

### Hysteria2
- QUIC/UDP, masquerade, Salamander OBFS
- `hysteria2://` + YAML + QR

## Cờ CLI hữu ích

| Cờ | Mô tả |
|---|---|
| `--lang=en\|vi` | Ngôn ngữ menu |
| `--diagnostic` | Báo cáo chẩn đoán |
| `--check-updates` / `--update` | Kiểm tra / áp dụng cập nhật |
| `--install-xray` / `--install-hysteria` | Cài từng stack |
| `--xray-domain=FQDN` / `--hy2-domain=FQDN` | Domain TLS/ACME |

```bash
sudo ./install_freedom.sh --install-xray --xray-domain=vpn.example.com
sudo ./install_freedom.sh --check-updates
sudo ./install_freedom.sh --update
```

## Cập nhật

- Tải lại helper scripts (**SHA256 bắt buộc**), nâng binary Xray/Hysteria2, giữ UUID/mật khẩu client
- Tự vá: REALITY dest post-quantum, cert Hysteria thiếu SAN, port CDN gRPC Cloudflare, certbot deploy-hook
- `FREEDOM_VERSION` = version Freedom; `SCRIPT_VERSION` bám bivlked AmneziaWG installer

## Bố cục trên server

| Đường dẫn | Nội dung |
|---|---|
| `/root/awg` | State AmneziaWG, client, backup |
| `/root/xray` | Client Xray, cert, pool SNI |
| `/root/hysteria` | Client Hysteria2, cert |
| `/etc/amnezia/amneziawg/` | Config server AWG |
| `/usr/local/etc/xray/config.json` | Config Xray |
| `/etc/hysteria/config.yaml` | Config Hysteria2 |

## Backup & restore (AmneziaWG)

```bash
sudo bash /root/awg/manage_amneziawg.sh backup
sudo bash /root/awg/manage_amneziawg.sh restore /root/awg/backups/awg_backup_*.tar.gz
```

Xray/Hysteria: sao lưu thư mục `/root/xray` và `/root/hysteria` (client + `*setup_cfg.init`).

## Bảo mật

- Helper scripts tải về được **pin SHA256**; mismatch → cài/update dừng
- Xray/Hysteria mặc định **chặn egress tới private IP / localhost / 169.254.169.254** (tránh open proxy). Đặt `XRAY_ALLOW_PRIVATE=1` hoặc `HY2_ALLOW_PRIVATE=1` trong file setup nếu cần truy cập LAN qua VPN
- Cert Let's Encrypt: hook tại `/etc/letsencrypt/renewal-hooks/deploy/freedom.sh` reload Xray/Hysteria sau renew

## Stack chống kiểm duyệt

| Stack | Transport | Khi nào dùng |
|---|---|---|
| AmneziaWG | UDP obfuscated WireGuard | Nhanh, DPI vừa |
| VLESS REALITY Vision/XHTTP/gRPC | TCP + camouflage | Stealth, active probe |
| CDN XHTTP/gRPC TLS | Domain + LE sau Cloudflare | Ẩn IP VPS |
| Hysteria2 | QUIC/UDP + OBFS | Tốc độ cao, mobile |

Upstream: [UPSTREAM.md](UPSTREAM.md). License: [LICENSE](LICENSE), [NOTICE](NOTICE).

Maintainer: `bash tools/verify_sha_pins.sh`, `bash tools/check_upstream.sh`, `bash tools/sync_upstream_pr.sh`. GitHub Actions syncs upstream daily (see [UPSTREAM.md](UPSTREAM.md)).
