#!/bin/bash

# ==============================================================================
# Shared function library for Xray
#   - VLESS + REALITY: Vision / XHTTP / gRPC
#   - Optional CDN front: XHTTP+TLS / gRPC+TLS (domain + cert, Cloudflare-friendly)
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
XRAY_CERT_DIR="${XRAY_CERT_DIR:-$XRAY_DIR/certs}"
XRAY_SNI_CANDIDATES_FILE="${XRAY_SNI_CANDIDATES_FILE:-$XRAY_DIR/sni_candidates.txt}"
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

# Optional $2 appends a suffix; xray picks the config parser from the file
# extension, so the temp file it validates must still end in .json.
xray_mktemp() {
    local dir="${1:-}" suffix="${2:-}" f
    if [[ -n "$dir" ]]; then
        mkdir -p "$dir" 2>/dev/null
        f=$(mktemp -p "$dir" "tmp.XXXXXXXXXX${suffix}") || return 1
    else
        f=$(mktemp "${TMPDIR:-/tmp}/tmp.XXXXXXXXXX${suffix}") || return 1
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
    mkdir -p "$XRAY_DIR" "$XRAY_CLIENTS_DIR" "$XRAY_CERT_DIR" "$(dirname "$XRAY_CONF_JSON")" || return 1
    chmod 700 "$XRAY_DIR" "$XRAY_CLIENTS_DIR" "$XRAY_CERT_DIR" 2>/dev/null || true
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
    local avoid="${1:-}" avoid2="${2:-}" p i
    for i in $(seq 1 40); do
        p="$(xray_random_tcp_port)"
        [[ "$p" == "$avoid" || "$p" == "$avoid2" ]] && continue
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
        "https://api.ipify.org" \
        "https://ifconfig.me/ip" \
        "https://icanhazip.com"; do
        ip="$(curl -4 -fsS --max-time 8 "$svc" 2>/dev/null | tr -d '[:space:]')"
        [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && { printf '%s\n' "$ip"; return 0; }
    done
    return 1
}

xray_generate_short_id() {
    openssl rand -hex 4 2>/dev/null || printf '%08x' "$RANDOM$RANDOM"
}

xray_generate_keys() {
    local out priv pub
    command -v "$XRAY_BIN" >/dev/null 2>&1 || return 1
    out="$("$XRAY_BIN" x25519 2>/dev/null)" || return 1
    priv="$(printf '%s\n' "$out" | awk -F': ' '/Private/{print $2}' | tr -d '[:space:]')"
    pub="$(printf '%s\n' "$out" | awk -F': ' '/Public/{print $2}' | tr -d '[:space:]')"
    [[ -n "$priv" && -n "$pub" ]] || return 1
    XRAY_PRIVATE_KEY="$priv"
    XRAY_PUBLIC_KEY="$pub"
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

xray_generate_service_name() {
    local hex
    hex="$(openssl rand -hex 4 2>/dev/null || printf '%08x' "$RANDOM")"
    printf 'grpc%s' "$hex"
}

# Candidate dests: TLS1.3 sites that are NOT behind Cloudflare (REALITY warning).
# Most big-tech sites now negotiate X25519MLKEM768, which REALITY cannot relay,
# so the list leans towards hosts still on classic X25519.
xray_dest_candidates() {
    cat <<'EOF'
www.yahoo.co.jp
www.rakuten.co.jp
www.nicovideo.jp
www.jal.co.jp
www.nintendo.co.jp
www.ntt.com
www.softbank.jp
www.fujitsu.com
www.hitachi.com
www.panasonic.com
www.canon.com
www.ricoh.com
www.sharp.co.jp
www.mitsubishielectric.com
www.asus.com
www.lenovo.com
www.dell.com
www.hp.com
www.sap.com
www.ibm.com
www.samsung.com
www.sony.com
www.intel.com
www.apple.com
www.microsoft.com
EOF
    # Users may continuously extend the pool without modifying this script.
    # Blank lines, comments, ports and duplicate hosts are normalized below.
    if [[ -f "$XRAY_SNI_CANDIDATES_FILE" && ! -L "$XRAY_SNI_CANDIDATES_FILE" ]]; then
        sed 's/[[:space:]]*#.*$//; s/:443[[:space:]]*$//; /^[[:space:]]*$/d' \
            "$XRAY_SNI_CANDIDATES_FILE"
    fi
}

# REALITY relays the real handshake of the target. A target that negotiates a
# post-quantum key exchange (X25519MLKEM768) makes that handshake fail with
# "handshake did not complete successfully", so such hosts are unusable.
xray_tls_ping_ok() {
    local host="$1" out
    command -v "$XRAY_BIN" >/dev/null 2>&1 || return 1
    out="$(timeout 20 "$XRAY_BIN" tls ping "$host" 2>/dev/null)" || return 1
    printf '%s\n' "$out" | grep -q 'Handshake succeeded' || return 1
    printf '%s\n' "$out" | grep -qiE 'tls version: +tls ?1\.3' || return 1
    if printf '%s\n' "$out" | grep -qiE 'post-quantum key exchange: +true|MLKEM'; then
        return 2
    fi
    return 0
}

# Print a tab-separated runtime report from this VPS:
#   host  AVAILABLE|POST_QUANTUM|UNREACHABLE  TLS/KEX detail
# Availability is deliberately measured live; a globally cached answer goes
# stale when a site changes its TLS stack or resolves to another edge.
xray_scan_destinations() {
    local host out status detail available=0 pq=0 failed=0
    local seen_file
    seen_file="$(xray_mktemp)" || return 1
    : > "$seen_file"
    printf 'SNI\tSTATUS\tDETAIL\n'
    while IFS= read -r host; do
        host="${host//[[:space:]]/}"
        host="${host%%:*}"
        [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || continue
        grep -Fqx "$host" "$seen_file" 2>/dev/null && continue
        printf '%s\n' "$host" >> "$seen_file"
        out="$(timeout 20 "$XRAY_BIN" tls ping "$host" 2>/dev/null || true)"
        if ! printf '%s\n' "$out" | grep -q 'Handshake succeeded'; then
            status="UNREACHABLE"; detail="TLS ping failed"; failed=$((failed + 1))
        elif ! printf '%s\n' "$out" | grep -qiE 'tls version: +tls ?1\.3'; then
            status="UNREACHABLE"; detail="TLS 1.3 unavailable"; failed=$((failed + 1))
        elif printf '%s\n' "$out" | grep -qiE 'post-quantum key exchange: +true|MLKEM'; then
            status="POST_QUANTUM"; detail="X25519MLKEM768 (not usable by REALITY)"; pq=$((pq + 1))
        else
            status="AVAILABLE"; detail="TLS 1.3 + classic X25519"; available=$((available + 1))
        fi
        printf '%s\t%s\t%s\n' "$host" "$status" "$detail"
    done < <(xray_dest_candidates)
    printf 'SUMMARY\tAVAILABLE=%d\tPOST_QUANTUM=%d UNREACHABLE=%d\n' \
        "$available" "$pq" "$failed"
    (( available > 0 ))
}

xray_add_sni_candidate() {
    local host="${1%%:*}" rc
    host="${host//[[:space:]]/}"
    [[ "$host" =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]] || {
        log_error "Invalid SNI hostname: $host"
        return 1
    }
    xray_tls_ping_ok "$host"
    rc=$?
    case "$rc" in
        0) ;;
        2) log_error "$host uses post-quantum key exchange and is not usable by REALITY"; return 1 ;;
        *) log_error "$host failed the live TLS 1.3 check"; return 1 ;;
    esac
    mkdir -p "$(dirname "$XRAY_SNI_CANDIDATES_FILE")" || return 1
    touch "$XRAY_SNI_CANDIDATES_FILE" || return 1
    chmod 600 "$XRAY_SNI_CANDIDATES_FILE"
    if grep -Fqx "$host" "$XRAY_SNI_CANDIDATES_FILE" 2>/dev/null; then
        log "$host is already in the custom SNI list."
        return 0
    fi
    printf '%s\n' "$host" >> "$XRAY_SNI_CANDIDATES_FILE"
    log "Added verified REALITY SNI candidate: $host"
}

