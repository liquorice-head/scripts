#!/usr/bin/env bash
set -euo pipefail

### helpers
say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

prompt_default() {
  local q="$1" d="$2" a=""
  read -r -p "$q [$d]: " a || true
  [[ -z "$a" ]] && a="$d"
  printf '%s' "$a"
}

prompt_required() {
  local q="$1" a=""
  while [[ -z "$a" ]]; do
    read -r -p "$q: " a || true
  done
  printf '%s' "$a"
}

yesno() {
  local q="$1" d="$2" a=""
  while true; do
    read -r -p "$q [$d]: " a || true
    [[ -z "$a" ]] && a="$d"
    case "$a" in
      Y|y) echo Y; return;;
      N|n) echo N; return;;
    esac
  done
}

is_port() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1>=1 && $1<=65535 )); }

port_in_use() {
  ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq ":$1$"
}

choose_port() {
  for p in "$1" 8443 4433; do
    if ! port_in_use "$p"; then
      echo "$p"; return
    fi
  done
  while true; do
    p="$(prompt_required "All common ports busy. Enter free port")"
    is_port "$p" && ! port_in_use "$p" && echo "$p" && return
  done
}

gen_secret() {
  openssl rand -hex 16 2>/dev/null || python3 - <<'EOF'
import os; print(os.urandom(16).hex())
EOF
}

hex() { echo -n "$1" | xxd -ps -c 256 | tr -d '\n'; }

### docker install (official ubuntu method)
install_docker() {
  if command -v docker >/dev/null; then
    say "Docker already installed"
    return
  fi

  . /etc/os-release
  [[ "$ID" == "ubuntu" ]] || die "Ubuntu only"

  say "Installing Docker (official repo)…"
  as_root apt update
  as_root apt install -y ca-certificates curl
  as_root install -m 0755 -d /etc/apt/keyrings
  as_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  as_root chmod a+r /etc/apt/keyrings/docker.asc

  as_root tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  as_root apt update
  as_root apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  as_root systemctl enable --now docker

  if [[ "$(yesno "Add user to docker group?" Y)" == "Y" ]]; then
    as_root usermod -aG docker "${SUDO_USER:-$USER}"
    say "Re-login required for docker group"
  fi
}

### start
say "=== telemt bootstrap ==="

install_docker
need_cmd docker
need_cmd docker-compose || true

BASE_DIR="$(prompt_default "Install dir" "/opt/docker/telemt")"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

IMAGE="whn0thacked/telemt-docker:latest"

DESIRED_PORT="$(prompt_default "Preferred port" "443")"
LISTEN_PORT="$(choose_port "$DESIRED_PORT")"
say "Using port: $LISTEN_PORT"

USE_TLS="$(yesno "Enable Fake-TLS (SNI masking)?" Y)"

if [[ "$USE_TLS" == "Y" ]]; then
  TLS_DOMAIN="$(prompt_required "SNI domain (e.g. www.cloudflare.com)")"
fi

USERNAME="$(prompt_default "Username label" "user")"
SECRET="$(prompt_default "Secret (empty = auto)" "")"
[[ -z "$SECRET" ]] && SECRET="$(gen_secret)"

PUBLIC_HOST="$(prompt_default "Public IP or DNS for links" "$(curl -fsSL https://api.ipify.org || echo 127.0.0.1)")"

CLIENT_SECRET="$SECRET"
[[ "$USE_TLS" == "Y" ]] && CLIENT_SECRET="ee${SECRET}$(hex "$TLS_DOMAIN")"

### write config
cat > telemt.toml <<EOF
[general]
prefer_ipv6 = true
fast_mode = true
use_middle_proxy = true

[general.modes]
tls = $( [[ "$USE_TLS" == "Y" ]] && echo true || echo false )

[server]
port = $LISTEN_PORT
listen_addr_ipv4 = "0.0.0.0"
listen_addr_ipv6 = "::"

$( [[ "$USE_TLS" == "Y" ]] && cat <<TLS
[censorship]
tls_domain = "$TLS_DOMAIN"
mask = true
mask_port = 443
mask_host = "$TLS_DOMAIN"
fake_cert_len = 2048
TLS
)

[access.users]
"$USERNAME" = "$SECRET"

[[upstreams]]
type = "direct"
enabled = true
EOF

### permissions fix (IMPORTANT)
chmod 0644 telemt.toml
chmod 0755 "$BASE_DIR"

### compose
cat > docker-compose.yml <<EOF
services:
  telemt:
    image: $IMAGE
    container_name: telemt
    restart: unless-stopped
    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro
    ports:
      - "$LISTEN_PORT:$LISTEN_PORT/tcp"
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE]
    read_only: true
    tmpfs:
      - /tmp
EOF

docker compose up -d --force-recreate

### output links
say ""
say "=== READY ==="
say "Server: $PUBLIC_HOST:$LISTEN_PORT"
say ""
say "Client links:"
say "tg://proxy?server=$PUBLIC_HOST&port=$LISTEN_PORT&secret=$CLIENT_SECRET"
say "https://t.me/proxy?server=$PUBLIC_HOST&port=$LISTEN_PORT&secret=$CLIENT_SECRET"
say ""
say "Done."