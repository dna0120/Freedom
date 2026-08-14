# Freedom Installer (AmneziaWG + Xray + Hysteria2)

Script cài đặt và quản lý **AmneziaWG**, **Xray (VLESS + REALITY / CDN)** và **Hysteria2** trên cùng một VPS, menu kiểu angristan.

## Quick Install (1 lệnh)

Chạy bằng root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/main/install_freedom.sh)
```

Không phải root:

```bash
curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/main/install_freedom.sh -o freedom.sh && sudo bash freedom.sh
```

Script tự tải các file phụ nên chỉ cần đúng một lệnh trên.

Lần chạy đầu trên máy sạch, script hỏi ngay muốn cài gì:

```
1) AmneziaWG
2) Xray — VLESS+REALITY (Vision/XHTTP/gRPC, tuỳ chọn CDN)
3) Hysteria2
4) AmneziaWG + Xray
5) Cả ba
```

Chọn 2 hoặc 3 thì bỏ qua hoàn toàn phần cài AmneziaWG. Lựa chọn được ghi nhớ nên nếu AmneziaWG cần reboot giữa chừng, chạy lại lệnh trên sẽ cài tiếp đúng các stack đã chọn. Dùng `--yes` hoặc `--force` thì không hỏi và mặc định AmneziaWG như cũ.

## Dùng lại sau khi cài

Chạy lại đúng lệnh trên (hoặc `sudo bash install_freedom.sh`) — mở menu quản lý.

Menu được đánh số động: chỉ hiện thao tác của stack đã cài; stack còn thiếu chỉ có một mục **Cài thêm**.

### AmneziaWG
- Thêm / list / thu hồi client
- Trạng thái, gỡ, cấu hình lại

### Xray
- Cài Xray: Vision + XHTTP + **gRPC** (REALITY), tùy chọn **CDN/TLS front**
- Thêm client — Vision / XHTTP / gRPC / CDN-XHTTP / CDN-gRPC, xuất QR + `vless://` + JSON
- List / thu hồi / trạng thái / gỡ / cấu hình lại
- **Quét SNI REALITY khả dụng** trực tiếp từ VPS; tự loại host dùng `X25519MLKEM768`
- CLI: `sudo bash /root/xray/manage_xray.sh check-sni`
- Bổ sung và xác minh SNI riêng: `sudo bash /root/xray/manage_xray.sh add-sni example.com`

### Hysteria2
- Cài Hysteria2 (QUIC/UDP, masquerade, Salamander OBFS mặc định bật)
- Thêm / list / thu hồi / trạng thái client (`hysteria2://` + YAML + QR)
- Gỡ / cấu hình lại

Hoặc:

```bash
sudo ./install_freedom.sh --install-xray
sudo ./install_freedom.sh --install-xray --xray-domain=vpn.example.com
sudo ./install_freedom.sh --install-hysteria
sudo ./install_freedom.sh --install-hysteria --hy2-domain=hy2.example.com
sudo ./install_freedom.sh --uninstall-xray
sudo ./install_freedom.sh --uninstall-hysteria
sudo ./install_freedom.sh --check-updates
sudo ./install_freedom.sh --update
```

### Cập nhật

- **`--check-updates`**: báo version script Freedom trên GitHub, pin bivlked vs latest, Xray/Hysteria2 local vs GitHub, và `apt-cache policy` cho `amneziawg-dkms` / `amneziawg-tools` (không tự `apt upgrade`).
- **`--update` / mục cập nhật trong menu**: tải lại helper scripts (SHA256), nâng cấp binary Xray và Hysteria2, **giữ nguyên client profile**. Không merge tự động code AmneziaWG từ bivlked — xem [UPSTREAM.md](UPSTREAM.md).

Maintainer: `bash tools/check_upstream.sh` (exit 2 = có bản upstream mới).

## Stack chống kiểm duyệt

| Stack | Transport | Khi nào dùng |
|---|---|---|
| AmneziaWG | UDP obfuscated WireGuard | Nhanh, dễ, DPI vừa |
| VLESS REALITY Vision | TCP + TLS camouflage | Stealth tối đa, active probe |
| VLESS REALITY XHTTP | HTTP-like request/response | Khi TCP tunnel bị bắt hành vi |
| VLESS REALITY gRPC | HTTP/2 gRPC | Giống traffic gRPC hợp lệ |
| CDN XHTTP/gRPC TLS | Domain + LE/self-signed sau Cloudflare | Ẩn IP VPS sau CDN |
| Hysteria2 | QUIC/UDP + masquerade + OBFS | Tốc độ cao, mobile/lossy |

Xray core: [XTLS/Xray-core](https://github.com/XTLS/Xray-core). Hysteria2: [apernet/hysteria](https://github.com/apernet/hysteria).

## Tuỳ chọn cài AmneziaWG hữu ích

Trong quá trình cài (interactive), script sẽ hỏi:
- **DNS** cho client (mặc định `1.1.1.1`, `1.0.0.1`)
- **MTU** — tự nhận IP client đang SSH vào VM, probe path MTU tới IP đó
- **BBR** — nếu chưa bật thì hỏi có muốn bật không (mặc định **Y**)

```bash
sudo ./install_freedom.sh --dns=8.8.8.8,8.8.4.4 --mtu=1420
```
