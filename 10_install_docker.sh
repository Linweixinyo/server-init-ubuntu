#!/usr/bin/env bash
# 10_install_docker.sh
#
# Ubuntu 24.04 默认仓库里可能没有你想要的最新版 Docker Engine。
# 这里使用 Docker 官方仓库安装。
#
# 我们安装：
# - docker-ce
# - docker-ce-cli
# - containerd.io
# - docker-buildx-plugin
# - docker-compose-plugin
#
# 这样你以后可以使用：
# - docker
# - docker compose
#
# 注意：
# 这里不会把 ADMIN_USER 自动加入 docker 组。
# 原因是 docker 组基本等价于 root 权限。
# 更安全的方式是需要时使用 sudo docker ...
# 如果你明确接受这个风险，再手动把用户加入 docker 组。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root
require_cmd curl

log "移除可能冲突的旧容器组件（如果有）"
DEBIAN_FRONTEND=noninteractive apt-get remove -y \
  docker.io \
  docker-doc \
  docker-compose \
  docker-compose-v2 \
  podman-docker \
  containerd \
  runc || true

log "安装 Docker 官方仓库所需工具"
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates gnupg

log "添加 Docker 官方仓库密钥"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

log "添加 Docker 官方仓库"
. /etc/os-release
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

log "更新 apt 索引"
apt-get update

log "安装 Docker Engine 及相关组件"
DEBIAN_FRONTEND=noninteractive apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

log "启用并启动 Docker"
systemctl enable --now docker

log "查看 Docker 版本"
docker version || true

log "Docker 安装完成"
warn "默认未将 ${ADMIN_USER} 加入 docker 组；这更安全。"