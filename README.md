# server-init

Ubuntu 24.04 容器宿主机初始化脚本。
fork：https://cnb.cool/ConwayCell/server-init-ubuntu

## 使用前准备

1. 已创建运维用户
2. 已配置 SSH 公钥
3. 运维用户具有 sudo 权限
4. 修改 `env.sh` 中的变量

## 执行顺序

```bash
sudo bash 00_prepare.sh
sudo bash 01_security_base.sh
sudo bash 02_firewalld.sh
sudo bash 03_system_tuning.sh
sudo bash 10_install_docker.sh
sudo bash 11_docker_baseline.sh
sudo bash 12_dirs_and_backup_stub.sh
sudo bash 99_verify.sh
```

## 注意事项

`01_security_base.sh` 脚本会修改 SSH 配置，有可能让你“登录不上”，所以执行前必须确认：

- 当前 `ADMIN_USER` 已经配置好 SSH 公钥
- 当前会话不要断
- 改完后另开新终端测试登录

Ubuntu 版本使用 `ufw` 作为防火墙，`chrony` 作为时间同步服务，`AppArmor` 作为内核强制访问控制基线检查项。
