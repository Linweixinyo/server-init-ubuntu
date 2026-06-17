#!/usr/bin/env bash
# 99_verify.sh
#
# 这个脚本用于做初始化后的自检。
# 它不修改系统，只负责输出关键状态，帮助你确认是否配置成功。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root

echo
log "========== 系统信息 =========="
uname -a
cat /etc/os-release || true

echo
log "========== 时间同步 =========="
timedatectl status || true
systemctl is-active chrony || true
chronyc tracking || true

echo
log "========== AppArmor =========="
aa-status || true

echo
log "========== SSHD 配置检查 =========="
sshd -t && echo "sshd 配置语法正常"

echo
log "========== 防火墙开放端口 =========="
ufw status verbose || true

echo
log "========== fail2ban 状态 =========="
systemctl is-active fail2ban || true
fail2ban-client status sshd || true

echo
log "========== swap =========="
swapon --show || true
free -h

echo
log "========== sysctl 关键参数 =========="
sysctl net.ipv4.ip_forward || true
sysctl vm.swappiness || true
sysctl fs.file-max || true

echo
log "========== Docker 状态 =========="
systemctl is-active docker || true
docker info 2>/dev/null | sed -n '1,40p' || true
docker compose version || true

echo
log "========== systemd 定时器 =========="
systemctl list-timers --all | grep -E 'docker-prune|example-backup' || true

echo
log "========== 目录结构 =========="
ls -ld /srv /srv/compose /srv/data /srv/backups /srv/scripts /srv/log || true

echo
log "自检完成"