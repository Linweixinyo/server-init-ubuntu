#!/usr/bin/env bash
#
# Ubuntu 24.04 快速初始化脚本
#
# 保留的初始化内容：
# - 更新系统并安装常用工具、Nginx、Docker
# - 配置 chrony、UFW、sysctl、journald
# - 配置 Docker daemon、日志轮转和定时清理
# - 配置 Fail2ban 的 SSH 防暴力破解规则
#
# 不包含 SSH 登录策略加固、swap、目录/备份脚手架。
# 面向新服务器使用；若变更 Docker 数据目录时发现已有数据，脚本会停止。
# 可通过同名环境变量覆盖下方默认值，例如：
#   SSH_PORT=2222 DOCKER_DATA_ROOT=/mnt/docker sudo -E bash quick_server_init.sh

set -Eeuo pipefail

readonly SSH_PORT="${SSH_PORT:-22}"
readonly PUBLIC_TCP_PORTS="${PUBLIC_TCP_PORTS:-80 443}"
readonly DOCKER_DATA_ROOT="${DOCKER_DATA_ROOT:-/data/docker}"
readonly DOCKER_LOG_MAX_SIZE="${DOCKER_LOG_MAX_SIZE:-100m}"
readonly DOCKER_LOG_MAX_FILE="${DOCKER_LOG_MAX_FILE:-3}"
readonly DOCKER_PRUNE_UNTIL="${DOCKER_PRUNE_UNTIL:-240h}"
readonly JOURNAL_MAX_USE="${JOURNAL_MAX_USE:-1G}"

readonly -a BASE_PACKAGES=(
  openssh-server
  vim curl wget git rsync tar unzip
  lsof dnsutils jq bash-completion
  ufw chrony fail2ban net-tools
  nginx ca-certificates
)

TMP_DIR=""
PUBLIC_PORTS=()

log() {
  printf '\033[1;32m[INFO]\033[0m %s\n' "$*"
}

warn() {
  printf '\033[1;33m[WARN]\033[0m %s\n' "$*"
}

err() {
  printf '\033[1;31m[ERR ]\033[0m %s\n' "$*" >&2
}

die() {
  err "$*"
  exit 1
}

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf -- "${TMP_DIR}"
  fi
}

trap cleanup EXIT
trap 'rc=$?; err "第 ${LINENO} 行执行失败，退出码：${rc}"' ERR

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "缺少命令：${cmd}"
}

