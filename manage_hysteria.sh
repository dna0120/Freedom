#!/bin/bash

if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    echo "ERROR: Bash >= 4.0 required (current: ${BASH_VERSION})" >&2; exit 1
fi

# ==============================================================================
# Hysteria2 peer management
# Author: @dna0120
# Version: 5.21.2
# Repository: https://github.com/dna0120/Freedom
# ==============================================================================

SCRIPT_VERSION="5.21.2"
set -o pipefail
HY2_DIR="/root/hysteria"
HY2_CONFIG_FILE="$HY2_DIR/hy2setup_cfg.init"
HY2_CLIENTS_DIR="$HY2_DIR/clients"
HY2_SERVER_YAML="/etc/hysteria/config.yaml"
HY2_BIN="/usr/local/bin/hysteria"
COMMON_SCRIPT_PATH="$HY2_DIR/hysteria_common.sh"
LOG_FILE="$HY2_DIR/manage_hysteria.log"
NO_COLOR=0
AUTO_YES=0
COMMAND=""
CLIENT_NAME=""

_manage_cleaned=0
_manage_cleanup() {
    [[ "$_manage_cleaned" -eq 1 ]] && return 0
    _manage_cleaned=1
    type _hy2_cleanup &>/dev/null && _hy2_cleanup
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
Usage: sudo bash manage_hysteria.sh <command> [args]

Commands:
  add <name>       Add a Hysteria2 client (userpass)
  list             List clients
  remove <name>    Revoke a client
  status|check     Show Hysteria2 status
  reconfigure      Re-apply server config

Options:
  -y, --yes        Skip confirmations
  --no-color       Disable colors
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        add|list|remove|status|check|reconfigure)
            COMMAND="$1" ;;
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
    die "hysteria_common.sh not found at $COMMON_SCRIPT_PATH"
fi
# shellcheck source=/dev/null
source "$COMMON_SCRIPT_PATH"

case "$COMMAND" in
    add)
        [[ -n "$CLIENT_NAME" ]] || die "Usage: manage_hysteria.sh add <name>"
        mkdir -p "$HY2_CLIENTS_DIR"
        exec 9>"$HY2_DIR/.hy2_config.lock"
        flock -w 60 9 || die "Could not lock $HY2_DIR/.hy2_config.lock"
        link="$(hy2_add_client "$CLIENT_NAME" | grep '^hysteria2://' | tail -n1)" \
            || die "Failed to add client '$CLIENT_NAME'"
        [[ -n "$link" ]] || die "Failed to add client '$CLIENT_NAME'"
        flock -u 9
        echo ""
        echo "User: $(awk -F= '/HY2_CLIENT_USER/{print $2}' "$HY2_CLIENTS_DIR/${CLIENT_NAME}.meta")"
        echo "YAML: $HY2_CLIENTS_DIR/${CLIENT_NAME}.yaml"
        echo "Link:"
        echo "$link"
        echo ""
        if command -v qrencode >/dev/null 2>&1; then
            echo "$link" | qrencode -t ansiutf8 -l L || true
            echo "$link" | qrencode -t png -o "$HY2_CLIENTS_DIR/${CLIENT_NAME}.png" 2>/dev/null || true
            [[ -f "$HY2_CLIENTS_DIR/${CLIENT_NAME}.png" ]] && echo "QR image: $HY2_CLIENTS_DIR/${CLIENT_NAME}.png"
        fi
        ;;
    list)
        echo "NAME            USER"
        echo "--------------  ---------------"
        hy2_list_clients | while IFS=$'\t' read -r n u; do
            printf '%-14s  %s\n' "$n" "$u"
        done
        ;;
    remove)
        [[ -n "$CLIENT_NAME" ]] || die "Usage: manage_hysteria.sh remove <name>"
        if [[ "$AUTO_YES" -eq 0 ]]; then
            read -rp "Revoke Hysteria2 client '$CLIENT_NAME'? [y/N]: " confirm < /dev/tty
            [[ "$confirm" =~ ^[Yy] ]] || { echo "Cancelled."; exit 1; }
        fi
        exec 9>"$HY2_DIR/.hy2_config.lock"
        flock -w 60 9 || die "Could not lock $HY2_DIR/.hy2_config.lock"
        hy2_remove_client "$CLIENT_NAME" || die "Failed to revoke '$CLIENT_NAME'"
        flock -u 9
        log "Revoked Hysteria2 client '$CLIENT_NAME'"
        ;;
    status|check)
        hy2_status
        ;;
    reconfigure)
        hy2_load_config || die "Hysteria2 is not configured"
        exec 9>"$HY2_DIR/.hy2_config.lock"
        flock -w 60 9 || die "Could not lock $HY2_DIR/.hy2_config.lock"
        hy2_apply_config || die "Failed to apply Hysteria2 config"
        flock -u 9
        log "Hysteria2 config re-applied."
        ;;
    *)
        usage
        exit 1
        ;;
esac
exit 0
