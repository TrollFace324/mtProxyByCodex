#!/usr/bin/env bash
set -Eeuo pipefail

MTG_CONFIG="${MTG_CONFIG:-/etc/mtg.toml}"
MTG_BIN="${MTG_BIN:-/usr/local/bin/mtg}"
MTG_SERVICE="${MTG_SERVICE:-/etc/systemd/system/mtg.service}"
PURGE=0

usage() {
  cat <<'EOF'
Uninstall mtg Telegram MTProto proxy.

Usage:
  sudo bash uninstall.sh [--purge]

Options:
  --purge      Also remove /etc/mtg.toml.
  -h, --help   Show this help.
EOF
}

log() {
  printf '[mtproxy] %s\n' "$*"
}

die() {
  printf '[mtproxy] ERROR: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --purge)
      PURGE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  die "run as root"
fi

systemctl disable --now mtg >/dev/null 2>&1 || true
rm -f "$MTG_SERVICE"
systemctl daemon-reload >/dev/null 2>&1 || true
systemctl reset-failed mtg >/dev/null 2>&1 || true
rm -f "$MTG_BIN"

if [[ "$PURGE" == "1" ]]; then
  rm -f "$MTG_CONFIG"
  log "Removed service, binary, and config"
else
  log "Removed service and binary. Config kept at ${MTG_CONFIG}"
fi
