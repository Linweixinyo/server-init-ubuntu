#!/usr/bin/env bash
# 03_system_tuning.sh
#
# 这个脚本负责：
# 1. journald 日志占用限制
# 2. 一些适合作为容器宿主机的 sysctl 参数
# 3. 创建小 swap（可选）
#
# 说明：
# sysctl 是 Linux 内核参数调优机制。
# 这里不会做很激进的优化，只做“比较保守、基础”的设置。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root

log "配置 journald 日志上限"
ensure_dir /etc/systemd/journald.conf.d 755

cat >/etc/systemd/journald.conf.d/99-size.conf <<EOF
[Journal]
# 限制日志总占用，避免把磁盘写满
SystemMaxUse=${JOURNAL_MAX_USE}

# 单个日志文件的最大值
SystemMaxFileSize=200M

# 保留至少多少可用磁盘空间
SystemKeepFree=500M

# 压缩历史日志
Compress=yes
EOF

systemctl restart systemd-journald

log "写入 sysctl 容器宿主机基础参数"
cat >/etc/sysctl.d/99-container-host.conf <<'EOF'
# 允许较多的文件监视/打开句柄，某些应用或反向代理会受益
fs.file-max = 1048576

# 增大连接队列，对高并发入口服务更友好
net.core.somaxconn = 4096

# 增大等待连接队列
net.ipv4.tcp_max_syn_backlog = 4096

# 开启 TCP TIME-WAIT 连接复用相关回收优化（现代内核中部分参数已弱化）
net.ipv4.tcp_fin_timeout = 15

# 允许转发。作为容器宿主机通常需要。
# 比如 Docker bridge 网络、NAT 转发等。
net.ipv4.ip_forward = 1

# 提高虚拟内存映射数，某些数据库/搜索类组件会用到
vm.max_map_count = 262144

# 尽量减少内核过早使用 swap 的倾向
# 数值越低，越倾向优先使用内存
vm.swappiness = 10
EOF

sysctl --system

if [[ "${CREATE_SWAP}" == "yes" ]]; then
  if ! swapon --show | grep -q .; then
    log "未检测到已启用 swap，创建 ${SWAP_SIZE_MB}MB swap 文件"
    fallocate -l "${SWAP_SIZE_MB}M" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="${SWAP_SIZE_MB}"
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    append_if_not_exists "/swapfile swap swap defaults 0 0" /etc/fstab
  else
    warn "系统已有 swap，跳过创建"
  fi
fi

log "系统基础调优完成"