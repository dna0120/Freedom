#!/bin/bash

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: Bash >= 4.0 required (current: ${BASH_VERSION})" >&2; exit 1
fi

# ==============================================================================
# Xray (VLESS + REALITY / CDN) peer management
# Author: @dna0120
# Version: 5.21.2
# Repository: https://github.com/dna0120/Freedom
# ==============================================================================

SCRIPT_VERSION="5.21.2"
set -o pipefail
XRAY_DIR="/root/xray"
XRAY_CONFIG_FILE="$XRAY_DIR/xraysetup_cfg.init"
XRAY_CLIENTS_DIR="$XRAY_DIR/clients"
XRAY_CONF_JSON="/usr/local/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
COMMON_SCRIPT_PATH="$XRAY_DIR/xray_common.sh"
LOG_FILE="$XRAY_DIR/manage_xray.log"
NO_COLOR=0
AUTO_YES=0
COMMAND=""
CLIENT_NAME=""
CLIENT_PROTO="vision"

_manage_cleaned=0
_manage_cleanup() {
    [[ "$_manage_cleaned" -eq 1 ]] && return 0
    _manage_cleaned=1
    type _xray_cleanup &>/dev/null && _xray_cleanup
}
_manage_on_signal() {
    _manage_cleanup
    exit "$1"
}
trap _manage_cleanup EXIT
trap '_manage_on_signal 130' INT
trap '_manage_on_signal 143' TERM

log_msg() {
    local type="$1" msg="$2"
    local ts entry color_start="" color_end=""
    ts=$(date +'%F %T')
    entry="[$ts] $type: $msg"
    if [[ "$NO_COLOR" -eq 0 ]]; then
        color_end="\033[0m"
        case "$type" in
            INFO)  color_start="\033[0;32m" ;;
            WARN)  color_start="\033[0;33m" ;;
            ERROR) color_start="\033[1;31m" ;;
            *)     color_start=""; color_end="" ;;
        esac
    fi
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    echo "$entry" >> "$LOG_FILE" 2>/dev/null || true
    if [[ "$type" == "ERROR" || "$type" == "WARN" ]]; then
        printf "${color_start}%s${color_end}\n" "$entry" >&2
    else
        printf "${color_start}%s${color_end}\n" "$entry"
    fi
}
log() { log_msg INFO "$1"; }
log_warn() { log_msg WARN "$1"; }
log_error() { log_msg ERROR "$1"; }
die() { log_error "$1"; exit 1; }

usage() {
    cat <<EOF
Usage: sudo bash manage_xray.sh <command> [args]

Commands:
  add <name> [--proto=vision|xhttp|grpc|cdn-xhttp|cdn-grpc]
  list
  remove <name>
  status|check
  reconfigure

Options:
  -y, --yes     Skip confirmations
  --no-color    Disable colors
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        add|list|remove|status|check|reconfigure)
            COMMAND="$1" ;;
        --proto=*) CLIENT_PROTO="${1#*=}" ;;
        --yes|-y) AUTO_YES=1 ;;
        --no-color) NO_COLOR=1 ;;
        --help|-h) usage; exit 0 ;;
        -*)
            echo "Unknown option: $1" >&2
            usage
            exit 1 ;;
        *)
            if [[ -z "$CLIENT_NAME" ]]; then
                CLIENT_NAME="$1"
            else
                echo "Unexpected argument: $1" >&2
                exit 1
            fi
            ;;
    esac
    shift
done

[[ -n "$COMMAND" ]] || { usage; exit 1; }
if [[ "$(id -u)" -ne 0 ]]; then
    die "Run as root (sudo bash $0)."
fi

if [[ ! -f "$COMMON_SCRIPT_PATH" ]]; then
    die "xray_common.sh not found at $COMMON_SCRIPT_PATH"
fi
# shellcheck source=/dev/null
source "$COMMON_SCRIPT_PATH"

