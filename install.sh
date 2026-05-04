#!/usr/bin/env bash
set -Eeuo pipefail

MTG_REPO="${MTG_REPO:-9seconds/mtg}"
MTG_VERSION="${MTG_VERSION:-latest}"
MTG_PORT="${MTG_PORT:-443}"
MTG_BIND="${MTG_BIND:-}"
MTG_FAKE_TLS_HOST="${MTG_FAKE_TLS_HOST:-}"
MTG_SECRET="${MTG_SECRET:-}"
MTG_ROTATE_SECRET="${MTG_ROTATE_SECRET:-0}"
MTG_IP_VERSION="${MTG_IP_VERSION:-}"
MTG_PREFER_IP="${MTG_PREFER_IP:-}"
MTG_PUBLIC_IPV4="${MTG_PUBLIC_IPV4:-}"
MTG_PUBLIC_IPV6="${MTG_PUBLIC_IPV6:-}"
MTG_CONFIG="${MTG_CONFIG:-/etc/mtg.toml}"
MTG_BIN="${MTG_BIN:-/usr/local/bin/mtg}"
MTG_SERVICE="${MTG_SERVICE:-/etc/systemd/system/mtg.service}"
MTG_NO_FIREWALL="${MTG_NO_FIREWALL:-0}"
MTG_FORCE="${MTG_FORCE:-0}"

usage() {
  cat <<'EOF'
Install mtg Telegram MTProto proxy.

Usage:
  sudo bash install.sh [options]

Options:
  --port PORT          Public TCP port to listen on. Default: 443
  --bind ADDR:PORT     Full bind address. Default: 0.0.0.0:<port>
  --host HOSTNAME      FakeTLS hostname for generated secret. Default: <public-ip>.sslip.io
  --secret SECRET      Use existing mtg secret instead of generating a new one.
  --rotate-secret      Generate a new secret even if /etc/mtg.toml already exists.
  --ip-version MODE    Ask/use public IP version: ipv4 or ipv6. Default: prompt, then ipv4
  --prefer-ip MODE     Advanced Telegram DC IP mode. Default: derived from --ip-version
  --public-ipv4 IP     Public IPv4 for access links and doctor checks. Default: auto-detect
  --public-ipv6 IP     Public IPv6 for access links and doctor checks. Default: auto-detect
  --version VERSION    mtg version/tag to install, for example v2.2.8. Default: latest
  --no-firewall        Do not modify ufw/firewalld rules.
  --force              Skip local port occupation pre-check.
  -h, --help           Show this help.

Environment variables:
  MTG_PORT, MTG_BIND, MTG_FAKE_TLS_HOST, MTG_SECRET, MTG_VERSION,
  MTG_ROTATE_SECRET=1, MTG_IP_VERSION, MTG_PREFER_IP,
  MTG_PUBLIC_IPV4, MTG_PUBLIC_IPV6,
  MTG_NO_FIREWALL=1, MTG_FORCE=1
EOF
}

log() {
  printf '[mtproxy] %s\n' "$*"
}

