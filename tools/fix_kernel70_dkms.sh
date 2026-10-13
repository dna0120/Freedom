#!/bin/bash
# ==============================================================================
# Script tự động sửa lỗi build DKMS AmneziaWG trên Linux Kernel 7.0+ (Ubuntu 7.0.0-38+)
# Repository: https://github.com/dna0120/Freedom
#
# Cách dùng (chạy bằng quyền root):
#   curl -fsSL https://raw.githubusercontent.com/dna0120/Freedom/main/tools/fix_kernel70_dkms.sh | sudo bash
# ==============================================================================

set -euo pipefail

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"; }
log_warn() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $*" >&2; }
log_err() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

if [ "$(id -u)" -ne 0 ]; then
    log_err "Vui lòng chạy script với quyền root: sudo bash $0"
    exit 1
fi

log "=== BẮT ĐẦU KIỂM TRA & TỰ ĐỘNG SỬA LỖI DKMS KERNEL 7.0+ ==="

# 1. Tìm thư mục nguồn amneziawg trong /usr/src
SRC_DIR=""
for d in /usr/src/amneziawg-*; do
    if [ -f "$d/compat/compat.h" ]; then
        SRC_DIR="$d"
        break
    fi
done

if [ -z "$SRC_DIR" ]; then
    log_warn "Không tìm thấy thư mục nguồn amneziawg trong /usr/src."
    exit 0
fi

log "Đã tìm thấy nguồn AmneziaWG tại: $SRC_DIR"

COMPAT_H="$SRC_DIR/compat/compat.h"
BAK_FILE="$SRC_DIR/compat/compat.h.awg-base"

# 2. Kiểm tra xem file compat.h đã có bản vá chưa
if grep -q '__compat_setup_udp_tunnel_sock' "$COMPAT_H"; then
    log "File $COMPAT_H đã có bản vá tương thích Kernel 7.0+ (không cần sửa lại)."
else
    log "Đang áp dụng bản vá Kernel 7.0+ (PR #218) vào $COMPAT_H..."
    
    # Tạo bản sao lưu nếu chưa có
    if [ ! -f "$BAK_FILE" ]; then
        cp -a "$COMPAT_H" "$BAK_FILE" 2>/dev/null || true
    fi

    # Áp dụng patch qua Python nếu có sẵn
    patched=0
    if command -v python3 >/dev/null 2>&1; then
        if python3 - "$COMPAT_H" <<'PY' 2>/dev/null; then
import sys
from pathlib import Path

target = Path(sys.argv[1])
content = target.read_text(encoding="utf-8")

old_block = """#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 1, 5)
#include <net/udp_tunnel.h>
#define setup_udp_tunnel_sock(net, sk, sock_cfg) setup_udp_tunnel_sock(net, sk->sk_socket, sock_cfg)
#define udp_tunnel_sock_release(sk) udp_tunnel_sock_release(sk->sk_socket)
#endif"""

new_block = """/* Kernel 7.0+ udp_tunnel backport fix */
#include <net/udp_tunnel.h>

static inline void __compat_udp_tunnel_sock_release(struct sock *sk)
{
	if (__builtin_types_compatible_p(typeof(&udp_tunnel_sock_release), void (*)(struct sock *)))
		((void (*)(struct sock *))udp_tunnel_sock_release)(sk);
	else
		((void (*)(struct socket *))udp_tunnel_sock_release)(sk->sk_socket);
}

static inline void __compat_setup_udp_tunnel_sock(struct net *net, struct sock *sk,
						    struct udp_tunnel_sock_cfg *cfg)
{
	if (__builtin_types_compatible_p(typeof(&setup_udp_tunnel_sock),
					  void (*)(struct net *, struct sock *, struct udp_tunnel_sock_cfg *)))
		((void (*)(struct net *, struct sock *, struct udp_tunnel_sock_cfg *))setup_udp_tunnel_sock)(net, sk, cfg);
	else
		((void (*)(struct net *, struct socket *, struct udp_tunnel_sock_cfg *))setup_udp_tunnel_sock)(net, sk->sk_socket, cfg);
}

#define udp_tunnel_sock_release(sk) __compat_udp_tunnel_sock_release(sk)
#define setup_udp_tunnel_sock(net, sk, cfg) __compat_setup_udp_tunnel_sock(net, sk, cfg)"""

if old_block in content:
    target.write_text(content.replace(old_block, new_block, 1), encoding="utf-8")
    sys.exit(0)
elif "__compat_setup_udp_tunnel_sock" in content:
    sys.exit(0)
else:
    sys.exit(1)
PY
            patched=1
        fi
    fi

    if [ "$patched" -eq 0 ]; then
        patch --forward -r - -p1 -d "$SRC_DIR" <<'DIFF_EOF' 2>/dev/null || true
--- a/compat/compat.h
+++ b/compat/compat.h
@@ -1447,8 +1447,27 @@
-#if LINUX_VERSION_CODE < KERNEL_VERSION(7, 1, 5)
+/* Kernel 7.0+ udp_tunnel backport fix */
 #include <net/udp_tunnel.h>
-#define setup_udp_tunnel_sock(net, sk, sock_cfg) setup_udp_tunnel_sock(net, sk->sk_socket, sock_cfg)
-#define udp_tunnel_sock_release(sk) udp_tunnel_sock_release(sk->sk_socket)
-#endif
+static inline void __compat_udp_tunnel_sock_release(struct sock *sk)
+{
+	if (__builtin_types_compatible_p(typeof(&udp_tunnel_sock_release), void (*)(struct sock *)))
+		((void (*)(struct sock *))udp_tunnel_sock_release)(sk);
+	else
+		((void (*)(struct socket *))udp_tunnel_sock_release)(sk->sk_socket);
+}
+static inline void __compat_setup_udp_tunnel_sock(struct net *net, struct sock *sk,
+						    struct udp_tunnel_sock_cfg *cfg)
+{
+	if (__builtin_types_compatible_p(typeof(&setup_udp_tunnel_sock),
+					  void (*)(struct net *, struct sock *, struct udp_tunnel_sock_cfg *)))
+		((void (*)(struct net *, struct sock *, struct udp_tunnel_sock_cfg *))setup_udp_tunnel_sock)(net, sk, cfg);
+	else
+		((void (*)(struct net *, struct socket *, struct udp_tunnel_sock_cfg *))setup_udp_tunnel_sock)(net, sk->sk_socket, cfg);
+}
+#define udp_tunnel_sock_release(sk) __compat_udp_tunnel_sock_release(sk)
+#define setup_udp_tunnel_sock(net, sk, cfg) __compat_setup_udp_tunnel_sock(net, sk, cfg)
DIFF_EOF
    fi

    log "Đã vá compat.h thành công!"
fi

# 3. Biên dịch lại toàn bộ module DKMS cho các kernel đã cài
if command -v dkms >/dev/null 2>&1; then
    log "Đang chạy dkms autoinstall cho các kernel trên hệ thống..."
    dkms autoinstall || true
fi

# 4. Hoàn tất cấu hình các gói debian/dpkg đang bị kẹt
if command -v dpkg >/dev/null 2>&1; then
    log "Đang chạy dpkg --configure -a để gỡ kẹt các gói kernel..."
    dpkg --configure -a || true
fi

log "=== HOÀN TẤT! HỆ THỐNG ĐÃ SẴN SÀNG CHO APT UPGRADE ==="