case "$COMMAND" in
    add)
        [[ -n "$CLIENT_NAME" ]] || die "Usage: manage_xray.sh add <name> [--proto=...]"
        case "$CLIENT_PROTO" in
            vision|1) CLIENT_PROTO="vision" ;;
            xhttp|2) CLIENT_PROTO="xhttp" ;;
            grpc|3) CLIENT_PROTO="grpc" ;;
            cdn-xhttp|4) CLIENT_PROTO="cdn-xhttp" ;;
            cdn-grpc|5) CLIENT_PROTO="cdn-grpc" ;;
            *) die "Invalid --proto='$CLIENT_PROTO' (vision|xhttp|grpc|cdn-xhttp|cdn-grpc)" ;;
        esac
        mkdir -p "$XRAY_CLIENTS_DIR"
        exec 9>"$XRAY_DIR/.xray_config.lock"
        flock -w 60 9 || die "Could not lock $XRAY_DIR/.xray_config.lock"
        # Do not run xray_add_client on the left side of a pipeline: that puts
        # config rendering/restart in a subshell and can leave the persisted
        # server config without the newly-created client. The URL is already
        # written atomically to the client's .url file.
        xray_add_client "$CLIENT_NAME" "$CLIENT_PROTO" >/dev/null \
            || die "Failed to add client '$CLIENT_NAME'"
        link="$(tr -d '\r\n' < "$XRAY_CLIENTS_DIR/${CLIENT_NAME}.url" 2>/dev/null)"
        [[ -n "$link" ]] || die "Failed to add client '$CLIENT_NAME'"
        flock -u 9
        echo ""
        echo "Protocol: $CLIENT_PROTO"
        echo "UUID:     $(awk -F= '/XRAY_CLIENT_UUID/{print $2}' "$XRAY_CLIENTS_DIR/${CLIENT_NAME}.meta")"
        echo "JSON:     $XRAY_CLIENTS_DIR/${CLIENT_NAME}.json"
        echo "Link:"
        echo "$link"
        echo ""
        if command -v qrencode >/dev/null 2>&1; then
            echo "$link" | qrencode -t ansiutf8 -l L || true
            echo "$link" | qrencode -t png -o "$XRAY_CLIENTS_DIR/${CLIENT_NAME}.png" 2>/dev/null || true
            [[ -f "$XRAY_CLIENTS_DIR/${CLIENT_NAME}.png" ]] && echo "QR image: $XRAY_CLIENTS_DIR/${CLIENT_NAME}.png"
        fi
        ;;
    list)
        echo "NAME            PROTO       UUID"
        echo "--------------  ----------  ------------------------------------"
        xray_list_clients | while IFS=$'\t' read -r n p u; do
            printf '%-14s  %-10s  %s\n' "$n" "$p" "$u"
        done
        ;;
    remove)
        [[ -n "$CLIENT_NAME" ]] || die "Usage: manage_xray.sh remove <name>"
        if [[ "$AUTO_YES" -eq 0 ]]; then
            read -rp "Revoke Xray client '$CLIENT_NAME'? [y/N]: " confirm < /dev/tty
            [[ "$confirm" =~ ^[Yy] ]] || { echo "Cancelled."; exit 1; }
        fi
        exec 9>"$XRAY_DIR/.xray_config.lock"
        flock -w 60 9 || die "Could not lock $XRAY_DIR/.xray_config.lock"
        xray_remove_client "$CLIENT_NAME" || die "Failed to revoke '$CLIENT_NAME'"
        flock -u 9
        log "Revoked Xray client '$CLIENT_NAME'"
        ;;
    status|check)
        xray_status
        ;;
    reconfigure)
        xray_load_config || die "Xray is not configured"
        exec 9>"$XRAY_DIR/.xray_config.lock"
        flock -w 60 9 || die "Could not lock $XRAY_DIR/.xray_config.lock"
        xray_apply_config || die "Failed to apply Xray config"
        flock -u 9
        log "Xray config re-applied."
        ;;
    *)
        usage
        exit 1
        ;;
esac
exit 0
