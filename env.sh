#!/usr/bin/env bash
# env.sh
#
# 这个文件用于集中定义“可按机器调整”的变量。
# 后续脚本都会 source 这个文件。
#
# 你只需要按实际情况修改这些变量，不用到每个脚本里找参数。

# 你的运维用户名（必须是已经存在并且已配置 SSH 公钥的用户）
# 这个用户将被允许通过 SSH 登录。
ADMIN_USER="ubuntu"

# SSH 服务端口
# 默认是 22。你可以改成其他端口减少扫描噪音，但这不是核心安全措施。
# 如果你要改，记得防火墙也要放行新端口。
SSH_PORT="22"

# 服务器时区
# 如果你希望系统日志统一、跨时区管理方便，可以改成 UTC。
# 如果你更习惯本地时间，也可设置为 Asia/Shanghai。
TIMEZONE="Asia/Shanghai"

# 是否允许 root 直接通过 SSH 登录
# 强烈建议 no
SSH_PERMIT_ROOT_LOGIN="no"

# 是否允许 SSH 密码登录
# 既然你已经配好密钥，强烈建议 no
SSH_PASSWORD_AUTH="no"

# 是否启用 fail2ban
# fail2ban 会根据日志自动封禁暴力尝试 IP
ENABLE_FAIL2BAN="yes"

# 允许开放到公网的业务端口列表
# 这里只列“宿主机直接对外提供服务”的端口
# 常见是 80 和 443。多个端口用空格分隔。
PUBLIC_TCP_PORTS="443"

# Docker 数据根目录
# 默认为 /var/lib/docker，也可以改到其他盘
DOCKER_DATA_ROOT="/var/lib/docker"

# Docker 日志单文件上限
DOCKER_LOG_MAX_SIZE="100m"

# Docker 日志轮转保留文件数
DOCKER_LOG_MAX_FILE="3"

# 是否给系统创建一个小 swap 文件
# 对 Docker 宿主机来说，保留少量 swap 往往比完全没有更稳妥
CREATE_SWAP="yes"

# swap 大小，单位 MB
SWAP_SIZE_MB="4096"

# journald 日志总占用上限
JOURNAL_MAX_USE="1G"

# 自动清理 Docker 无用镜像/构建缓存的保留策略
# 例如 240h = 10 天
DOCKER_PRUNE_UNTIL="240h"