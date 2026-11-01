# shipin 服务管理与升级

`scripts/shipin-service.sh` 管理 systemd 服务，`health`、`check-update` 和 `update` 调用同目录的 `shipin-update.py`。管理命令适用于运行 systemd 的 Linux，Python 升级器需要 Python 3；macOS 开发使用 `scripts/run.sh`。

## 用户服务

新部署默认服务名是 `shipin.service`，作用域为用户服务。程序、管理脚本和更新脚本可平铺在同一目录：

```text
/home/lee/shipin/
├── shipin
├── shipin-service.sh
├── shipin-update.py
├── data/
└── media/
```

这是目录布局示例，既有服务器保留实际目录和原 unit。以服务所属用户运行：

```bash
cd /home/lee/shipin
./shipin-service.sh status
./shipin-service.sh health
./shipin-service.sh logs
./shipin-service.sh check-update
./shipin-service.sh update
```

| 命令 | 行为 |
| --- | --- |
| `help` | 显示帮助 |
| `status` | 查看服务状态 |
| `start`、`stop`、`restart` | 启停或重启服务；下载任务在重新启动后按持久化状态恢复 |
| `logs` | 查看最近 100 条日志 |
| `logs -f` | 跟踪日志，Ctrl+C 仅退出查看 |
| `health` | 从 unit 的监听参数推导 `/healthz`，显示运行版本 |
| `check-update` | 查询最新正式 Release，不安装 |
| `update` | 校验下载、原子替换、重启、核对版本；启动失败时尝试回滚 |

除 `logs -f` 外，各命令不接受额外参数。脚本不自动提权，执行用户需要有权管理对应 unit 和替换程序。

## 环境变量

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `SHIPIN_SYSTEMD_SCOPE` | `user` | `user` 或 `system` |
| `SHIPIN_SERVICE_NAME` | `shipin` | unit 名，不带 `.service`；小写字母开头，后接小写字母、数字、连字符或下划线 |
| `SHIPIN_BINARY` | 脚本同目录的程序，或源码目录中的 `bin/shipin` | 脚本升级要替换的普通文件 |
| `SHIPIN_HEALTH_URL` | 从 unit 的 `--listen` 推导 | 显式本机 HTTP `/healthz` 地址 |

上述变量也兼容 `MOVIEHUB_` 前缀，新变量优先。更新器寻找程序时优先使用新名称，也兼容旧程序名；目录不同或存在多个程序时请显式设置 `SHIPIN_BINARY`。

系统服务示例：

```bash
SHIPIN_SYSTEMD_SCOPE=system SHIPIN_SERVICE_NAME=shipin SHIPIN_BINARY=/opt/shipin/bin/shipin \
  /usr/local/bin/shipin-service check-update
sudo env SHIPIN_SYSTEMD_SCOPE=system SHIPIN_SERVICE_NAME=shipin SHIPIN_BINARY=/opt/shipin/bin/shipin \
  /usr/local/bin/shipin-service update
```

自定义 unit 时替换两条命令的服务名；`sudo` 不保证继承终端环境，因此更新命令显式传入所有目标参数。服务已停止时先排查并启动，升级器需要访问健康接口。

## 网页更新

管理台底部展示当前版本、发行时间和检测更新按钮。检测有新版后需要确认安装；独立 systemd 任务负责下载、SHA256 校验、原子替换、重启和版本回验，失败时尝试恢复旧程序。页面在服务重启后自动重连。

支持 Linux amd64/arm64，需要 `systemctl`、`systemd-run`，且 unit 主进程必须是当前程序。程序目录必须可写，unit 应通过 `--listen` 指定监听地址。普通用户运行的系统级服务使用有权限的管理脚本升级；系统级网页更新仅支持 root 服务进程。

将 `SHIPIN_SERVICE_NAME` 和 `SHIPIN_SYSTEMD_SCOPE` 设置在服务进程的 systemd 环境中，例如 unit 的 `Environment=` 或 `EnvironmentFile=`。只在终端设置变量不会改变已经运行的网页服务。模板生成器会为新建系统服务写入这两个变量；自建用户 unit 则显式设为 `user`。

网页更新自动定位正在运行的程序，不使用脚本的 `SHIPIN_BINARY` 和 `SHIPIN_HEALTH_URL`。进度保存在 `data/web-update.json`，对应 `.lock` 文件用于加锁，旧二进制保存在程序旁的 `.previous-时间戳` 文件中。查看默认用户服务的更新任务日志：

```bash
journalctl --user -u shipin-web-update.service -n 100
```

检测后超过 30 分钟需要重新检测。升级期间不要手动替换程序或修改更新记录；服务健康不等于下载和 Emby 入库均已验收。

## 从旧版迁移

`v0.5.0` 首次统一项目、仓库和发行资产名称，原更新器固定校验旧路径与资产名，需要先更换为本仓库的新版脚本。

1. 确认原 unit 名、服务所属用户、程序路径、数据与媒体路径，等待正在运行的独立更新任务退出。
2. 备份数据目录、程序和 unit。保留数据及媒体的实际路径，保留已有权限与 ACL；不要改写任务 JSON 中的绝对路径。
3. 从本版本源码取出 `scripts/shipin-service.sh`、`scripts/shipin-update.py`，放在同一目录。两个脚本可管理仍沿用旧程序名和旧 unit 的服务。
4. 为单条命令显式设置原服务名、实际程序绝对路径和服务作用域，再调用新版脚本的 `check-update`、`update`。例如：

   ```bash
   SHIPIN_SERVICE_NAME=existing-service SHIPIN_SYSTEMD_SCOPE=user SHIPIN_BINARY=/absolute/path/to/program \
     ./shipin-service.sh update
   ```

   将示例值替换为刚核实的实际配置；系统服务使用有权限的管理员，并用 `sudo env` 显式传入相同目标参数。
5. 为新版服务进程设置同样的 `SHIPIN_SERVICE_NAME`、`SHIPIN_SYSTEMD_SCOPE`，在后续正常重启后核对网页更新目标。只更换二进制不会改变原 unit 的环境配置。
6. 检查 `/healthz` 报告新版本，原任务和媒体可用，再核对下载及 Emby 入库。

也可以从 Release 校验下载后，在停服并备份的前提下手动更换程序。不要在仅改仓库名时搬迁生产目录或删除旧文件。`.moviehub/` 和 `.moviehub.json` 属于既有媒体格式，继续用于归属校验、失败恢复与安全删除。

## 故障排查

| 现象 | 检查 |
| --- | --- |
| 读不到健康接口 | unit 的 `--listen`、本机监听地址，必要时设 `SHIPIN_HEALTH_URL` |
| 网页提示不支持更新 | 服务进程的变量、MainPID、systemd 工具、目录写权限与作用域 |
| 找不到新资产 | 是否仍在使用旧脚本，以及 GitHub 最新正式 Release 的资产名 |
| 升级失败 | 下载错误、SHA256、旧程序备份和 journal 日志；确认是否回滚成功 |
| Emby 尚未识别 | 共享目录、权限、媒体库类型和扫描进度 |
