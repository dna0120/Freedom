# Freedom Installer (AmneziaWG + Xray + Hysteria2)

Script cài đặt và quản lý **AmneziaWG**, **Xray (VLESS + REALITY / CDN)** và **Hysteria2** trên cùng một VPS, menu kiểu angristan.

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
