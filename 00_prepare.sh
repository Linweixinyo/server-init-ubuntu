#!/usr/bin/env bash
# 00_prepare.sh
#
# 这个阶段只做“安全风险较低”的基础准备：
# 1. 更新系统包
# 2. 配置时区
# 3. 安装常用工具
# 4. 启用 chrony 做时间同步
#
# 先执行这个脚本，一般不会影响你的远程连接。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root

log "检查管理员用户是否存在"
require_user_exists "${ADMIN_USER}"

log "更新系统软件包缓存并升级"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

log "安装常用基础工具"
# vim: 较完整的 vim
# curl/wget: 网络下载与调试
# git: 拉取代码或配置仓库
# rsync: 同步/备份常用
# tar/unzip: 解压缩
# lsof: 查看端口和文件占用
# dnsutils: dig/nslookup 等 DNS 工具
# jq: 处理 JSON
# bash-completion: 自动补全
# ufw: Ubuntu 常用防火墙
# chrony: 时间同步
# fail2ban: 防暴力破解（后续脚本会配置）
# net-tools: ifconfig/netstat 等旧工具，排障时有时方便
# apparmor-utils: 检查 AppArmor 状态
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openssh-server \
  vim curl wget git rsync tar unzip \
  lsof dnsutils jq bash-completion \
  ufw chrony fail2ban net-tools apparmor-utils

log "设置时区为 ${TIMEZONE}"
timedatectl set-timezone "${TIMEZONE}"

log "启用并启动 chrony 时间同步服务"
systemctl enable --now chrony

log "基础准备完成"