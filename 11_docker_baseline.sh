#!/usr/bin/env bash
# 11_docker_baseline.sh
#
# 这个脚本配置 Docker daemon：
# 1. 日志轮转，避免容器日志无限增长
# 2. live-restore，降低 daemon 重启对容器的影响
# 3. 配置 data-root（容器数据目录)
# 4. 使用 systemd 管理 Docker 开机自启
#
# 说明：
# /etc/docker/daemon.json 是 Docker 守护进程的主配置文件。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root

ensure_dir /etc/docker 755

log "备份旧的 Docker daemon 配置（如果存在）"
backup_file /etc/docker/daemon.json

log "写入 Docker daemon 基线配置"
cat >/etc/docker/daemon.json <<EOF
{
  "data-root": "${DOCKER_DATA_ROOT}",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "${DOCKER_LOG_MAX_SIZE}",
    "max-file": "${DOCKER_LOG_MAX_FILE}"
  },
  "live-restore": true,
  "iptables": true,
  "ip-forward": true,
  "storage-driver": "overlay2",
  "features": {
    "buildkit": true
  }
}
EOF

log "重启 Docker 使配置生效"
systemctl restart docker

log "创建 Docker 定时清理任务"
cat >/usr/local/sbin/docker-prune-safe.sh <<EOF
#!/usr/bin/env bash
set -euo pipefail

# 清理长时间未使用的镜像、构建缓存、已停止容器
# 注意：这里故意不加 --volumes，避免误删还可能有用的数据卷
/usr/bin/docker system prune -af --filter "until=${DOCKER_PRUNE_UNTIL}"
EOF

chmod 750 /usr/local/sbin/docker-prune-safe.sh

cat >/etc/systemd/system/docker-prune.service <<'EOF'
[Unit]
Description=Safe Docker prune

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/docker-prune-safe.sh
EOF

cat >/etc/systemd/system/docker-prune.timer <<'EOF'
[Unit]
Description=Run safe Docker prune daily

[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now docker-prune.timer

log "Docker 基线配置完成"