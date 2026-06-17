#!/usr/bin/env bash
# 01_security_base.sh
#
# 这个脚本负责：
# 1. SSH 安全加固
# 2. sudo 基础配置检查
# 3. fail2ban 启用
# 4. AppArmor 状态确认
#
# 注意：
# 改 SSH 配置有可能让你“登录不上”。
# 所以执行前必须确认：
# - 当前 ADMIN_USER 已经配置好 SSH 公钥
# - 当前会话不要断
# - 改完后另开新终端测试登录

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root
require_user_exists "${ADMIN_USER}"

log "备份 SSH 配置文件"
backup_file /etc/ssh/sshd_config

log "写入 SSH 安全配置"
# 这里使用独立 drop-in 文件，而不是粗暴改原始 sshd_config
# 这样更清晰，也方便以后维护
ensure_dir /etc/ssh/sshd_config.d 700

cat >/etc/ssh/sshd_config.d/99-hardening.conf <<EOF
# 99-hardening.conf
#
# 这是额外的 SSH 加固配置。
# OpenSSH 会读取 /etc/ssh/sshd_config.d/*.conf

# SSH 监听端口
Port ${SSH_PORT}

# 禁止 root 直接远程登录
PermitRootLogin ${SSH_PERMIT_ROOT_LOGIN}

# 禁止密码认证，只允许密钥认证
PasswordAuthentication ${SSH_PASSWORD_AUTH}

# 显式开启公钥认证
PubkeyAuthentication yes

# 禁止空密码
PermitEmptyPasswords no

# 限制失败尝试次数，减少暴力破解空间
MaxAuthTries 3

# 限制认证等待时间
LoginGraceTime 30

# 不允许 X11 转发，除非你明确需要图形转发
X11Forwarding no

# 一般服务器不需要 GSSAPI，关掉可减少某些慢连接问题
GSSAPIAuthentication no

# 只允许指定用户登录
AllowUsers ${ADMIN_USER}

# 仅使用 SSH 协议 2（现代系统一般默认如此，这里写明是为了可读性）
Protocol 2

# 减少空闲连接长期占用
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

chown root:root /etc/ssh/sshd_config.d/99-hardening.conf
chmod 600 /etc/ssh/sshd_config.d/99-hardening.conf

log "校验 SSH 配置语法"
sshd -t

log "重启 ssh 服务使配置生效"
systemctl restart ssh

log "配置 sudo 日志记录"
# 这里的目的不是限制 sudo，而是让 sudo 使用行为更容易追踪
cat >/etc/sudoers.d/99-audit-log <<'EOF'
Defaults logfile="/var/log/sudo.log"
Defaults loglinelen=0
EOF

chmod 440 /etc/sudoers.d/99-audit-log
visudo -cf /etc/sudoers.d/99-audit-log >/dev/null

if [[ "${ENABLE_FAIL2BAN}" == "yes" ]]; then
  log "配置 fail2ban"
  cat >/etc/fail2ban/jail.local <<EOF
[DEFAULT]
# 封禁时长，单位秒。1小时 = 3600
bantime = 3600

# 在 findtime 时间窗口内，超过 maxretry 次失败则封禁
findtime = 600
maxretry = 5

# Ubuntu 上一般使用 systemd 作为日志后端
backend = systemd

[sshd]
enabled = true
port = ${SSH_PORT}
EOF

  systemctl enable --now fail2ban
fi

log "检查 AppArmor 状态"
# AppArmor 是 Ubuntu 常用的强制访问控制机制。
aa-status || true

warn "请现在另开一个终端窗口，测试是否还能通过 SSH 正常登录。"
warn "确认新连接正常前，不要关闭当前会话。"

log "安全基线配置完成"