#!/bin/bash

# ==============================================================================
# Shared function library for Hysteria2 (QUIC/UDP + optional Salamander OBFS)
# Author: @dna0120
# Version: 5.21.2
# Date: 2026-08-14
# Repository: https://github.com/dna0120/Freedom
# ==============================================================================

HY2_DIR="${HY2_DIR:-/root/hysteria}"
HY2_CONFIG_FILE="${HY2_CONFIG_FILE:-$HY2_DIR/hy2setup_cfg.init}"
HY2_CLIENTS_DIR="${HY2_CLIENTS_DIR:-$HY2_DIR/clients}"
HY2_SERVER_YAML="${HY2_SERVER_YAML:-/etc/hysteria/config.yaml}"
HY2_BIN="${HY2_BIN:-/usr/local/bin/hysteria}"
HY2_CERT_DIR="${HY2_CERT_DIR:-$HY2_DIR/certs}"
HY2_COMMON_VERSION="5.21.2"

_HY2_TEMP_FILES=()
_HY2_TEMP_REGISTRY="${HY2_DIR}/.hy2_temp_registry.$$"

_hy2_cleanup() {
    local f
    for f in "${_HY2_TEMP_FILES[@]}"; do
        [[ -f "$f" ]] && rm -f "$f"
    done
    if [[ -n "${_HY2_TEMP_REGISTRY:-}" && -f "$_HY2_TEMP_REGISTRY" && ! -L "$_HY2_TEMP_REGISTRY" ]]; then
        while IFS= read -r f; do
            [[ -n "$f" && -f "$f" ]] && rm -f "$f"
        done < "$_HY2_TEMP_REGISTRY"
        rm -f "$_HY2_TEMP_REGISTRY"
    fi
}

