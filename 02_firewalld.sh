#!/usr/bin/env bash
# 02_firewalld.sh
#
# 这个脚本负责配置 ufw：
# 1. 仅开放 SSH 端口
# 2. 开放你明确需要的公网业务端口
#
# 注意：
# Docker 本身会操作 iptables/nftables。
# 这里的 ufw 规则主要用于宿主机入口控制。
#
# 如果你未来需要开放更多端口，请修改 env.sh 里的 PUBLIC_TCP_PORTS。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root
require_cmd ufw

log "设置 ufw 默认策略"
ufw default deny incoming
ufw default allow outgoing

log "放行 SSH 端口 ${SSH_PORT}/tcp"
ufw allow "${SSH_PORT}/tcp"

for port in ${PUBLIC_TCP_PORTS}; do
  log "放行业务端口 ${port}/tcp"
  ufw allow "${port}/tcp"
done

log "启用 ufw"
ufw --force enable

log "当前 ufw 状态如下："
ufw status verbose

log "防火墙配置完成"