# Import a list of hostnames (one per line). Only hosts that pass the live
# REALITY checks (TLS 1.3 + classic X25519, not post-quantum) are appended to
# the custom candidate pool that xray_dest_candidates() already reads.
xray_import_sni_file() {
    local file="$1" host rc added=0 skipped=0 pq=0 bad=0
    [[ -f "$file" ]] || { log_error "SNI list not found: $file"; return 1; }
    mkdir -p "$(dirname "$XRAY_SNI_CANDIDATES_FILE")" || return 1
    touch "$XRAY_SNI_CANDIDATES_FILE" || return 1
    chmod 600 "$XRAY_SNI_CANDIDATES_FILE"
    printf 'SNI\tSTATUS\tDETAIL\n'
    while IFS= read -r host || [[ -n "$host" ]]; do
        host="${host%%#*}"
        host="${host//[[:space:]]/}"
        host="${host%%:*}"
        [[ -z "$host" ]] && continue
        [[ "$host" =~ ^([A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}$ ]] || continue
        case "$host" in
            *cloudflare*|*cloudfront*|*akamai*|*edgekey*|*edgesuite*)
                printf '%s\tSKIP\tCDN generic / unsuitable for REALITY dest\n' "$host"
                skipped=$((skipped + 1))
                continue
                ;;
        esac
        xray_tls_ping_ok "$host"
        rc=$?
        case "$rc" in
            0)
                if grep -Fqx "$host" "$XRAY_SNI_CANDIDATES_FILE" 2>/dev/null; then
                    printf '%s\tAVAILABLE\talready in candidate list\n' "$host"
                else
                    printf '%s\n' "$host" >> "$XRAY_SNI_CANDIDATES_FILE"
                    printf '%s\tAVAILABLE\tadded to candidate list\n' "$host"
                    added=$((added + 1))
                fi
                ;;
            2)
                printf '%s\tPOST_QUANTUM\tX25519MLKEM768 (not usable by REALITY)\n' "$host"
                pq=$((pq + 1))
                ;;
            *)
                printf '%s\tUNREACHABLE\tTLS 1.3 / classic X25519 check failed\n' "$host"
                bad=$((bad + 1))
                ;;
        esac
    done < "$file"
    printf 'SUMMARY\tADDED=%d\tPOST_QUANTUM=%d\tUNREACHABLE=%d\tSKIP=%d\n' \
        "$added" "$pq" "$bad" "$skipped"
    log "Custom REALITY SNI pool: $XRAY_SNI_CANDIDATES_FILE"
    (( added > 0 || pq + bad + skipped > 0 ))
}

