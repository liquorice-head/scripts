#!/usr/bin/env bash
set -euo pipefail

say() { printf '%s\n' "$*"; }
die() { say "ERROR: $*" >&2; exit 1; }

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  else
    command -v sudo >/dev/null 2>&1 || die "sudo is required"
    sudo "$@"
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"; }

prompt_default() {
  local q="$1" def="$2" ans=""
  read -r -p "${q} [${def}]: " ans || true
  [[ -z "${ans}" ]] && ans="${def}"
  printf '%s' "${ans}"
}

prompt_required() {
  local q="$1" ans=""
  while [[ -z "${ans}" ]]; do
    read -r -p "${q}: " ans || true
  done
  printf '%s' "${ans}"
}

yesno() {
  local q="$1" def="$2" ans=""
  while true; do
    read -r -p "${q} [${def}]: " ans || true
    [[ -z "${ans}" ]] && ans="${def}"
    case "${ans}" in
      Y|y|yes|YES) echo "Y"; return 0 ;;
      N|n|no|NO) echo "N"; return 0 ;;
    esac
    say "Please answer Y or N."
  done
}

is_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  (( $1 >= 1 && $1 <= 65535 )) || return 1
  return 0
}

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -H -lnt | awk '{print $4}' | grep -Eq "(^|:)$p$"
    return $?
  fi
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi
  return 1
}

choose_listen_port() {
  local desired="$1"
  local alt1="8443"
  local alt2="4433"

  if ! port_in_use "$desired"; then
    echo "$desired"
    return 0
  fi

  say "Port ${desired} is already in use."
  if ! port_in_use "$alt1"; then
    say "Auto-selecting free port: ${alt1}"
    echo "$alt1"
    return 0
  fi
  if ! port_in_use "$alt2"; then
    say "Auto-selecting free port: ${alt2}"
    echo "$alt2"
    return 0
  fi

  while true; do
    local p
    p="$(prompt_required "Enter a free TCP port (443/8443/4433 are busy)")"
    is_port "$p" || { say "Invalid port."; continue; }
    if port_in_use "$p"; then
      say "Port ${p} is still busy."
      continue
    fi
    echo "$p"
    return 0
  done
}

gen_secret_32hex() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    python3 -c 'import os; print(os.urandom(16).hex())'
  fi
}

hex_of_ascii() {
  echo -n "$1" | xxd -ps -c 256 | tr -d '\n'
}

escape_toml_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

detect_public_host() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://api.ipify.org 2>/dev/null || true
  fi
}

install_docker_official_ubuntu() {
  if command -v docker >/dev/null 2>&1; then
    say "Docker is already installed: $(docker --version || true)"
    return 0
  fi

  [[ -r /etc/os-release ]] || die "/etc/os-release not found"
  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    die "This installer supports Ubuntu only (detected ID='${ID:-unknown}')."
  fi

  say ""
  say "== Installing Docker (official apt repo) =="

  as_root apt update
  as_root apt install -y ca-certificates curl

  as_root install -m 0755 -d /etc/apt/keyrings
  as_root curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  as_root chmod a+r /etc/apt/keyrings/docker.asc

  local codename=""
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  [[ -n "${codename}" ]] || die "Unable to detect Ubuntu codename"

  as_root tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  as_root apt update
  as_root apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  as_root systemctl enable --now docker >/dev/null 2>&1 || true

  say "Docker installed: $(docker --version || true)"
  say "Docker Compose plugin: $(docker compose version || true)"

  local add_group
  add_group="$(yesno "Add current user '${SUDO_USER:-$USER}' to 'docker' group (docker without sudo)?" "Y")"
  if [[ "${add_group}" == "Y" ]]; then
    as_root groupadd -f docker
    as_root usermod -aG docker "${SUDO_USER:-$USER}"
    say "User added to docker group. Re-login is required."
  fi
}

