#!/usr/bin/env bash
# lib.sh
#
# 放公共函数，给其他脚本复用。
# 这样脚本会更清晰，也更容易维护。

set -euo pipefail

# 获取当前脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载变量文件
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/env.sh"

log() {
  echo -e "\033[1;32m[INFO]\033[0m $*"
}

warn() {
  echo -e "\033[1;33m[WARN]\033[0m $*"
}

err() {
  echo -e "\033[1;31m[ERR ]\033[0m $*" >&2
}

# 检查是否为 root 执行
require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "请使用 sudo 或 root 执行本脚本。"
    exit 1
  fi
}

# 检查命令是否存在
require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    err "缺少命令: ${cmd}"
    exit 1
  fi
}

# 备份文件
backup_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    local ts
    ts="$(date +%Y%m%d_%H%M%S)"
    cp -a "${file}" "${file}.bak.${ts}"
    log "已备份 ${file} -> ${file}.bak.${ts}"
  fi
}

# 仅当某行不存在时才追加，避免重复写入
append_if_not_exists() {
  local line="$1"
  local file="$2"
  grep -Fqx "${line}" "${file}" 2>/dev/null || echo "${line}" >> "${file}"
}

# 写配置前先确保目录存在
ensure_dir() {
  local dir="$1"
  local mode="${2:-755}"
  mkdir -p "${dir}"
  chmod "${mode}" "${dir}"
}

# 简单检查用户是否存在
require_user_exists() {
  local user="$1"
  if ! id "${user}" >/dev/null 2>&1; then
    err "用户 ${user} 不存在，请先创建用户并配置好 SSH 公钥。"
    exit 1
  fi
}