# Discover nearby HTTPS domains with Reality-SNI-Finder
# (https://github.com/ShatakVPN/Reality-SNI-Finder), then keep only those that
# Freedom's live REALITY checks accept. Scanning neighbor /24s may violate a
# host's AUP — we use conservative defaults and require an explicit opt-in.
xray_discover_nearby_sni() {
    local work="${XRAY_DIR}/sni-finder"
    local py_url="https://raw.githubusercontent.com/ShatakVPN/Reality-SNI-Finder/main/reality_sni_finder.py"
    local py="$work/reality_sni_finder.py"
    local out="$work/domains.txt"
    local miss=()

    log_warn "Nearby SNI discovery scans TCP/443 on this VPS's /24 and neighbor blocks (masscan)."
    log_warn "Only run this where your provider allows it. Defaults are conservative."

    mkdir -p "$work" || return 1
    chmod 700 "$work"

    for b in python3 masscan curl openssl; do
        command -v "$b" >/dev/null 2>&1 || miss+=("$b")
    done
    if ((${#miss[@]})); then
        log "Installing missing tools: ${miss[*]}"
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${miss[@]}" >/dev/null 2>&1 \
                || { log_error "Could not install: ${miss[*]}"; return 1; }
        else
            log_error "Install these tools first: ${miss[*]}"
            return 1
        fi
    fi

    if ! curl -fLso "$py" --max-time 60 --retry 2 "$py_url"; then
        log_error "Failed to download Reality-SNI-Finder engine from GitHub"
        return 1
    fi
    chmod 700 "$py"

    # Conservative defaults from the upstream README; override via env if needed.
    (
        cd "$work" || exit 1
        export RSF_BLOCKS="${RSF_BLOCKS:-6}"
        export RSF_RATE="${RSF_RATE:-4000}"
        export RSF_TIMEOUT="${RSF_TIMEOUT:-8}"
        export RSF_THREADS="${RSF_THREADS:-64}"
        export RSF_VERIFY_H2="${RSF_VERIFY_H2:-1}"
        export RSF_INCLUDE_GENERIC="${RSF_INCLUDE_GENERIC:-0}"
        [[ -n "${RSF_REF_IP:-}" ]] && export RSF_REF_IP
        log "Running Reality-SNI-Finder (blocks=${RSF_BLOCKS}, rate=${RSF_RATE} pps)..."
        python3 "$py"
    ) || { log_error "Reality-SNI-Finder finished with errors (see above)."; return 1; }

    [[ -s "$out" ]] || { log_error "No domains discovered ($out empty)."; return 1; }
    log "Discovered $(wc -l < "$out" | tr -d ' ') nearby candidates — verifying for REALITY..."
    xray_import_sni_file "$out"
}

xray_pick_dest() {
    local cand rc fallback=""
    if [[ -n "${XRAY_DEST:-}" ]]; then
        printf '%s\n' "${XRAY_DEST%%:*}"
        return 0
    fi
    while IFS= read -r cand; do
        [[ -z "$cand" || "$cand" =~ ^# ]] && continue
        xray_tls_ping_ok "$cand"
        rc=$?
        case "$rc" in
            0)
                printf '%s\n' "$cand"
                return 0
                ;;
            2)
                [[ -z "$fallback" ]] && fallback="$cand"
                log_warn "REALITY dest candidate uses post-quantum key exchange, skipping: $cand"
                ;;
            *)
                log_warn "REALITY dest candidate failed tls ping: $cand"
                ;;
        esac
    done < <(xray_dest_candidates)
    if [[ -n "$fallback" ]]; then
        log_warn "No post-quantum-free REALITY dest found; falling back to $fallback (clients may fail to handshake)."
        printf '%s\n' "$fallback"
        return 0
    fi
    printf '%s\n' "www.yahoo.co.jp"
}

# dest/SNI changes invalidate every issued profile, so rewrite them in place.
xray_refresh_client_files() {
    local f name proto uuid count=0
    shopt -s nullglob
    for f in "$XRAY_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        proto="${XRAY_CLIENT_PROTO:-}"
        uuid="${XRAY_CLIENT_UUID:-}"
        [[ -n "$proto" && -n "$uuid" ]] || continue
        xray_write_client_files "$name" "$proto" "$uuid" >/dev/null || continue
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -t png -o "$XRAY_CLIENTS_DIR/${name}.png" \
                < "$XRAY_CLIENTS_DIR/${name}.url" 2>/dev/null || true
        fi
        count=$((count + 1))
    done
    shopt -u nullglob
    [[ "$count" -gt 0 ]] && log "Refreshed $count Xray client profile(s)."
    return 0
}

xray_cdn_enabled() {
    [[ "${XRAY_CDN_ENABLED:-0}" == "1" && -n "${XRAY_DOMAIN:-}" && -f "${XRAY_TLS_CERT:-}" && -f "${XRAY_TLS_KEY:-}" ]]
}

xray_issue_tls_cert() {
    local domain="$1" email="${2:-admin@$1}"
    local live="/etc/letsencrypt/live/${domain}"
    xray_ensure_dirs || return 1
    [[ -n "$domain" ]] || return 1

    if [[ -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]]; then
        XRAY_TLS_CERT="$live/fullchain.pem"
        XRAY_TLS_KEY="$live/privkey.pem"
        log "Reusing existing Let's Encrypt cert for $domain"
        return 0
    fi

    if ! command -v certbot >/dev/null 2>&1; then
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot >/dev/null 2>&1 || true
        fi
    fi

    if command -v certbot >/dev/null 2>&1; then
        log "Requesting Let's Encrypt certificate for $domain (standalone, needs :80 free)..."
        if certbot certonly --standalone --non-interactive --agree-tos \
            --register-unsafely-without-email \
            -d "$domain" >/dev/null 2>&1 \
            || certbot certonly --standalone --non-interactive --agree-tos \
                -m "$email" -d "$domain" >/dev/null 2>&1; then
            if [[ -f "$live/fullchain.pem" && -f "$live/privkey.pem" ]]; then
                XRAY_TLS_CERT="$live/fullchain.pem"
                XRAY_TLS_KEY="$live/privkey.pem"
                log "Let's Encrypt certificate issued for $domain"
                return 0
            fi
        fi
        log_warn "certbot failed (port 80 busy, DNS not ready, or rate limit). Falling back to self-signed."
    else
        log_warn "certbot not available — generating self-signed cert for CDN/TLS mode."
    fi

    openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
        -keyout "$XRAY_CERT_DIR/${domain}.key" \
        -out "$XRAY_CERT_DIR/${domain}.crt" \
        -subj "/CN=${domain}" \
        -addext "subjectAltName=DNS:${domain}" >/dev/null 2>&1 \
        || openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
            -keyout "$XRAY_CERT_DIR/${domain}.key" \
            -out "$XRAY_CERT_DIR/${domain}.crt" \
            -subj "/CN=${domain}" >/dev/null 2>&1 \
        || return 1
    chmod 600 "$XRAY_CERT_DIR/${domain}.key" "$XRAY_CERT_DIR/${domain}.crt"
    XRAY_TLS_CERT="$XRAY_CERT_DIR/${domain}.crt"
    XRAY_TLS_KEY="$XRAY_CERT_DIR/${domain}.key"
    log "Self-signed cert created at $XRAY_TLS_CERT (set Cloudflare SSL to Full, not Full Strict)."
    return 0
}

xray_save_config() {
    xray_ensure_dirs || return 1
    local tmp
    tmp="$(xray_mktemp "$XRAY_DIR")" || return 1
    cat > "$tmp" <<EOF
export XRAY_VISION_PORT=${XRAY_VISION_PORT}
export XRAY_XHTTP_PORT=${XRAY_XHTTP_PORT}
export XRAY_GRPC_PORT=${XRAY_GRPC_PORT}
export XRAY_CDN_PORT=${XRAY_CDN_PORT:-}
export XRAY_CDN_ENABLED=${XRAY_CDN_ENABLED:-0}
export XRAY_DOMAIN='${XRAY_DOMAIN:-}'
export XRAY_TLS_CERT='${XRAY_TLS_CERT:-}'
export XRAY_TLS_KEY='${XRAY_TLS_KEY:-}'
export XRAY_DEST='${XRAY_DEST}'
export XRAY_SNI='${XRAY_SNI}'
export XRAY_PRIVATE_KEY='${XRAY_PRIVATE_KEY}'
export XRAY_PUBLIC_KEY='${XRAY_PUBLIC_KEY}'
export XRAY_SHORT_ID='${XRAY_SHORT_ID}'
export XRAY_XHTTP_PATH='${XRAY_XHTTP_PATH}'
export XRAY_GRPC_SERVICE='${XRAY_GRPC_SERVICE}'
export XRAY_ENDPOINT='${XRAY_ENDPOINT:-}'
EOF
    chmod 600 "$tmp"
    mv -f "$tmp" "$XRAY_CONFIG_FILE"
}

xray_load_config() {
    [[ -f "$XRAY_CONFIG_FILE" ]] || return 1
    # shellcheck source=/dev/null
    source "$XRAY_CONFIG_FILE"
    : "${XRAY_VISION_PORT:=}" "${XRAY_XHTTP_PORT:=}" "${XRAY_GRPC_PORT:=}"
    : "${XRAY_CDN_PORT:=}" "${XRAY_CDN_ENABLED:=0}" "${XRAY_DOMAIN:=}"
    : "${XRAY_TLS_CERT:=}" "${XRAY_TLS_KEY:=}"
    : "${XRAY_DEST:=}" "${XRAY_SNI:=}"
    : "${XRAY_PRIVATE_KEY:=}" "${XRAY_PUBLIC_KEY:=}" "${XRAY_SHORT_ID:=}"
    : "${XRAY_XHTTP_PATH:=}" "${XRAY_GRPC_SERVICE:=}" "${XRAY_ENDPOINT:=}"
}

xray_clients_json_array() {
    local want="$1" f name uuid first=1 proto
    printf '['
    shopt -s nullglob
    for f in "$XRAY_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        proto="${XRAY_CLIENT_PROTO:-}"
        uuid="${XRAY_CLIENT_UUID:-}"
        [[ -n "$uuid" ]] || continue
        case "$want" in
            vision)
                [[ "$proto" == "vision" ]] || continue
                ;;
            xhttp)
                [[ "$proto" == "xhttp" || "$proto" == "cdn-xhttp" ]] || continue
                ;;
            grpc)
                [[ "$proto" == "grpc" || "$proto" == "cdn-grpc" ]] || continue
                ;;
            *) continue ;;
        esac
        # CDN clients only belong on TLS inbounds; REALITY inbounds get direct-only.
        if [[ "$want" == "xhttp" || "$want" == "grpc" ]]; then
            :
        fi
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