apply_sysctl_tuning() {
  say "Applying sysctl tuning..."
  as_root tee /etc/sysctl.d/99-telemt.conf >/dev/null <<'EOF'
# Faster cleanup of half-closed TCP sessions
net.ipv4.tcp_fin_timeout=15

# Backlog
net.core.somaxconn=4096

# Higher global file limit
fs.file-max=2097152
EOF
  as_root sysctl --system >/dev/null
}

post_start_check() {
  local container_name="$1"

  say ""
  say "== Post-start check =="

  docker ps --filter "name=^/${container_name}$"

  local pid
  pid="$(docker inspect -f '{{.State.Pid}}' "${container_name}")"

  say ""
  say "Open files limit:"
  cat /proc/"$pid"/limits | grep -i "open files" || true

  say ""
  say "Current FD count:"
  ls -1 /proc/"$pid"/fd | wc -l || true

  say ""
  say "Top TCP states inside container netns:"
  if command -v nsenter >/dev/null 2>&1; then
    as_root nsenter -t "$pid" -n ss -Htan | awk '{print $1}' | sort | uniq -c | sort -nr | head || true
  else
    say "nsenter not found, skipping TCP states check."
  fi

  say ""
  say "Recent logs:"
  docker compose logs --tail=30 "${container_name}" || true
}

say ""
say "== Telemt Docker bootstrap =="
say ""

install_docker_official_ubuntu

need_cmd docker
need_cmd python3
need_cmd awk
need_cmd xxd

docker compose version >/dev/null 2>&1 || die "docker compose plugin is not available."

INSTALL_SYSCTL="$(yesno "Apply recommended sysctl tuning?" "Y")"
if [[ "${INSTALL_SYSCTL}" == "Y" ]]; then
  apply_sysctl_tuning
fi

BASE_DIR="$(prompt_default "Install directory" "/opt/docker/telemt")"
mkdir -p "${BASE_DIR}"

IMAGE="$(prompt_default "Container image" "whn0thacked/telemt-docker:latest")"
CONTAINER_NAME="$(prompt_default "Container name" "telemt")"
RUST_LOG="$(prompt_default "RUST_LOG (info/debug/trace)" "info")"

DESIRED_PORT="$(prompt_default "Desired listen port (preferred 443)" "443")"
is_port "${DESIRED_PORT}" || die "Invalid port: ${DESIRED_PORT}"
LISTEN_PORT="$(choose_listen_port "${DESIRED_PORT}")"

TLS_MODE="$(yesno "Enable Fake-TLS mode (SNI masking)?" "Y")"

TLS_DOMAIN=""
if [[ "${TLS_MODE}" == "Y" ]]; then
  TLS_DOMAIN="$(prompt_required "censorship.tls_domain (e.g. www.office.com)")"
fi

# Conservative defaults based on your real-world debugging
PREFER_IPV6="N"
USE_MIDDLE_PROXY="N"
FAST_MODE="Y"

CHANGE_ADVANCED="$(yesno "Change advanced defaults (prefer_ipv6=false, use_middle_proxy=false, fast_mode=true)?" "N")"
if [[ "${CHANGE_ADVANCED}" == "Y" ]]; then
  PREFER_IPV6="$(yesno "general.prefer_ipv6 ?" "N")"
  USE_MIDDLE_PROXY="$(yesno "general.use_middle_proxy ?" "N")"
  FAST_MODE="$(yesno "general.fast_mode ?" "Y")"
fi

LISTEN_IPV4="$(prompt_default "server.listen_addr_ipv4" "0.0.0.0")"

ENABLE_IPV6_LISTEN="$(yesno "Listen on IPv6 address :: ?" "N")"
LISTEN_IPV6=""
if [[ "${ENABLE_IPV6_LISTEN}" == "Y" ]]; then
  LISTEN_IPV6="::"
fi

USERNAME="$(prompt_default "MTProxy username label" "user")"
SECRET="$(prompt_default "User secret (32 hex chars). Leave empty to auto-generate" "")"
if [[ -z "${SECRET}" ]]; then
  SECRET="$(gen_secret_32hex)"
  say "Generated base secret: ${SECRET}"
