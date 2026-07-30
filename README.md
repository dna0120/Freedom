# AmneziaWG Installer

Script cài đặt và quản lý AmneziaWG với menu tiện dụng (add/list/revoke client) theo kiểu dễ dùng như angristan.

## Quick Install

```bash
curl -O https://raw.githubusercontent.com/dna0120/Freedom/main/install_amneziawg.sh
chmod +x install_amneziawg.sh
sudo ./install_amneziawg.sh
```

## Dùng lại sau khi cài

```bash
sudo bash install_amneziawg.sh
```

Menu sẽ hiện các lựa chọn:
- Add a new client
- List all clients
- Revoke existing client
- Show server status
- Uninstall AmneziaWG

## Tuỳ chọn cài đặt hữu ích

Trong quá trình cài (interactive), script sẽ hỏi:
- **DNS** cho client (mặc định `1.1.1.1`, `1.0.0.1`)
- **MTU** — tự nhận IP client đang SSH vào VM, probe path MTU tới IP đó (fallback `1.1.1.1`), rồi gợi ý (thường ~1280–1420)
- **BBR** — nếu chưa bật thì hỏi có muốn bật không (mặc định **Y**)

Hoặc truyền sẵn:

```bash
sudo ./install_amneziawg.sh --dns=8.8.8.8,8.8.4.4 --mtu=1420
```
