# shipin Linux 部署

Release 提供 Linux `amd64`、`arm64` 程序，运行机需要 FFmpeg 和 FFprobe。systemd 是后台管理与在线升级的条件；手动前台运行不需要 systemd。

下面是新建系统服务的示例。已有部署请先阅读[旧版迁移](service-management.md#从旧版迁移)，保留现有数据目录、媒体目录和共享权限。

## 构建与目录

构建机需要 Go 1.25+：

```bash
SHIPIN_VERSION=v0.5.0 ./scripts/build-linux.sh
(cd dist && shasum -a 256 -c SHA256SUMS)
```

也可直接下载 Release 的程序与 `SHA256SUMS`，先核对校验项和摘要再安装。以下 Ubuntu/Debian 示例创建专用系统用户；已有用户或目录先检查，不要覆盖媒体：

```bash
sudo useradd --system --home /opt/shipin --shell /usr/sbin/nologin shipin
sudo install -d -m 0755 /opt/shipin/bin
sudo install -d -o shipin -g shipin -m 0700 /var/lib/shipin
sudo install -d -o shipin -g shipin -m 2750 /srv/shipin/media
sudo install -m 0755 dist/shipin-linux-amd64 /opt/shipin/bin/shipin
```

ARM64 主机把最后一行源文件换成 `shipin-linux-arm64`。服务用户需要能读写状态和媒体目录。Emby 用户需要目录遍历与文件读取权限；按实际共享组或 ACL 配置，保留既有权限，不要递归改写属主。

## 生成并安装 systemd unit

从源码目录运行，按实际用户和路径设置：

```bash
SHIPIN_USER=shipin \
SHIPIN_INSTALL_DIR=/opt/shipin \
SHIPIN_DATA_DIR=/var/lib/shipin \
SHIPIN_MEDIA_DIR=/srv/shipin/media \
SHIPIN_LISTEN=127.0.0.1:4444 \
SHIPIN_SERVICE_NAME=shipin \
./scripts/render-systemd.sh
```

生成器只输出临时文件，不启用服务。路径限定为不含空格的绝对路径；将以下临时路径替换为脚本打印的真实路径。审阅 `User`、`ExecStart`、环境变量和 `ReadWritePaths` 后执行：

```bash
sudo install -m 0644 /tmp/shipin.XXXXXXXX.service /etc/systemd/system/shipin.service
sudo systemctl daemon-reload
sudo systemctl enable --now shipin.service
systemctl status shipin.service --no-pager
curl --fail http://127.0.0.1:4444/healthz
sudo install -m 0755 scripts/shipin-service.sh /usr/local/bin/shipin-service
sudo install -m 0644 scripts/shipin-update.py /usr/local/bin/shipin-update.py
```

模板默认面向系统服务，会写入实际服务名与 `SHIPIN_SYSTEMD_SCOPE=system`，可通过安装目录的 `.env` 覆盖。自建用户服务需要把 scope 设置为 `user`。

局域网访问可将监听地址改为服务器内网 IP。管理台没有登录，不要映射到公网。`UMask=0027` 限制媒体默认权限；更换媒体目录时还需核对共享权限和 unit 的 `ReadWritePaths`，按需重新加载、重启服务。

## 管理与升级

```bash
SHIPIN_SYSTEMD_SCOPE=system SHIPIN_SERVICE_NAME=shipin SHIPIN_BINARY=/opt/shipin/bin/shipin \
  /usr/local/bin/shipin-service health
SHIPIN_SYSTEMD_SCOPE=system SHIPIN_SERVICE_NAME=shipin SHIPIN_BINARY=/opt/shipin/bin/shipin \
  /usr/local/bin/shipin-service check-update
sudo env SHIPIN_SYSTEMD_SCOPE=system SHIPIN_SERVICE_NAME=shipin SHIPIN_BINARY=/opt/shipin/bin/shipin \
  /usr/local/bin/shipin-service update
journalctl -u shipin.service -n 100 --no-pager
```

脚本升级需要 Python 3，先校验 Release 与 SHA256，再替换、重启并验证目标版本；失败时尝试恢复旧程序。升级前备份 JSON 状态与媒体。日志写入标准错误，由 journal 收集，HTTP 请求日志不记录搜索词、播放地址、请求体和凭据。

完整参数、网页更新条件、用户服务和排障见[服务管理与升级](service-management.md)。