# Separate arrays: REALITY inbounds should not list CDN-only clients (and vice versa).
xray_clients_json_array_for() {
    local want="$1" scope="$2" f name uuid first=1 proto
    printf '['
    shopt -s nullglob
    for f in "$XRAY_CLIENTS_DIR"/*.meta; do
        name="$(basename "$f" .meta)"
        # shellcheck source=/dev/null
        source "$f"
        proto="${XRAY_CLIENT_PROTO:-}"
        uuid="${XRAY_CLIENT_UUID:-}"
        [[ -n "$uuid" ]] || continue
        case "$scope:$want:$proto" in
            reality:vision:vision) ;;
            reality:xhttp:xhttp) ;;
            reality:grpc:grpc) ;;
            cdn:xhttp:cdn-xhttp) ;;
            cdn:grpc:cdn-grpc) ;;
            *) continue ;;
        esac
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
    local vision_clients xhttp_clients grpc_clients
    local cdn_xhttp_clients cdn_grpc_clients
    local dest sni tmp cdn_block=""
    dest="${XRAY_DEST}"
    [[ "$dest" == *:* ]] || dest="${dest}:443"
    sni="${XRAY_SNI:-${XRAY_DEST%%:*}}"
    vision_clients="$(xray_clients_json_array_for vision reality)"
    xhttp_clients="$(xray_clients_json_array_for xhttp reality)"
    grpc_clients="$(xray_clients_json_array_for grpc reality)"
    cdn_xhttp_clients="$(xray_clients_json_array_for xhttp cdn)"
    cdn_grpc_clients="$(xray_clients_json_array_for grpc cdn)"
    tmp="$(xray_mktemp "$(dirname "$XRAY_CONF_JSON")" ".json")" || return 1

    if xray_cdn_enabled; then
        cdn_block=$(cat <<CDN
    ,
    {
      "tag": "vless-cdn-xhttp",
      "listen": "0.0.0.0",
      "port": ${XRAY_CDN_PORT},
      "protocol": "vless",
      "settings": {
        "clients": ${cdn_xhttp_clients},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "xhttp",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{
            "certificateFile": "$(xray_json_escape "$XRAY_TLS_CERT")",
            "keyFile": "$(xray_json_escape "$XRAY_TLS_KEY")"
          }],
          "alpn": ["h2", "http/1.1"]
        },
        "xhttpSettings": {
          "path": "$(xray_json_escape "${XRAY_XHTTP_PATH}")"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    },
    {
      "tag": "vless-cdn-grpc",
      "listen": "0.0.0.0",
      "port": $(( XRAY_CDN_PORT + 1 )),
      "protocol": "vless",
      "settings": {
        "clients": ${cdn_grpc_clients},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "tls",
        "tlsSettings": {
          "certificates": [{
            "certificateFile": "$(xray_json_escape "$XRAY_TLS_CERT")",
            "keyFile": "$(xray_json_escape "$XRAY_TLS_KEY")"
          }],
          "alpn": ["h2"]
        },
        "grpcSettings": {
          "serviceName": "$(xray_json_escape "${XRAY_GRPC_SERVICE}")"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
CDN
)
    fi

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
    },
    {
      "tag": "vless-grpc",
      "listen": "0.0.0.0",
      "port": ${XRAY_GRPC_PORT},
      "protocol": "vless",
      "settings": {
        "clients": ${grpc_clients},
        "decryption": "none"
      },
      "streamSettings": {
        "network": "grpc",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "target": "$(xray_json_escape "$dest")",
          "xver": 0,
          "serverNames": ["$(xray_json_escape "$sni")"],
          "privateKey": "$(xray_json_escape "$XRAY_PRIVATE_KEY")",
          "shortIds": ["$(xray_json_escape "$XRAY_SHORT_ID")"]
        },
        "grpcSettings": {
          "serviceName": "$(xray_json_escape "${XRAY_GRPC_SERVICE}")"
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }${cdn_block}
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

# The upstream unit runs xray as nobody, which cannot read our 600-mode config
# nor the Let's Encrypt keys used in CDN mode. A drop-in leaves that unit intact.
xray_ensure_service_root() {
    local dir="/etc/systemd/system/xray.service.d"
    local file="$dir/20-freedom-root.conf"
    systemctl list-unit-files xray.service >/dev/null 2>&1 || return 0
    [[ -f "$file" ]] && return 0
    mkdir -p "$dir" 2>/dev/null || return 0
    cat > "$file" <<'EOF'
[Service]
User=root
Group=root
EOF
    systemctl daemon-reload 2>/dev/null || true
    return 0
}

xray_apply_config() {
    xray_render_server_config || return 1
    xray_ensure_service_root
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
    local host port sni sid pbk path svc enc_name
    host="$(xray_get_public_ip 2>/dev/null || true)"
    [[ -n "$host" ]] || host="${XRAY_ENDPOINT:-127.0.0.1}"
    sni="${XRAY_SNI}"
    sid="${XRAY_SHORT_ID}"
    pbk="${XRAY_PUBLIC_KEY}"
    path="$(xray_urlencode "${XRAY_XHTTP_PATH}")"
    svc="$(xray_urlencode "${XRAY_GRPC_SERVICE}")"
    enc_name="$(xray_urlencode "$name")"
    case "$proto" in
        vision)
            port="${XRAY_VISION_PORT}"
            printf 'vless://%s@%s:%s?encryption=none&flow=xtls-rprx-vision&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=tcp&spx=%%2F#%s\n' \
                "$uuid" "$host" "$port" "$(xray_urlencode "$sni")" "$pbk" "$sid" "$enc_name"
            ;;
        xhttp)
            port="${XRAY_XHTTP_PORT}"
            printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=xhttp&path=%s#%s\n' \
                "$uuid" "$host" "$port" "$(xray_urlencode "$sni")" "$pbk" "$sid" "$path" "$enc_name"
            ;;
        grpc)
            port="${XRAY_GRPC_PORT}"
            printf 'vless://%s@%s:%s?encryption=none&security=reality&sni=%s&fp=chrome&pbk=%s&sid=%s&type=grpc&serviceName=%s&mode=gun#%s\n' \
                "$uuid" "$host" "$port" "$(xray_urlencode "$sni")" "$pbk" "$sid" "$svc" "$enc_name"
            ;;
        cdn-xhttp)
            host="${XRAY_DOMAIN:-$host}"
            port="${XRAY_CDN_PORT}"
            printf 'vless://%s@%s:%s?encryption=none&security=tls&sni=%s&fp=chrome&type=xhttp&path=%s&alpn=h2%%2Chttp%%2F1.1#%s\n' \
                "$uuid" "$host" "$port" "$(xray_urlencode "$XRAY_DOMAIN")" "$path" "$enc_name"
            ;;
        cdn-grpc)
            host="${XRAY_DOMAIN:-$host}"
            port=$(( XRAY_CDN_PORT + 1 ))
            printf 'vless://%s@%s:%s?encryption=none&security=tls&sni=%s&fp=chrome&type=grpc&serviceName=%s&mode=gun&alpn=h2#%s\n' \
                "$uuid" "$host" "$port" "$(xray_urlencode "$XRAY_DOMAIN")" "$svc" "$enc_name"
            ;;
        *)
            return 1
            ;;
    esac
}

xray_write_client_files() {
    local name="$1" proto="$2" uuid="$3"
    local host port sni link tmp json_file meta_file
    host="$(xray_get_public_ip 2>/dev/null || true)"
    [[ -n "$host" ]] || host="${XRAY_ENDPOINT:-127.0.0.1}"
    sni="${XRAY_SNI}"
    case "$proto" in
        vision) port="${XRAY_VISION_PORT}" ;;
        xhttp) port="${XRAY_XHTTP_PORT}" ;;
        grpc) port="${XRAY_GRPC_PORT}" ;;
        cdn-xhttp) host="${XRAY_DOMAIN:-$host}"; port="${XRAY_CDN_PORT}"; sni="${XRAY_DOMAIN}" ;;
        cdn-grpc) host="${XRAY_DOMAIN:-$host}"; port=$(( XRAY_CDN_PORT + 1 )); sni="${XRAY_DOMAIN}" ;;
        *) return 1 ;;
    esac
    link="$(xray_vless_link "$proto" "$uuid" "$name")"
    json_file="$XRAY_CLIENTS_DIR/${name}.json"
    meta_file="$XRAY_CLIENTS_DIR/${name}.meta"
    tmp="$(xray_mktemp "$XRAY_CLIENTS_DIR")" || return 1

    case "$proto" in
        vision)
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
            ;;
        xhttp)
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
            ;;
        grpc)
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
    "network": "grpc",
    "security": "reality",
    "realitySettings": {
      "serverName": "$(xray_json_escape "$sni")",
      "fingerprint": "chrome",
      "password": "$(xray_json_escape "$XRAY_PUBLIC_KEY")",
      "shortId": "$(xray_json_escape "$XRAY_SHORT_ID")",
      "spiderX": "/"
    },
    "grpcSettings": {
      "serviceName": "$(xray_json_escape "${XRAY_GRPC_SERVICE}")"
    }
  }
}
EOF
            ;;
        cdn-xhttp)
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
    "security": "tls",
    "tlsSettings": {
      "serverName": "$(xray_json_escape "$sni")",
      "fingerprint": "chrome",
      "alpn": ["h2", "http/1.1"]
    },
    "xhttpSettings": {
      "path": "$(xray_json_escape "${XRAY_XHTTP_PATH}")"
    }
  }
}
EOF
            ;;
        cdn-grpc)
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
    "network": "grpc",
    "security": "tls",
    "tlsSettings": {
      "serverName": "$(xray_json_escape "$sni")",
      "fingerprint": "chrome",
      "alpn": ["h2"]
    },
    "grpcSettings": {
      "serviceName": "$(xray_json_escape "${XRAY_GRPC_SERVICE}")"
    }
  }
}
EOF
            ;;
    esac
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
        vision|xhttp|grpc) ;;
        cdn-xhttp|cdn-grpc)
            xray_cdn_enabled || { log_error "CDN/TLS mode is not configured"; return 1; }
            ;;
        *) log_error "Protocol must be vision|xhttp|grpc|cdn-xhttp|cdn-grpc"; return 1 ;;
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
    ufw allow "${XRAY_GRPC_PORT}/tcp" comment "Xray VLESS REALITY gRPC" >/dev/null 2>&1 || true
    if xray_cdn_enabled; then
        ufw allow "${XRAY_CDN_PORT}/tcp" comment "Xray CDN XHTTP TLS" >/dev/null 2>&1 || true
        ufw allow "$((XRAY_CDN_PORT + 1))/tcp" comment "Xray CDN gRPC TLS" >/dev/null 2>&1 || true
        ufw allow 80/tcp comment "HTTP ACME" >/dev/null 2>&1 || true
    fi
}

xray_maybe_close_ufw() {
    command -v ufw >/dev/null 2>&1 || return 0
    [[ -n "${XRAY_VISION_PORT:-}" ]] && ufw delete allow "${XRAY_VISION_PORT}/tcp" >/dev/null 2>&1 || true
    [[ -n "${XRAY_XHTTP_PORT:-}" ]] && ufw delete allow "${XRAY_XHTTP_PORT}/tcp" >/dev/null 2>&1 || true
    [[ -n "${XRAY_GRPC_PORT:-}" ]] && ufw delete allow "${XRAY_GRPC_PORT}/tcp" >/dev/null 2>&1 || true
    [[ -n "${XRAY_CDN_PORT:-}" ]] && ufw delete allow "${XRAY_CDN_PORT}/tcp" >/dev/null 2>&1 || true
    [[ -n "${XRAY_CDN_PORT:-}" ]] && ufw delete allow "$((XRAY_CDN_PORT + 1))/tcp" >/dev/null 2>&1 || true
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
        echo "gRPC TCP port: ${XRAY_GRPC_PORT}"
        echo "REALITY dest: ${XRAY_DEST}"
        echo "SNI: ${XRAY_SNI}"
        echo "XHTTP path: ${XRAY_XHTTP_PATH}"
        echo "gRPC service: ${XRAY_GRPC_SERVICE}"
        if xray_cdn_enabled; then
            echo "CDN/TLS: enabled"
            echo "CDN domain: ${XRAY_DOMAIN}"
            echo "CDN XHTTP port: ${XRAY_CDN_PORT}"
            echo "CDN gRPC port: $((XRAY_CDN_PORT + 1))"
            echo "TLS cert: ${XRAY_TLS_CERT}"
        else
            echo "CDN/TLS: disabled"
        fi
    else
        echo "Config: not found ($XRAY_CONFIG_FILE)"
    fi
    n="$(xray_list_clients | wc -l | tr -d ' ')"
    echo "Clients: ${n}"
    if command -v ss >/dev/null 2>&1 && [[ -n "${XRAY_VISION_PORT:-}" ]]; then
        ss -lnt | grep -E ":${XRAY_VISION_PORT}|:${XRAY_XHTTP_PORT}|:${XRAY_GRPC_PORT}|:${XRAY_CDN_PORT}" || true
    fi
}