hy2_mktemp() {
    local dir="${1:-}" f
    if [[ -n "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null
        f=$(mktemp -p "$dir") || return 1
    else
        f=$(mktemp) || return 1
    fi
    _HY2_TEMP_FILES+=("$f")
    [[ -n "${_HY2_TEMP_REGISTRY:-}" ]] && printf '%s\n' "$f" >> "$_HY2_TEMP_REGISTRY" 2>/dev/null
    echo "$f"
}

if ! declare -f log >/dev/null 2>&1; then
    log()       { echo "[INFO] $1"; }
    log_warn()  { echo "[WARN] $1" >&2; }
    log_error() { echo "[ERROR] $1" >&2; }
    log_debug() { echo "[DEBUG] $1"; }
fi

hy2_is_installed() {
    [[ -x "$HY2_BIN" && -f "$HY2_SERVER_YAML" && -f "$HY2_CONFIG_FILE" ]]
}

hy2_ensure_dirs() {
    mkdir -p "$HY2_DIR" "$HY2_CLIENTS_DIR" "$HY2_CERT_DIR" "$(dirname "$HY2_SERVER_YAML")" || return 1
    chmod 700 "$HY2_DIR" "$HY2_CLIENTS_DIR" "$HY2_CERT_DIR" 2>/dev/null || true
}

hy2_acl_yaml_block() {
    if [[ "${HY2_ALLOW_PRIVATE:-0}" == "1" ]]; then
        return 0
    fi
    cat <<'ACL'

acl:
  inline:
    - reject(10.0.0.0/8)
    - reject(172.16.0.0/12)
    - reject(192.168.0.0/16)
    - reject(127.0.0.0/8)
    - reject(169.254.169.254/32)
    - reject(::1/128)
    - reject(fc00::/7)
ACL
}

if ! declare -f freedom_install_certbot_deploy_hook >/dev/null 2>&1; then
    freedom_install_certbot_deploy_hook() {
        local hook="/etc/letsencrypt/renewal-hooks/deploy/freedom.sh"
        mkdir -p "$(dirname "$hook")" 2>/dev/null || return 1
        cat > "$hook" <<'EOF'
#!/bin/bash
systemctl reload-or-restart xray 2>/dev/null || true
systemctl reload-or-restart hysteria-server 2>/dev/null || true
EOF
        chmod 755 "$hook" 2>/dev/null || return 1
    }
fi

hy2_valid_name() {
    local n="$1"
    [[ "$n" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    (( ${#n} >= 1 && ${#n} <= 15 ))
}

hy2_urlencode() {
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

# Always emit a double-quoted scalar: an unquoted name like 01 is read back as
# a number, which silently breaks the userpass map and yields auth errors.
hy2_yaml_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

hy2_random_udp_port() {
    echo $(( (RANDOM % 16384) + 49152 ))
}

hy2_udp_port_free() {
    local port="$1"
    [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] || return 1
    (( port <= 65535 )) || return 1
    if ss -lun 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${port}$"; then
        return 1
    fi
    return 0
}

hy2_pick_free_udp_port() {
    local p i
    for i in $(seq 1 40); do
        p="$(hy2_random_udp_port)"
        if hy2_udp_port_free "$p"; then
            echo "$p"
            return 0
        fi
    done
    return 1
}

hy2_get_public_ip() {
    local ip svc
    if [[ -n "${HY2_ENDPOINT:-}" ]]; then
        printf '%s\n' "$HY2_ENDPOINT"
        return 0
    fi
    for svc in \
        "https://api.ipify.org" \
        "https://ifconfig.me/ip" \
        "https://icanhazip.com"; do
        ip="$(curl -4 -fsS --max-time 8 "$svc" 2>/dev/null | tr -d '[:space:]')"
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { printf '%s\n' "$ip"; return 0; }
    done
    return 1
}

hy2_rand_password() {
    openssl rand -base64 18 2>/dev/null | tr -d '/+=' | head -c 22
    echo
}

hy2_generate_self_signed() {
    local cn="${1:-hysteria.local}"
    hy2_ensure_dirs || return 1
    # A SAN is required by modern TLS stacks; CN alone is no longer accepted.
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
        -keyout "$HY2_CERT_DIR/server.key" \
        -out "$HY2_CERT_DIR/server.crt" \
        -subj "/CN=${cn}" \
        -addext "subjectAltName=DNS:${cn}" >/dev/null 2>&1 \
        || openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
            -keyout "$HY2_CERT_DIR/server.key" \
            -out "$HY2_CERT_DIR/server.crt" \
            -subj "/CN=${cn}" >/dev/null 2>&1 \
        || return 1
    chmod 600 "$HY2_CERT_DIR/server.key" "$HY2_CERT_DIR/server.crt"
    HY2_TLS_CERT="$HY2_CERT_DIR/server.crt"
    HY2_TLS_KEY="$HY2_CERT_DIR/server.key"
}

# Certificate fingerprint for pinning. Clients that refuse to trust a
# self-signed certificate (most iOS apps) accept it when it is pinned.
hy2_cert_fingerprint() {
    local cert="${1:-${HY2_TLS_CERT:-}}" out
    [[ -f "$cert" ]] || return 1
    out="$(openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null)" || return 1
    printf '%s' "${out#*=}"
}

hy2_issue_acme_or_self() {
    local domain="$1" email="${2:-admin@$1}"
    local live="/etc/letsencrypt/live/${domain}"
    hy2_ensure_dirs || return 1

    if [[ -z "$domain" ]]; then
        hy2_generate_self_signed "hysteria.local" || return 1
        HY2_INSECURE=1
        HY2_SNI="hysteria.local"
        return 0
    fi

    if [[ -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]]; then
        HY2_TLS_CERT="$live/fullchain.pem"
        HY2_TLS_KEY="$live/privkey.pem"
        HY2_INSECURE=0
        HY2_SNI="$domain"
        HY2_DOMAIN="$domain"
        return 0
    fi

    if ! command -v certbot >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot >/dev/null 2>&1 || true
    fi
    if command -v certbot >/dev/null 2>&1; then
        log "Requesting Let's Encrypt cert for Hysteria domain $domain..."
        if certbot certonly --standalone --non-interactive --agree-tos \
            --register-unsafely-without-email \
            --deploy-hook "systemctl reload-or-restart hysteria-server" \
            -d "$domain" >/dev/null 2>&1 \
            || certbot certonly --standalone --non-interactive --agree-tos \
                --deploy-hook "systemctl reload-or-restart hysteria-server" \
                -m "$email" -d "$domain" >/dev/null 2>&1; then
            if [[ -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]]; then
                HY2_TLS_CERT="$live/fullchain.pem"
                HY2_TLS_KEY="$live/privkey.pem"
                HY2_INSECURE=0
                HY2_SNI="$domain"
                HY2_DOMAIN="$domain"
                freedom_install_certbot_deploy_hook || true
                return 0
            fi
        fi
        log_warn "ACME failed for $domain — using self-signed (client needs insecure=1)."
    fi
    hy2_generate_self_signed "$domain" || return 1
    HY2_INSECURE=1
    HY2_SNI="$domain"
    HY2_DOMAIN="$domain"
}

hy2_save_config() {
    hy2_ensure_dirs || return 1
    local tmp
    tmp="$(hy2_mktemp "$HY2_DIR")" || return 1
    cat > "$tmp" <<EOF
export HY2_PORT=${HY2_PORT}
export HY2_DOMAIN='${HY2_DOMAIN:-}'
export HY2_SNI='${HY2_SNI:-}'
export HY2_TLS_CERT='${HY2_TLS_CERT}'
export HY2_TLS_KEY='${HY2_TLS_KEY}'
export HY2_INSECURE=${HY2_INSECURE:-1}
export HY2_OBFS='${HY2_OBFS:-}'
export HY2_MASQUERADE='${HY2_MASQUERADE:-https://www.microsoft.com/}'
export HY2_ENDPOINT='${HY2_ENDPOINT:-}'
export HY2_ALLOW_PRIVATE=${HY2_ALLOW_PRIVATE:-0}
EOF
    chmod 600 "$tmp"
    mv -f "$tmp" "$HY2_CONFIG_FILE"
}

hy2_load_config() {
    [[ -f "$HY2_CONFIG_FILE" ]] || return 1
    # shellcheck source=/dev/null
    source "$HY2_CONFIG_FILE"
    : "${HY2_PORT:=}" "${HY2_DOMAIN:=}" "${HY2_SNI:=}"
    : "${HY2_TLS_CERT:=}" "${HY2_TLS_KEY:=}" "${HY2_INSECURE:=1}"
    : "${HY2_OBFS:=}" "${HY2_MASQUERADE:=https://www.microsoft.com/}" "${HY2_ENDPOINT:=}"
    : "${HY2_ALLOW_PRIVATE:=0}"
}

hy2_userpass_yaml() {
    local f name user pass
    shopt -s nullglob
    for f in "$HY2_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        user="${HY2_CLIENT_USER:-$name}"
        pass="${HY2_CLIENT_PASS:-}"
        [[ -n "$pass" ]] || continue
        printf '    %s: %s\n' "$(hy2_yaml_escape "$user")" "$(hy2_yaml_escape "$pass")"
    done
    shopt -u nullglob
}

hy2_render_server_config() {
    hy2_ensure_dirs || return 1
    [[ -n "${HY2_PORT:-}" && -f "${HY2_TLS_CERT:-}" && -f "${HY2_TLS_KEY:-}" ]] || return 1
    local tmp users_block obfs_block
    users_block="$(hy2_userpass_yaml)"
    if [[ -z "$users_block" ]]; then
        # Keep auth section valid with a disabled placeholder until first client.
        users_block="    \"_bootstrap\": $(hy2_yaml_escape "$(hy2_rand_password | tr -d '\n')")"
    fi
    obfs_block=""
    if [[ -n "${HY2_OBFS:-}" ]]; then
        obfs_block=$(cat <<OBFS
obfs:
  type: salamander
  salamander:
    password: $(hy2_yaml_escape "$HY2_OBFS")
OBFS
)
    fi
    local acl_block
    acl_block="$(hy2_acl_yaml_block)"
    tmp="$(hy2_mktemp "$(dirname "$HY2_SERVER_YAML")")" || return 1
    cat > "$tmp" <<EOF
listen: :${HY2_PORT}

tls:
  cert: $(hy2_yaml_escape "$HY2_TLS_CERT")
  key: $(hy2_yaml_escape "$HY2_TLS_KEY")

auth:
  type: userpass
  userpass:
${users_block}

${obfs_block}
${acl_block}

masquerade:
  type: proxy
  proxy:
    url: $(hy2_yaml_escape "$HY2_MASQUERADE")
    rewriteHost: true
EOF
    chmod 600 "$tmp"
    mv -f "$tmp" "$HY2_SERVER_YAML"
    chmod 600 "$HY2_SERVER_YAML"
}

hy2_apply_config() {
    hy2_render_server_config || return 1
    if [[ "${HY2_ALLOW_PRIVATE:-0}" != "1" ]]; then
        log "Hysteria2 ACL: blocking private/loopback/link-local egress (set HY2_ALLOW_PRIVATE=1 to allow LAN)."
    fi
    if systemctl list-unit-files hysteria-server.service >/dev/null 2>&1; then
        systemctl enable hysteria-server.service >/dev/null 2>&1 || true
        systemctl restart hysteria-server.service || return 1
    elif [[ -x "$HY2_BIN" ]]; then
        log_warn "hysteria-server.service missing — binary present at $HY2_BIN"
        return 1
    fi
    return 0
}

hy2_share_link() {
    local name="$1" user="$2" pass="$3"
    local host sni insecure enc_name enc_obfs fp query
    host="$(hy2_get_public_ip 2>/dev/null || true)"
    [[ -n "$host" ]] || host="${HY2_ENDPOINT:-127.0.0.1}"
    if [[ -n "${HY2_DOMAIN:-}" && "${HY2_INSECURE:-1}" == "0" ]]; then
        host="$HY2_DOMAIN"
    fi
    sni="${HY2_SNI:-$host}"
    insecure="${HY2_INSECURE:-1}"
    enc_name="$(hy2_urlencode "$name")"
    query="insecure=${insecure}&sni=$(hy2_urlencode "$sni")"
    if [[ "$insecure" == "1" ]]; then
        fp="$(hy2_cert_fingerprint 2>/dev/null || true)"
        [[ -n "$fp" ]] && query+="&pinSHA256=$(hy2_urlencode "$fp")"
    fi
    if [[ -n "${HY2_OBFS:-}" ]]; then
        enc_obfs="$(hy2_urlencode "$HY2_OBFS")"
        query+="&obfs=salamander&obfs-password=${enc_obfs}"
    fi
    printf 'hysteria2://%s:%s@%s:%s/?%s#%s\n' \
        "$(hy2_urlencode "$user")" "$(hy2_urlencode "$pass")" \
        "$host" "$HY2_PORT" "$query" "$enc_name"
}

hy2_write_client_files() {
    local name="$1" user="$2" pass="$3"
    local host link tmp
    host="$(hy2_get_public_ip 2>/dev/null || true)"
    [[ -n "$host" ]] || host="${HY2_ENDPOINT:-127.0.0.1}"
    [[ -n "${HY2_DOMAIN:-}" && "${HY2_INSECURE:-1}" == "0" ]] && host="$HY2_DOMAIN"
    link="$(hy2_share_link "$name" "$user" "$pass")"
    printf 'HY2_CLIENT_NAME=%s\nHY2_CLIENT_USER=%s\nHY2_CLIENT_PASS=%s\n' \
        "$name" "$user" "$pass" > "$HY2_CLIENTS_DIR/${name}.meta"
    chmod 600 "$HY2_CLIENTS_DIR/${name}.meta"
    local insecure_yaml="false" fp=""
    if [[ "${HY2_INSECURE:-1}" == "1" ]]; then
        insecure_yaml="true"
        fp="$(hy2_cert_fingerprint 2>/dev/null || true)"
    fi
    tmp="$(hy2_mktemp "$HY2_CLIENTS_DIR")" || return 1
    cat > "$tmp" <<EOF
server: $(hy2_yaml_escape "${host}:${HY2_PORT}")
auth: $(hy2_yaml_escape "${user}:${pass}")
tls:
  sni: $(hy2_yaml_escape "$HY2_SNI")
  insecure: ${insecure_yaml}
EOF
    if [[ -n "$fp" ]]; then
        printf '  pinSHA256: %s\n' "$(hy2_yaml_escape "$fp")" >> "$tmp"
    fi
    if [[ -n "${HY2_OBFS:-}" ]]; then
        cat >> "$tmp" <<EOF
obfs:
  type: salamander
  salamander:
    password: $(hy2_yaml_escape "$HY2_OBFS")
EOF
    fi
    chmod 600 "$tmp"
    mv -f "$tmp" "$HY2_CLIENTS_DIR/${name}.yaml"
    printf '%s\n' "$link" > "$HY2_CLIENTS_DIR/${name}.url"
    chmod 600 "$HY2_CLIENTS_DIR/${name}.url"
    printf '%s\n' "$link"
}

hy2_client_exists() {
    [[ -f "$HY2_CLIENTS_DIR/${1}.meta" ]]
}

# Port, SNI or obfs changes invalidate every issued profile, so rewrite them.
hy2_refresh_client_files() {
    local f name user pass count=0
    shopt -s nullglob
    for f in "$HY2_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        user="${HY2_CLIENT_USER:-$name}"
        pass="${HY2_CLIENT_PASS:-}"
        [[ -n "$pass" ]] || continue
        hy2_write_client_files "$name" "$user" "$pass" >/dev/null || continue
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -t png -o "$HY2_CLIENTS_DIR/${name}.png" \
                < "$HY2_CLIENTS_DIR/${name}.url" 2>/dev/null || true
        fi
        count=$((count + 1))
    done
    shopt -u nullglob
    [[ "$count" -gt 0 ]] && log "Refreshed $count Hysteria2 client profile(s)."
    return 0
}

hy2_add_client() {
    local name="$1" user pass
    hy2_valid_name "$name" || { log_error "Invalid client name"; return 1; }
    hy2_client_exists "$name" && { log_error "Client '$name' already exists"; return 1; }
    hy2_load_config || { log_error "Hysteria2 is not configured"; return 1; }
    user="$name"
    pass="$(hy2_rand_password | tr -d '\n')"
    [[ -n "$pass" ]] || { log_error "Password generation failed"; return 1; }
    hy2_write_client_files "$name" "$user" "$pass" >/dev/null || return 1
    hy2_apply_config || return 1
    hy2_share_link "$name" "$user" "$pass"
}

hy2_remove_client() {
    local name="$1"
    hy2_client_exists "$name" || { log_error "Client '$name' not found"; return 1; }
    rm -f "$HY2_CLIENTS_DIR/${name}.meta" \
          "$HY2_CLIENTS_DIR/${name}.yaml" \
          "$HY2_CLIENTS_DIR/${name}.url" \
          "$HY2_CLIENTS_DIR/${name}.png"
    hy2_load_config || return 1
    hy2_apply_config
}

hy2_list_clients() {
    local f name user
    shopt -s nullglob
    for f in "$HY2_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        user="${HY2_CLIENT_USER:-$name}"
        printf '%s\t%s\n' "$name" "$user"
    done
    shopt -u nullglob
}

hy2_maybe_open_ufw() {
    command -v ufw >/dev/null 2>&1 || return 0
    ufw status 2>/dev/null | grep -qi 'Status: active' || return 0
    ufw allow "${HY2_PORT}/udp" comment "Hysteria2 QUIC" >/dev/null 2>&1 || true
}

hy2_maybe_close_ufw() {
    command -v ufw >/dev/null 2>&1 || return 0
    [[ -n "${HY2_PORT:-}" ]] && ufw delete allow "${HY2_PORT}/udp" >/dev/null 2>&1 || true
}

hy2_status() {
    local n=0
    echo "Hysteria binary: ${HY2_BIN} $( [[ -x $HY2_BIN ]] && echo OK || echo MISSING )"
    if systemctl is-active --quiet hysteria-server 2>/dev/null; then
        echo "Service: running"
    else
        echo "Service: NOT running"
    fi
    if hy2_load_config; then
        echo "UDP port: ${HY2_PORT}"
        echo "SNI: ${HY2_SNI}"
        echo "Domain: ${HY2_DOMAIN:-none}"
        echo "Insecure TLS: ${HY2_INSECURE}"
        echo "Salamander OBFS: $( [[ -n ${HY2_OBFS:-} ]] && echo enabled || echo disabled )"
        echo "Masquerade: ${HY2_MASQUERADE}"
        echo "TLS cert: ${HY2_TLS_CERT}"
        if [[ "${HY2_INSECURE:-1}" == "1" ]]; then
            echo "Cert pin (SHA256): $(hy2_cert_fingerprint 2>/dev/null || echo unavailable)"
        fi
    else
        echo "Config: not found ($HY2_CONFIG_FILE)"
    fi
    n="$(hy2_list_clients | wc -l | tr -d ' ')"
    echo "Clients: ${n}"
    if command -v ss >/dev/null 2>&1 && [[ -n "${HY2_PORT:-}" ]]; then
        ss -lun | grep -E ":${HY2_PORT}" || true
    fi
}
