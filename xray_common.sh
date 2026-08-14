#!/bin/bash

# ==============================================================================
# Shared function library for Xray (VLESS + REALITY Vision / XHTTP)
# Author: @dna0120
# Version: 5.21.2
# Date: 2026-08-14
# Repository: https://github.com/dna0120/Freedom
# ==============================================================================

XRAY_DIR="${XRAY_DIR:-/root/xray}"
XRAY_CONFIG_FILE="${XRAY_CONFIG_FILE:-$XRAY_DIR/xraysetup_cfg.init}"
XRAY_CLIENTS_DIR="${XRAY_CLIENTS_DIR:-$XRAY_DIR/clients}"
XRAY_CONF_JSON="${XRAY_CONF_JSON:-/usr/local/etc/xray/config.json}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
XRAY_COMMON_VERSION="5.21.2"

_XRAY_TEMP_FILES=()
_XRAY_TEMP_REGISTRY="${XRAY_DIR}/.xray_temp_registry.$$"

_xray_cleanup() {
    local f
    for f in "${_XRAY_TEMP_FILES[@]}"; do
        [[ -f "$f" ]] && rm -f "$f"
    done
    if [[ -n "${_XRAY_TEMP_REGISTRY:-}" && -f "$_XRAY_TEMP_REGISTRY" && ! -L "$_XRAY_TEMP_REGISTRY" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && rm -f "$f"
        done < "$_XRAY_TEMP_REGISTRY"
        rm -f "$_XRAY_TEMP_REGISTRY"
    fi
}

xray_mktemp() {
    local dir="${1:-}" f
    if [[ -n "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null
        f=$(mktemp -p "$dir") || return 1
    else
        f=$(mktemp) || return 1
    fi
    _XRAY_TEMP_FILES+=("$f")
    [[ -n "${_XRAY_TEMP_REGISTRY:-}" ]] && printf '%s\n' "$f" >> "$_XRAY_TEMP_REGISTRY" 2>/dev/null
    echo "$f"
}

if ! declare -f log >/dev/null 2>&1; then
    log()       { echo "[INFO] $1"; }
    log_warn()  { echo "[WARN] $1" >&2; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_debug() { echo "[DEBUG] $1"; }
fi

xray_is_installed() {
    [[ -x "$XRAY_BIN" && -f "$XRAY_CONF_JSON" && -f "$XRAY_CONFIG_FILE" ]]
}

xray_ensure_dirs() {
    mkdir -p "$XRAY_DIR" "$XRAY_CLIENTS_DIR" "$(dirname "$XRAY_CONF_JSON")" || return 1
    chmod 700 "$XRAY_DIR" "$XRAY_CLIENTS_DIR" 2>/dev/null || true
}

xray_valid_name() {
    local n="$1"
    [[ "$n" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    (( ${#n} >= 1 && ${#n} <= 15 ))
}

xray_urlencode() {
    local s="$1" out="" i c hex
    for (( i=0; i<${#s}; i++ )); do
        c="${s:i:1}"
        case "$c" in
            [a-zA-Z0-9._~-]) out+="$c" ;;
            *) printf -v hex '%%%02X' "'$c"; out+="$hex" ;;
        esac
    done
    printf '%s' "$out"
}

xray_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

xray_random_tcp_port() {
    echo $(( (RANDOM % 16384) + 49152 ))
}

xray_tcp_port_free() {
    local port="$1"
    [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] || return 1
    (( port <= 65535 )) || return 1
    if ss -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
        return 1
    fi
    return 0
}

xray_pick_free_tcp_port() {
    local avoid="${1:-}" p i
    for i in $(seq 1 40); do
        p="$(xray_random_tcp_port)"
        [[ "$p" == "$avoid" ]] && continue
        if xray_tcp_port_free "$p"; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

xray_get_public_ip() {
    local ip svc
    if [[ -n "${XRAY_ENDPOINT:-}" ]]; then
        printf '%s\n' "$XRAY_ENDPOINT"
        return 0
    fi
    for svc in \
        https://api.ipify.org \
        https://checkip.amazonaws.com \
        https://icanhazip.com \
        https://ifconfig.io \
        https://ipinfo.io/ip
    do
        ip=$(curl -4 -sf --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            printf '%s\n' "$ip"
            return 0
        fi
    done
    return 1
}

xray_generate_short_id() {
    openssl rand -hex 8 2>/dev/null || xxd -l 8 -p /dev/urandom 2>/dev/null || \
        printf '%08x%08x' "$RANDOM$RANDOM" "$RANDOM$RANDOM"
}

xray_generate_keys() {
    command -v "$XRAY_BIN" >/dev/null 2>&1 || { log_error "xray binary not found"; return 1; }
    local out priv pub
    out="$("$XRAY_BIN" x25519 2>/dev/null)" || return 1
    priv="$(printf '%s\n' "$out" | awk -F': *' '/Private/{print $2; exit}' | tr -d '[:space:]')"
    pub="$(printf '%s\n' "$out" | awk -F': *' '/Password:|Public/{print $2; exit}' | tr -d '[:space:]')"
    [[ -n "$priv" && -n "$pub" ]] || return 1
    XRAY_PRIVATE_KEY="$priv"
    XRAY_PUBLIC_KEY="$pub"
    XRAY_SHORT_ID="$(xray_generate_short_id)"
    export XRAY_PRIVATE_KEY XRAY_PUBLIC_KEY XRAY_SHORT_ID
}

xray_generate_uuid() {
    if command -v "$XRAY_BIN" >/dev/null 2>&1; then
        "$XRAY_BIN" uuid 2>/dev/null | tr -d '[:space:]'
        return 0
    fi
    cat /proc/sys/kernel/random/uuid 2>/dev/null
}

xray_generate_path() {
    local hex
    hex="$(openssl rand -hex 6 2>/dev/null || printf '%012x' "$RANDOM$RANDOM")"
    printf '/x%s' "$hex"
}

# Candidate dests: TLS1.3+H2 sites that are NOT Cloudflare (REALITY warning).
xray_dest_candidates() {
    cat <<'EOF'
www.microsoft.com
www.apple.com
www.samsung.com
www.sony.com
www.nvidia.com
www.intel.com
download.microsoft.com
update.microsoft.com
EOF
}

xray_tls_ping_ok() {
    local host="$1" out
    command -v "$XRAY_BIN" >/dev/null 2>&1 || return 1
    out="$("$XRAY_BIN" tls ping "$host" 2>/dev/null)" || return 1
    printf '%s\n' "$out" | grep -qiE 'tls 1\.3|tls1\.3|h2|http/2' || return 1
    return 0
}

xray_pick_dest() {
    local host cand
    if [[ -n "${XRAY_DEST:-}" ]]; then
        printf '%s\n' "${XRAY_DEST%%:*}"
        return 0
    fi
    while IFS= read -r cand; do
        [[ -z "$cand" || "$cand" =~ ^# ]] && continue
        if xray_tls_ping_ok "$cand"; then
            printf '%s\n' "$cand"
            return 0
        fi
        log_warn "REALITY dest candidate failed tls ping: $cand"
    done < <(xray_dest_candidates)
    printf '%s\n' "www.microsoft.com"
}

xray_save_config() {
    xray_ensure_dirs || return 1
    local tmp
    tmp="$(xray_mktemp "$XRAY_DIR")" || return 1
    cat > "$tmp" <<EOF
export XRAY_VISION_PORT=${XRAY_VISION_PORT}
export XRAY_XHTTP_PORT=${XRAY_XHTTP_PORT}
export XRAY_DEST='${XRAY_DEST}'
export XRAY_SNI='${XRAY_SNI}'
export XRAY_PRIVATE_KEY='${XRAY_PRIVATE_KEY}'
export XRAY_PUBLIC_KEY='${XRAY_PUBLIC_KEY}'
export XRAY_SHORT_ID='${XRAY_SHORT_ID}'
export XRAY_XHTTP_PATH='${XRAY_XHTTP_PATH}'
export XRAY_ENDPOINT='${XRAY_ENDPOINT:-}'
EOF
    chmod 600 "$tmp"
    mv -f "$tmp" "$XRAY_CONFIG_FILE"
}

xray_load_config() {
    [[ -f "$XRAY_CONFIG_FILE" ]] || return 1
    # shellcheck source=/dev/null
    source "$XRAY_CONFIG_FILE"
    : "${XRAY_VISION_PORT:=}" "${XRAY_XHTTP_PORT:=}" "${XRAY_DEST:=}" "${XRAY_SNI:=}"
    : "${XRAY_PRIVATE_KEY:=}" "${XRAY_PUBLIC_KEY:=}" "${XRAY_SHORT_ID:=}" "${XRAY_XHTTP_PATH:=}"
    : "${XRAY_ENDPOINT:=}"
}

xray_clients_json_array() {
    local proto="$1" f name uuid first=1
    printf '['
    shopt -s nullglob
    for f in "$XRAY_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        [[ "${XRAY_CLIENT_PROTO:-}" == "$proto" ]] || continue
        uuid="${XRAY_CLIENT_UUID:-}"
        [[ -n "$uuid" ]] || continue
        if [[ "$first" -eq 1 ]]; then first=0; else printf ','; fi
        if [[ "$proto" == "vision" ]]; then
            printf '{"id":"%s","email":"%s","flow":"xtls-rprx-vision"}' \
                "$(xray_json_escape "$uuid")" "$(xray_json_escape "$name")"
        else
            printf '{"id":"%s","email":"%s"}' \
                "$(xray_json_escape "$uuid")" "$(xray_json_escape "$name")"
        fi
    done
    shopt -u nullglob
    printf ']'
}

xray_render_server_config() {
    xray_ensure_dirs || return 1
    local vision_clients xhttp_clients dest sni tmp
    dest="${XRAY_DEST}"
    [[ "$dest" == *:* ]] || dest="${dest}:443"
    sni="${XRAY_SNI:-${XRAY_DEST%%:*}}"
    vision_clients="$(xray_clients_json_array vision)"
    xhttp_clients="$(xray_clients_json_array xhttp)"
    tmp="$(xray_mktemp "$(dirname "$XRAY_CONF_JSON")")" || return 1
    cat > "$tmp" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-vision",
      "listen": "0.0.0.0",
      "port": ${XRAY_VISION_PORT},
      "protocol": "vless",
      "settings": {
        "clients": ${vision_clients},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "$(xray_json_escape "$dest")",
          "xver": 0,
          "serverNames": ["$(xray_json_escape "$sni")"],
          "privateKey": "$(xray_json_escape "$XRAY_PRIVATE_KEY")",
          "shortIds": ["$(xray_json_escape "$XRAY_SHORT_ID")"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "tag": "vless-xhttp",
      "listen": "0.0.0.0",
      "port": ${XRAY_XHTTP_PORT},
      "protocol": "vless",
      "settings": {
        "clients": ${xhttp_clients},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "$(xray_json_escape "$dest")",
          "xver": 0,
          "serverNames": ["$(xray_json_escape "$sni")"],
          "privateKey": "$(xray_json_escape "$XRAY_PRIVATE_KEY")",
          "shortIds": ["$(xray_json_escape "$XRAY_SHORT_ID")"]
        },
        "xhttpSettings": {
          "path": "$(xray_json_escape "${XRAY_XHTTP_PATH}")"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF
    chmod 600 "$tmp"
    if ! "$XRAY_BIN" run -test -c "$tmp" >/dev/null 2>&1; then
        log_error "xray config test failed"
        "$XRAY_BIN" run -test -c "$tmp" >&2 || true
        rm -f "$tmp"
        return 1
    fi
    mv -f "$tmp" "$XRAY_CONF_JSON"
    chmod 600 "$XRAY_CONF_JSON"
}

xray_apply_config() {
    xray_render_server_config || return 1
    if systemctl list-unit-files xray.service >/dev/null 2>&1; then
        if systemctl is-active --quiet xray; then
            systemctl reload xray 2>/dev/null || systemctl restart xray || return 1
        else
            systemctl enable --now xray || return 1
        fi
    fi
    return 0
}

xray_vless_link() {
    local proto="$1" uuid="$2" name="$3"
    local host port sni sid pbk path enc_name
    host="$(xray_get_public_ip 2>/dev/null || true)"
    [[ -n "$host" ]] || host="${XRAY_ENDPOINT:-127.0.0.1}"
    sni="${XRAY_SNI}"
    sid="${XRAY_SHORT_ID}"
    pbk="${XRAY_PUBLIC_KEY}"
    enc_name="$(xray_urlencode "$name")"
    if [[ "$proto" == "vision" ]]; then
        port="${XRAY_VISION_PORT}"
        printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&spx=%%2F#%s\n' \
            "$uuid" "$host" "$port" "$(xray_urlencode "$sni")" "$pbk" "$sid" "$enc_name"
    else
        port="${XRAY_XHTTP_PORT}"
        path="$(xray_urlencode "${XRAY_XHTTP_PATH}")"
        printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=xhttp&path=%s#%s\n' \
            "$uuid" "$host" "$port" "$(xray_urlencode "$sni")" "$pbk" "$sid" "$path" "$enc_name"
    fi
}

xray_write_client_files() {
    local name="$1" proto="$2" uuid="$3"
    local host port sni link tmp json_file meta_file
    host="$(xray_get_public_ip 2>/dev/null || true)"
    [[ -n "$host" ]] || host="${XRAY_ENDPOINT:-127.0.0.1}"
    sni="${XRAY_SNI}"
    if [[ "$proto" == "vision" ]]; then port="${XRAY_VISION_PORT}"; else port="${XRAY_XHTTP_PORT}"; fi
    link="$(xray_vless_link "$proto" "$uuid" "$name")"
    json_file="$XRAY_CLIENTS_DIR/${name}.json"
    meta_file="$XRAY_CLIENTS_DIR/${name}.meta"
    tmp="$(xray_mktemp "$XRAY_CLIENTS_DIR")" || return 1
    if [[ "$proto" == "vision" ]]; then
        cat > "$tmp" <<EOF
{
  "remarks": "$(xray_json_escape "$name")",
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "$(xray_json_escape "$host")",
      "port": ${port},
      "users": [{
        "id": "$(xray_json_escape "$uuid")",
        "encryption": "none",
        "flow": "xtls-rprx-vision"
      }]
    }]
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
      "serverName": "$(xray_json_escape "$sni")",
      "fingerprint": "chrome",
      "password": "$(xray_json_escape "$XRAY_PUBLIC_KEY")",
      "shortId": "$(xray_json_escape "$XRAY_SHORT_ID")",
      "spiderX": "/"
    }
  }
}
EOF
    else
        cat > "$tmp" <<EOF
{
  "remarks": "$(xray_json_escape "$name")",
  "protocol": "vless",
  "settings": {
    "vnext": [{
      "address": "$(xray_json_escape "$host")",
      "port": ${port},
      "users": [{
        "id": "$(xray_json_escape "$uuid")",
        "encryption": "none"
      }]
    }]
  },
  "streamSettings": {
    "network": "xhttp",
    "security": "reality",
    "realitySettings": {
      "serverName": "$(xray_json_escape "$sni")",
      "fingerprint": "chrome",
      "password": "$(xray_json_escape "$XRAY_PUBLIC_KEY")",
      "shortId": "$(xray_json_escape "$XRAY_SHORT_ID")",
      "spiderX": "/"
    },
    "xhttpSettings": {
      "path": "$(xray_json_escape "${XRAY_XHTTP_PATH}")"
    }
  }
}
EOF
    fi
    chmod 600 "$tmp"
    mv -f "$tmp" "$json_file"
    printf 'XRAY_CLIENT_NAME=%s\nXRAY_CLIENT_PROTO=%s\nXRAY_CLIENT_UUID=%s\n' \
        "$name" "$proto" "$uuid" > "$meta_file"
    chmod 600 "$meta_file"
    printf '%s\n' "$link" > "$XRAY_CLIENTS_DIR/${name}.url"
    chmod 600 "$XRAY_CLIENTS_DIR/${name}.url"
    printf '%s\n' "$link"
}

xray_client_exists() {
    [[ -f "$XRAY_CLIENTS_DIR/${1}.meta" ]]
}

xray_add_client() {
    local name="$1" proto="$2" uuid
    xray_valid_name "$name" || { log_error "Invalid client name"; return 1; }
    case "$proto" in
        vision|xhttp) ;;
        *) log_error "Protocol must be vision or xhttp"; return 1 ;;
    esac
    xray_client_exists "$name" && { log_error "Client '$name' already exists"; return 1; }
    xray_load_config || { log_error "Xray is not configured"; return 1; }
    uuid="$(xray_generate_uuid)"
    [[ -n "$uuid" ]] || { log_error "UUID generation failed"; return 1; }
    xray_write_client_files "$name" "$proto" "$uuid" >/dev/null || return 1
    xray_apply_config || return 1
    xray_vless_link "$proto" "$uuid" "$name"
}

xray_remove_client() {
    local name="$1"
    xray_client_exists "$name" || { log_error "Client '$name' not found"; return 1; }
    rm -f "$XRAY_CLIENTS_DIR/${name}.meta" \
          "$XRAY_CLIENTS_DIR/${name}.json" \
          "$XRAY_CLIENTS_DIR/${name}.url" \
          "$XRAY_CLIENTS_DIR/${name}.png"
    xray_load_config || return 1
    xray_apply_config
}

xray_list_clients() {
    local f name proto uuid
    shopt -s nullglob
    for f in "$XRAY_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        proto="${XRAY_CLIENT_PROTO:-?}"
        uuid="${XRAY_CLIENT_UUID:-?}"
        printf '%s\t%s\t%s\n' "$name" "$proto" "$uuid"
    done
    shopt -u nullglob
}

xray_maybe_open_ufw() {
    command -v ufw >/dev/null 2>&1 || return 0
    ufw status 2>/dev/null | grep -qi 'Status: active' || return 0
    ufw allow "${XRAY_VISION_PORT}/tcp" comment "Xray VLESS REALITY Vision" >/dev/null 2>&1 || true
    ufw allow "${XRAY_XHTTP_PORT}/tcp" comment "Xray VLESS REALITY XHTTP" >/dev/null 2>&1 || true
}

xray_maybe_close_ufw() {
    command -v ufw >/dev/null 2>&1 || return 0
    [[ -n "${XRAY_VISION_PORT:-}" ]] && ufw delete allow "${XRAY_VISION_PORT}/tcp" >/dev/null 2>&1 || true
    [[ -n "${XRAY_XHTTP_PORT:-}" ]] && ufw delete allow "${XRAY_XHTTP_PORT}/tcp" >/dev/null 2>&1 || true
}

xray_status() {
    local n=0
    echo "Xray binary: ${XRAY_BIN} $( [[ -x $XRAY_BIN ]] && echo OK || echo MISSING )"
    if systemctl is-active --quiet xray 2>/dev/null; then
        echo "Service: running"
    else
        echo "Service: NOT running"
    fi
    if xray_load_config; then
        echo "Vision TCP port: ${XRAY_VISION_PORT}"
        echo "XHTTP TCP port: ${XRAY_XHTTP_PORT}"
        echo "REALITY dest: ${XRAY_DEST}"
        echo "SNI: ${XRAY_SNI}"
        echo "XHTTP path: ${XRAY_XHTTP_PATH}"
    else
        echo "Config: not found ($XRAY_CONFIG_FILE)"
    fi
    n="$(xray_list_clients | wc -l | tr -d ' ')"
    echo "Clients: ${n}"
    if command -v ss >/dev/null 2>&1 && [[ -n "${XRAY_VISION_PORT:-}" ]]; then
        ss -lnt | grep -E ":${XRAY_VISION_PORT}|:${XRAY_XHTTP_PORT}" || true
    fi
}