die() {
  printf '[mtproxy] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    die "run as root, for example: sudo bash install.sh"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        [[ $# -ge 2 ]] || die "--port requires a value"
        MTG_PORT="$2"
        shift 2
        ;;
      --bind)
        [[ $# -ge 2 ]] || die "--bind requires a value"
        MTG_BIND="$2"
        shift 2
        ;;
      --host)
        [[ $# -ge 2 ]] || die "--host requires a value"
        MTG_FAKE_TLS_HOST="$2"
        shift 2
        ;;
      --secret)
        [[ $# -ge 2 ]] || die "--secret requires a value"
        MTG_SECRET="$2"
        shift 2
        ;;
      --rotate-secret)
        MTG_ROTATE_SECRET=1
        shift
        ;;
      --ip-version|--ip)
        [[ $# -ge 2 ]] || die "$1 requires a value"
        MTG_IP_VERSION="$2"
        shift 2
        ;;
      --prefer-ip)
        [[ $# -ge 2 ]] || die "--prefer-ip requires a value"
        MTG_PREFER_IP="$2"
        shift 2
        ;;
      --public-ipv4)
        [[ $# -ge 2 ]] || die "--public-ipv4 requires a value"
        MTG_PUBLIC_IPV4="$2"
        shift 2
        ;;
      --public-ipv6)
        [[ $# -ge 2 ]] || die "--public-ipv6 requires a value"
        MTG_PUBLIC_IPV6="$2"
        shift 2
        ;;
      --version)
        [[ $# -ge 2 ]] || die "--version requires a value"
        MTG_VERSION="$2"
        shift 2
        ;;
      --no-firewall)
        MTG_NO_FIREWALL=1
        shift
        ;;
      --force)
        MTG_FORCE=1
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
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'arm64' ;;
    armv7l|armv7*) printf 'armv7' ;;
    armv6l|armv6*) printf 'armv6' ;;
    i386|i686) printf '386' ;;
    *) die "unsupported CPU architecture: $(uname -m)" ;;
  esac
}

extract_port_from_bind() {
  local bind="$1"
  bind="${bind##*:}"
  bind="${bind%]}"
  printf '%s' "$bind"
}

validate_port() {
  [[ "$MTG_PORT" =~ ^[0-9]+$ ]] || die "port must be a number: $MTG_PORT"
  (( MTG_PORT >= 1 && MTG_PORT <= 65535 )) || die "port must be in range 1..65535: $MTG_PORT"
}

prompt_ip_version() {
  if [[ -n "$MTG_IP_VERSION" || -n "$MTG_PREFER_IP" ]]; then
    return
  fi

  if [[ -t 0 && -t 1 ]]; then
    echo
    echo "Choose proxy IP version:"
    echo "  1) IPv4 (recommended)"
    echo "  2) IPv6"
    read -r -p "Select [1]: " MTG_IP_VERSION || true
  fi

  MTG_IP_VERSION="${MTG_IP_VERSION:-ipv4}"
  case "${MTG_IP_VERSION,,}" in
    1) MTG_IP_VERSION="ipv4" ;;
    2) MTG_IP_VERSION="ipv6" ;;
  esac
}

normalize_ip_settings() {
  local mode

  prompt_ip_version

  if [[ -n "$MTG_PREFER_IP" ]]; then
    mode="${MTG_PREFER_IP,,}"
  else
    mode="${MTG_IP_VERSION,,}"
  fi

  case "$mode" in
    1|4|ip4|ipv4|only-ipv4)
      MTG_IP_VERSION="ipv4"
      MTG_PREFER_IP="only-ipv4"
      ;;
    2|6|ip6|ipv6|only-ipv6)
      MTG_IP_VERSION="ipv6"
      MTG_PREFER_IP="only-ipv6"
      ;;
    prefer4|prefer-ipv4)
      MTG_IP_VERSION="ipv4"
      MTG_PREFER_IP="prefer-ipv4"
      ;;
    prefer6|prefer-ipv6)
      MTG_IP_VERSION="ipv6"
      MTG_PREFER_IP="prefer-ipv6"
      ;;
    *)
      die "unsupported IP mode: ${mode}. Use ipv4, ipv6, prefer-ipv4, prefer-ipv6, only-ipv4, or only-ipv6."
      ;;
  esac
}

install_dependencies() {
  local missing=()
  local cmd

  for cmd in curl tar sha256sum systemctl sed grep awk find install ss; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done

  if [[ "${#missing[@]}" -eq 0 ]]; then
    return
  fi

  log "Installing required packages: ${missing[*]}"
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y ca-certificates curl tar coreutils systemd sed grep gawk findutils iproute2
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y ca-certificates curl tar coreutils systemd sed grep gawk findutils iproute
  elif command -v yum >/dev/null 2>&1; then
    yum install -y ca-certificates curl tar coreutils systemd sed grep gawk findutils iproute
  else
    die "unsupported package manager. Install manually: ${missing[*]}"
  fi

  command -v systemctl >/dev/null 2>&1 || die "systemd is required"
}

resolve_version_tag() {
  if [[ "$MTG_VERSION" == "latest" ]]; then
    curl -fsSL -H 'User-Agent: mtproxy-installer' \
      "https://api.github.com/repos/${MTG_REPO}/releases/latest" |
      sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' |
      head -n 1
  elif [[ "$MTG_VERSION" == v* ]]; then
    printf '%s' "$MTG_VERSION"
  else
    printf 'v%s' "$MTG_VERSION"
  fi
}

