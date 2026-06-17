#!/usr/bin/env bash
# 12_dirs_and_backup_stub.sh
#
# 这个脚本不直接替你实现数据库备份逻辑，
# 而是先把宿主机目录结构、示例备份脚本、systemd 定时任务框架搭起来。
#
# 这样你以后接 PostgreSQL / MySQL / Redis 时，只需要替换具体命令。

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib.sh"

require_root

log "创建统一目录结构"

# /srv/compose     放 compose 项目
# /srv/data        放持久化数据
# /srv/backups     放备份文件
# /srv/scripts     放运维脚本
# /srv/log         可选放宿主机级别自定义日志
ensure_dir /srv/compose 755
ensure_dir /srv/data 755
ensure_dir /srv/backups 700
ensure_dir /srv/scripts 750
ensure_dir /srv/log 755

log "为管理员用户授予 /srv 下的管理权限"
chown -R "${ADMIN_USER}:${ADMIN_USER}" /srv/compose /srv/data /srv/log
chown root:root /srv/backups /srv/scripts

log "创建一个示例备份脚本"
cat >/srv/scripts/backup-example.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# 这是一个“示意脚本”，目的是告诉你备份应该如何组织。
# 它不会真的备份数据库，除非你把里面的示例命令替换成真实命令。

BACKUP_ROOT="/srv/backups"
DATE_TAG="$(date +%F_%H%M%S)"
TARGET_DIR="${BACKUP_ROOT}/${DATE_TAG}"

mkdir -p "${TARGET_DIR}"

# 示例 1：打包某个应用的数据目录
# 适合静态文件、配置文件、部分小型应用数据
# 注意：对数据库来说，直接打包数据目录通常不是最佳做法，数据库更推荐逻辑备份（dump）
tar -czf "${TARGET_DIR}/srv-data-snapshot.tar.gz" /srv/data

# 示例 2：如果你以后部署 PostgreSQL，更推荐用 pg_dump
# pg_dump -h 127.0.0.1 -U postgres -d yourdb > "${TARGET_DIR}/yourdb.sql"

# 示例 3：如果你以后部署 MySQL/MariaDB
# mysqldump -h 127.0.0.1 -u root -p'密码' yourdb > "${TARGET_DIR}/yourdb.sql"

# 删除 7 天前的旧备份
find "${BACKUP_ROOT}" -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
EOF

chmod 750 /srv/scripts/backup-example.sh

log "创建示例 systemd 定时备份任务"
cat >/etc/systemd/system/example-backup.service <<'EOF'
[Unit]
Description=Example backup job

[Service]
Type=oneshot
ExecStart=/srv/scripts/backup-example.sh
EOF

cat >/etc/systemd/system/example-backup.timer <<'EOF'
[Unit]
Description=Run example backup daily

[Timer]
OnCalendar=*-*-* 02:30:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now example-backup.timer

log "目录与备份脚手架准备完成"