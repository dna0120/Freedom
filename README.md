# AmneziaWG + Xray Installer

Script cài đặt và quản lý **AmneziaWG** và **Xray (VLESS + REALITY)** trên cùng một VPS, menu kiểu angristan.

## Quick Install (1 lệnh)

Chạy bằng root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/main/install_amneziawg.sh)
```

Không phải root:

```bash
curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/main/install_amneziawg.sh -o awg.sh && sudo bash awg.sh
```

Script tự tải các file phụ (`awg_common.sh`, `manage_amneziawg.sh`, `xray_common.sh`, `manage_xray.sh`) nên chỉ cần đúng một lệnh trên.

## Dùng lại sau khi cài

Chạy lại đúng lệnh trên (hoặc `sudo bash install_amneziawg.sh` nếu còn file) — script phát hiện đã cài và mở thẳng menu quản lý.

### AmneziaWG (1–7)
- Thêm / list / thu hồi client
- Trạng thái, gỡ, cấu hình lại

### Xray (8–14)
- **8)** Cài Xray (VLESS + REALITY Vision + XHTTP, 2 cổng TCP random)
- **9)** Thêm client — hỏi Vision hoặc XHTTP, xuất QR + `vless://` + JSON
- **10–12)** List / thu hồi / trạng thái
- **13–14)** Gỡ Xray (không đụng AWG) / cấu hình lại dest-SNI và cổng

Hoặc:

```bash
sudo ./install_amneziawg.sh --install-xray
sudo ./install_amneziawg.sh --uninstall-xray
```

Xray dùng core chính thức: [XTLS/Xray-core](https://github.com/XTLS/Xray-core) qua [Xray-install](https://github.com/XTLS/Xray-install).

## Tuỳ chọn cài AmneziaWG hữu ích

Trong quá trình cài (interactive), script sẽ hỏi:
- **DNS** cho client (mặc định `1.1.1.1`, `1.0.0.1`)
- **MTU** — tự nhận IP client đang SSH vào VM, probe path MTU tới IP đó (fallback `1.1.1.1`), rồi gợi ý (thường ~1280–1420)
- **BBR** — nếu chưa bật thì hỏi có muốn bật không (mặc định **Y**)

Hoặc truyền sẵn:

```bash
sudo ./install_amneziawg.sh --dns=8.8.8.8,8.8.4.4 --mtu=1420
```