check_port_available() {
  if [[ "$MTG_FORCE" == "1" ]]; then
    return
  fi

  if systemctl is-active --quiet mtg 2>/dev/null; then
    return
  fi

  if ss -ltnH "sport = :${MTG_PORT}" 2>/dev/null | grep -q .; then
    die "port ${MTG_PORT}/tcp is already in use. Choose another --port or use --force if you know what you are doing."
  fi
}

backup_file() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cp -a "$path" "${path}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

read_existing_secret() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  sed -n 's/^[[:space:]]*secret[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$path" | head -n 1
}

detect_public_ipv4() {
  local ip
  ip="$(curl -4 -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -4 -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    printf '%s' "$ip"
  fi
  return 0
}

detect_public_ipv6() {
  local ip
  ip="$(curl -6 -fsS --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="$(curl -6 -fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)"
  fi
  if [[ "$ip" == *:* && "$ip" =~ ^[0-9A-Fa-f:.]+$ ]]; then
    printf '%s' "$ip"
  fi
  return 0
}

sslip_host_for_ipv6() {
  local ip="${1,,}"
  ip="${ip//:/-}"
  printf '%s.sslip.io' "$ip"
}

download_and_install_mtg() {
  local tag version arch asset checksums base_url tmpdir mtg_path

  tag="$(resolve_version_tag)"
  [[ -n "$tag" ]] || die "cannot resolve mtg release tag"

  version="${tag#v}"
  arch="$(detect_arch)"
  asset="mtg-${version}-linux-${arch}.tar.gz"
  checksums="mtg-${version}-checksums.txt"
  base_url="https://github.com/${MTG_REPO}/releases/download/${tag}"
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  log "Downloading ${MTG_REPO} ${tag} for linux-${arch}"
  curl -fL --retry 3 -o "${tmpdir}/${asset}" "${base_url}/${asset}"
  curl -fL --retry 3 -o "${tmpdir}/${checksums}" "${base_url}/${checksums}"

  grep -E "[[:space:]]${asset}$" "${tmpdir}/${checksums}" > "${tmpdir}/${asset}.sha256" ||
    die "checksum for ${asset} not found"
  (cd "$tmpdir" && sha256sum -c "${asset}.sha256")

  tar -xzf "${tmpdir}/${asset}" -C "$tmpdir"
  mtg_path="$(find "$tmpdir" -type f -name mtg | head -n 1)"
  [[ -n "$mtg_path" ]] || die "mtg binary not found in release archive"

  install -m 0755 "$mtg_path" "$MTG_BIN"
  log "Installed $("$MTG_BIN" --version | head -n 1)"
}