validate_port() {
  local port="$1"
  local name="$2"

  [[ "${port}" =~ ^[1-9][0-9]{0,4}$ ]] ||
    die "${name} 必须是 1-65535 之间的端口号，当前值：${port}"
  ((10#${port} <= 65535)) ||
    die "${name} 必须是 1-65535 之间的端口号，当前值：${port}"
}

install_config() {
  local source_file="$1"
  local target_file="$2"
  local mode="$3"

  if [[ -f "${target_file}" ]] && cmp -s -- "${source_file}" "${target_file}"; then
    log "配置未变化，跳过：${target_file}"
    return
  fi

  if [[ -e "${target_file}" || -L "${target_file}" ]]; then
    local backup_file
    backup_file="${target_file}.bak.$(date +%Y%m%d_%H%M%S_%N)"
    cp -a -- "${target_file}" "${backup_file}"
    warn "已备份原配置：${backup_file}"
  fi

  install -D -o root -g root -m "${mode}" -- "${source_file}" "${target_file}"
  log "已写入配置：${target_file}"
}

check_environment() {
  [[ "${EUID}" -eq 0 ]] || die "请使用 sudo 或 root 执行本脚本。"
  [[ -r /etc/os-release ]] || die "无法读取 /etc/os-release，不能确认操作系统。"

  # shellcheck disable=SC1091
  source /etc/os-release
  [[ "${ID:-}" == "ubuntu" ]] || die "本脚本仅支持 Ubuntu，当前系统：${ID:-unknown}"

  if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    warn "本脚本以 Ubuntu 24.04 为基线，当前版本为 ${VERSION_ID:-unknown}。"
  fi

  [[ -d /run/systemd/system ]] || die "当前环境未运行 systemd。"

  local cmd
  for cmd in apt-get systemctl install cmp mktemp; do
    require_cmd "${cmd}"
  done

  validate_port "${SSH_PORT}" "SSH_PORT"

  read -r -a PUBLIC_PORTS <<<"${PUBLIC_TCP_PORTS}"
  ((${#PUBLIC_PORTS[@]} > 0)) || die "PUBLIC_TCP_PORTS 不能为空。"

  local port
  for port in "${PUBLIC_PORTS[@]}"; do
    validate_port "${port}" "PUBLIC_TCP_PORTS"
  done

  [[ "${DOCKER_DATA_ROOT}" == /* && "${DOCKER_DATA_ROOT}" != "/" ]] ||
    die "DOCKER_DATA_ROOT 必须是非根目录的绝对路径。"
  [[ "${DOCKER_LOG_MAX_SIZE}" =~ ^[1-9][0-9]*[kKmMgG]$ ]] ||
    die "DOCKER_LOG_MAX_SIZE 格式无效，示例：100m。"
  [[ "${DOCKER_LOG_MAX_FILE}" =~ ^[1-9][0-9]*$ ]] ||
    die "DOCKER_LOG_MAX_FILE 必须是正整数。"
  [[ "${DOCKER_PRUNE_UNTIL}" =~ ^[1-9][0-9]*h$ ]] ||
    die "DOCKER_PRUNE_UNTIL 必须使用小时格式，示例：240h。"
  [[ "${JOURNAL_MAX_USE}" =~ ^[1-9][0-9]*[KMGT]$ ]] ||
    die "JOURNAL_MAX_USE 格式无效，示例：1G。"

  TMP_DIR="$(mktemp -d)"
  chmod 700 "${TMP_DIR}"
}

install_packages() {
  log "更新系统软件包缓存并升级"
  DEBIAN_FRONTEND=noninteractive apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

  log "安装常用工具、Nginx 与安全组件"
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${BASE_PACKAGES[@]}"

  if ! command -v docker >/dev/null 2>&1 || ! command -v dockerd >/dev/null 2>&1; then
    log "安装 Ubuntu 仓库中的 Docker Engine 与 Compose v2"
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2
  else
    log "检测到现有 Docker Engine，跳过重复安装"
  fi

  if ! docker compose version >/dev/null 2>&1; then
    log "安装 Docker Compose v2"
    DEBIAN_FRONTEND=noninteractive apt-get install -y docker-compose-v2
  fi

  local cmd
  for cmd in ufw jq docker dockerd fail2ban-client sshd; do
    require_cmd "${cmd}"
  done
}

configure_base_services() {
  log "启用 SSH、chrony 与 Nginx"
  systemctl enable --now ssh
  systemctl enable --now chrony
  systemctl enable --now nginx
}

configure_firewall() {
  if ! sshd -T 2>/dev/null |
    awk '$1 == "port" { print $2 }' |
    grep -Fxq "${SSH_PORT}"; then
    die "SSH_PORT=${SSH_PORT} 与 sshd 实际监听端口不一致，拒绝启用 UFW。"
  fi

  log "配置 UFW 默认策略"
  ufw default deny incoming
  ufw default allow outgoing

  log "放行 SSH 端口 ${SSH_PORT}/tcp"
  ufw allow "${SSH_PORT}/tcp"

  local port
  for port in "${PUBLIC_PORTS[@]}"; do
    log "放行业务端口 ${port}/tcp"
    ufw allow "${port}/tcp"
  done

  ufw --force enable
}

configure_system() {
  log "配置 journald 日志上限"
  local journald_config="${TMP_DIR}/99-size.conf"
  cat >"${journald_config}" <<EOF
[Journal]
# 限制日志总占用，避免写满磁盘
SystemMaxUse=${JOURNAL_MAX_USE}
SystemMaxFileSize=200M
SystemKeepFree=500M
Compress=yes
EOF
  install_config "${journald_config}" /etc/systemd/journald.conf.d/99-size.conf 0644
  systemctl restart systemd-journald

  log "配置容器宿主机 sysctl 参数"
  local sysctl_config="${TMP_DIR}/99-container-host.conf"
  cat >"${sysctl_config}" <<'EOF'
# 提高全局文件句柄上限
fs.file-max = 1048576

# 增大连接队列与 TCP 半连接队列
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 4096

# 缩短 FIN-WAIT 状态超时时间
net.ipv4.tcp_fin_timeout = 15

# Docker bridge/NAT 需要 IP 转发
net.ipv4.ip_forward = 1

# Elasticsearch/OpenSearch 等服务需要更多虚拟内存映射
vm.max_map_count = 262144

# 减少过早使用 swap 的倾向
vm.swappiness = 10
EOF
  install_config "${sysctl_config}" /etc/sysctl.d/99-container-host.conf 0644
  sysctl --system
}

configure_fail2ban() {
  log "配置 Fail2ban SSH 防护"
  local jail_config="${TMP_DIR}/jail.local"
  cat >"${jail_config}" <<EOF
[DEFAULT]
# 封禁 1 小时
bantime = 3600

# 10 分钟内失败 5 次后封禁
findtime = 600
maxretry = 5

# Ubuntu 使用 systemd journal 作为日志后端
backend = systemd

[sshd]
enabled = true
port = ${SSH_PORT}
EOF
  install_config "${jail_config}" /etc/fail2ban/jail.local 0644

  fail2ban-client -t >/dev/null
  systemctl enable fail2ban
  systemctl restart fail2ban
}

configure_docker() {
  log "配置 Docker daemon"

  if systemctl is-active --quiet docker; then
    local current_data_root
    current_data_root="$(docker info --format '{{.DockerRootDir}}' 2>/dev/null || true)"

    if [[ -n "${current_data_root}" && "${current_data_root}" != "${DOCKER_DATA_ROOT}" ]]; then
      if [[ -n "$(docker ps -aq 2>/dev/null)" ||
        -n "$(docker images -q 2>/dev/null)" ||
        -n "$(docker volume ls -q 2>/dev/null)" ]]; then
        die "Docker 已有数据且当前目录为 ${current_data_root}，请先迁移后再改为 ${DOCKER_DATA_ROOT}。"
      fi

      warn "Docker 数据目录将从 ${current_data_root} 调整为 ${DOCKER_DATA_ROOT}。"
    fi
  fi

  local daemon_config="${TMP_DIR}/daemon.json"
  jq -n \
    --arg data_root "${DOCKER_DATA_ROOT}" \
    --arg log_max_size "${DOCKER_LOG_MAX_SIZE}" \
    --arg log_max_file "${DOCKER_LOG_MAX_FILE}" \
    '{
      "registry-mirrors": [
        "https://docker.1ms.run",
        "https://dockerproxy.net",
        "https://proxy.vvvv.ee",
        "https://dockerproxy.link"
      ],
      "data-root": $data_root,
      "log-driver": "json-file",
      "log-opts": {
        "max-size": $log_max_size,
        "max-file": $log_max_file
      },
      "live-restore": true,
      "iptables": true,
      "ip-forward": true,
      "storage-driver": "overlay2",
      "features": {
        "buildkit": true
      }
    }' >"${daemon_config}"

  dockerd --validate --config-file="${daemon_config}" >/dev/null
  mkdir -p -- "${DOCKER_DATA_ROOT}"
  install_config "${daemon_config}" /etc/docker/daemon.json 0644

  log "创建 Docker 安全清理脚本与 systemd 定时器"
  local docker_bin
  docker_bin="$(command -v docker)"

  local prune_script="${TMP_DIR}/docker-prune-safe.sh"
  cat >"${prune_script}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

# 清理长期未使用的镜像、构建缓存和已停止容器；不删除数据卷。
exec "${docker_bin}" system prune -af --filter "until=${DOCKER_PRUNE_UNTIL}"
EOF
  install_config "${prune_script}" /usr/local/sbin/docker-prune-safe.sh 0750

  local prune_service="${TMP_DIR}/docker-prune.service"
  cat >"${prune_service}" <<'EOF'
[Unit]
Description=Safe Docker prune
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/docker-prune-safe.sh
EOF
  install_config "${prune_service}" /etc/systemd/system/docker-prune.service 0644

  local prune_timer="${TMP_DIR}/docker-prune.timer"
  cat >"${prune_timer}" <<'EOF'
[Unit]
Description=Run safe Docker prune daily

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
  install_config "${prune_timer}" /etc/systemd/system/docker-prune.timer 0644

  systemctl daemon-reload
  systemctl enable docker
  systemctl restart docker
  systemctl enable --now docker-prune.timer
}

verify_initialization() {
  log "验证初始化结果"
  local service
  for service in ssh chrony nginx docker fail2ban; do
    systemctl is-active --quiet "${service}" ||
      die "服务未正常运行：${service}"
  done

  systemctl is-enabled --quiet docker-prune.timer ||
    die "docker-prune.timer 未启用。"
  systemctl is-active --quiet docker-prune.timer ||
    die "docker-prune.timer 未运行。"

  grep -Eq '^ENABLED=yes$' /etc/ufw/ufw.conf ||
    die "UFW 未启用。"
  [[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] ||
    die "net.ipv4.ip_forward 未生效。"
  [[ "$(sysctl -n vm.max_map_count)" == "262144" ]] ||
    die "vm.max_map_count 未生效。"

  docker info >/dev/null
  docker compose version >/dev/null
  fail2ban-client status sshd >/dev/null

  log "快速初始化完成"
  log "UFW 已放行 TCP 端口：${SSH_PORT} ${PUBLIC_TCP_PORTS}"
  log "Docker 数据目录：${DOCKER_DATA_ROOT}"

  if [[ -f /var/run/reboot-required ]]; then
    warn "系统升级后需要重启，请在确认业务允许后执行 reboot。"
  fi

  warn "Docker 发布端口由 Docker 自身的 iptables 规则管理，不完全受 UFW 入站规则约束。"
}

main() {
  check_environment
  install_packages
  configure_base_services
  configure_firewall
  configure_system
  configure_fail2ban
  configure_docker
  verify_initialization
}

main "$@"