fi
[[ "${#SECRET}" -eq 32 ]] || die "Secret must be 32 hex chars (got length ${#SECRET})."

DEFAULT_PUBLIC_HOST="$(detect_public_host)"
[[ -z "${DEFAULT_PUBLIC_HOST}" ]] && DEFAULT_PUBLIC_HOST="127.0.0.1"
PUBLIC_HOST="$(prompt_default "Public host for client links (IP or DNS)" "${DEFAULT_PUBLIC_HOST}")"

CLIENT_SECRET="${SECRET}"
if [[ "${TLS_MODE}" == "Y" ]]; then
  CLIENT_SECRET="ee${SECRET}$(hex_of_ascii "${TLS_DOMAIN}")"
fi

TELEMT_TOML="${BASE_DIR}/telemt.toml"
say ""
say "Writing ${TELEMT_TOML}"

cat > "${TELEMT_TOML}" <<EOF
[general]
prefer_ipv6 = $( [[ "${PREFER_IPV6}" == "Y" ]] && echo true || echo false )
fast_mode = $( [[ "${FAST_MODE}" == "Y" ]] && echo true || echo false )
use_middle_proxy = $( [[ "${USE_MIDDLE_PROXY}" == "Y" ]] && echo true || echo false )
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = $( [[ "${TLS_MODE}" == "Y" ]] && echo true || echo false )

[server]
port = ${LISTEN_PORT}
listen_addr_ipv4 = "$(escape_toml_str "${LISTEN_IPV4}")"
EOF

if [[ -n "${LISTEN_IPV6}" ]]; then
cat >> "${TELEMT_TOML}" <<EOF
listen_addr_ipv6 = "$(escape_toml_str "${LISTEN_IPV6}")"
EOF
fi

if [[ "${TLS_MODE}" == "Y" ]]; then
cat >> "${TELEMT_TOML}" <<EOF

[censorship]
tls_domain = "$(escape_toml_str "${TLS_DOMAIN}")"
mask = false
fake_cert_len = 2048
EOF
fi

cat >> "${TELEMT_TOML}" <<EOF

[access]
replay_check_len = 65536
replay_window_secs = 1800
ignore_time_skew = false

[access.users]
"$(escape_toml_str "${USERNAME}")" = "$(escape_toml_str "${SECRET}")"

[[upstreams]]
type = "direct"
enabled = true
weight = 10
EOF

# Important: container must be able to read config
chmod 0644 "${TELEMT_TOML}"
chmod 0755 "$(dirname "${TELEMT_TOML}")"

COMPOSE_YML="${BASE_DIR}/docker-compose.yml"
say "Writing ${COMPOSE_YML}"

cat > "${COMPOSE_YML}" <<EOF
services:
  ${CONTAINER_NAME}:
    image: ${IMAGE}
    container_name: ${CONTAINER_NAME}
    restart: unless-stopped

    environment:
      RUST_LOG: "${RUST_LOG}"

    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro

    ports:
      - "${LISTEN_PORT}:${LISTEN_PORT}/tcp"

    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576

    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m

    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

say ""
say "Starting stack..."
(
  cd "${BASE_DIR}"
  docker compose up -d --force-recreate
)

TG_LINK="tg://proxy?server=${PUBLIC_HOST}&port=${LISTEN_PORT}&secret=${CLIENT_SECRET}"
TME_LINK="https://t.me/proxy?server=${PUBLIC_HOST}&port=${LISTEN_PORT}&secret=${CLIENT_SECRET}"

say ""
say "Done."
say "Config dir: ${BASE_DIR}"
say "Listen: ${PUBLIC_HOST}:${LISTEN_PORT}"
say ""
say "Client links:"
say "  tg://  ${TG_LINK}"
say "  https:  ${TME_LINK}"

post_start_check "${CONTAINER_NAME}"