write_config() {
  normalize_ip_settings

  if [[ -z "$MTG_BIND" ]]; then
    if [[ "$MTG_IP_VERSION" == "ipv6" ]]; then
      MTG_BIND="[::]:${MTG_PORT}"
    else
      MTG_BIND="0.0.0.0:${MTG_PORT}"
    fi
  else
    MTG_PORT="$(extract_port_from_bind "$MTG_BIND")"
    validate_port
  fi

  [[ "$MTG_SECRET" != *\"* ]] || die "secret must not contain double quotes"
  [[ "$MTG_FAKE_TLS_HOST" != *\"* ]] || die "hostname must not contain double quotes"
  [[ "$MTG_PREFER_IP" != *\"* ]] || die "prefer-ip must not contain double quotes"
  [[ "$MTG_PUBLIC_IPV4" != *\"* ]] || die "public IPv4 must not contain double quotes"
  [[ "$MTG_PUBLIC_IPV6" != *\"* ]] || die "public IPv6 must not contain double quotes"

  if [[ "$MTG_IP_VERSION" == "ipv6" && -z "$MTG_PUBLIC_IPV6" ]]; then
    MTG_PUBLIC_IPV6="$(detect_public_ipv6)"
    if [[ -n "$MTG_PUBLIC_IPV6" ]]; then
      log "Detected public IPv6: ${MTG_PUBLIC_IPV6}"
    else
      log "Could not auto-detect public IPv6; pass --public-ipv6 if mtg access links need it"
    fi
  elif [[ "$MTG_IP_VERSION" == "ipv4" && -z "$MTG_PUBLIC_IPV4" ]]; then
    MTG_PUBLIC_IPV4="$(detect_public_ipv4)"
    if [[ -n "$MTG_PUBLIC_IPV4" ]]; then
      log "Detected public IPv4: ${MTG_PUBLIC_IPV4}"
    else
      log "Could not auto-detect public IPv4; pass --public-ipv4 if mtg access links need it"
    fi
  fi

  if [[ -z "$MTG_SECRET" && "$MTG_ROTATE_SECRET" != "1" ]]; then
    MTG_SECRET="$(read_existing_secret "$MTG_CONFIG")"
    if [[ -n "$MTG_SECRET" ]]; then
      log "Keeping existing secret from ${MTG_CONFIG}"
    fi
  fi

  if [[ -z "$MTG_SECRET" ]]; then
    if [[ -z "$MTG_FAKE_TLS_HOST" ]]; then
      if [[ "$MTG_IP_VERSION" == "ipv6" && -n "$MTG_PUBLIC_IPV6" ]]; then
        MTG_FAKE_TLS_HOST="$(sslip_host_for_ipv6 "$MTG_PUBLIC_IPV6")"
      elif [[ -n "$MTG_PUBLIC_IPV4" ]]; then
        MTG_FAKE_TLS_HOST="${MTG_PUBLIC_IPV4}.sslip.io"
      else
        MTG_FAKE_TLS_HOST="www.microsoft.com"
      fi
    fi
    log "Generating FakeTLS secret for ${MTG_FAKE_TLS_HOST}"
    MTG_SECRET="$("$MTG_BIN" generate-secret --hex "$MTG_FAKE_TLS_HOST")"
  fi

  backup_file "$MTG_CONFIG"
  cat > "$MTG_CONFIG" <<EOF
secret = "$MTG_SECRET"
bind-to = "$MTG_BIND"
prefer-ip = "$MTG_PREFER_IP"
EOF
  if [[ -n "$MTG_PUBLIC_IPV4" ]]; then
    printf 'public-ipv4 = "%s"\n' "$MTG_PUBLIC_IPV4" >> "$MTG_CONFIG"
  fi
  if [[ -n "$MTG_PUBLIC_IPV6" ]]; then
    printf 'public-ipv6 = "%s"\n' "$MTG_PUBLIC_IPV6" >> "$MTG_CONFIG"
  fi
  chmod 0644 "$MTG_CONFIG"
}

write_systemd_service() {
  backup_file "$MTG_SERVICE"
  cat > "$MTG_SERVICE" <<EOF
[Unit]
Description=mtg - Telegram MTProto proxy server
Documentation=https://github.com/${MTG_REPO}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${MTG_BIN} run ${MTG_CONFIG}
Restart=always
RestartSec=3
DynamicUser=true
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
}

open_firewall() {
  if [[ "$MTG_NO_FIREWALL" == "1" ]]; then
    log "Skipping firewall changes"
    return
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status | grep -qi '^Status: active'; then
    log "Opening ${MTG_PORT}/tcp in ufw"
    ufw allow "${MTG_PORT}/tcp" >/dev/null
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    log "Opening ${MTG_PORT}/tcp in firewalld"
    firewall-cmd --permanent --add-port="${MTG_PORT}/tcp" >/dev/null
    firewall-cmd --reload >/dev/null
  else
    log "No active ufw/firewalld detected; provider firewall may still need port ${MTG_PORT}/tcp opened manually"
  fi
}

start_service() {
  systemctl daemon-reload
  systemctl enable mtg >/dev/null
  systemctl restart mtg
  sleep 2

  if ! systemctl is-active --quiet mtg; then
    journalctl -u mtg -n 80 --no-pager >&2 || true
    die "mtg service failed to start"
  fi
}

print_result() {
  echo
  log "Installation complete"
  log "Service: systemctl status mtg"
  log "Logs:    journalctl -u mtg -f"
  echo
  "$MTG_BIN" access "$MTG_CONFIG" || {
    log "Could not render access links automatically. Config is stored at ${MTG_CONFIG}."
  }
}

main() {
  parse_args "$@"
  require_root

  if [[ "$(uname -s)" != "Linux" ]]; then
    die "Linux is required"
  fi

  if [[ -n "$MTG_BIND" ]]; then
    MTG_PORT="$(extract_port_from_bind "$MTG_BIND")"
  fi
  validate_port

  install_dependencies
  check_port_available
  download_and_install_mtg
  write_config
  write_systemd_service
  open_firewall
  start_service
  print_result
}

main "$@"
