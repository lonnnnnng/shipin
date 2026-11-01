# shipin

从资源站找剧、追更、下载，到整理媒体并交给 Emby 播放。

shipin 是面向个人与家庭局域网的影视下载管理服务，使用 Go 编写，Web 管理台随程序一起发布。资源站提供 HLS，shipin 下载并封装为 MP4，生成剧集元数据和海报，随后通知 Emby 扫描共享媒体目录。

[下载正式版](https://github.com/lonnnnnng/shipin/releases/latest) · [Linux 部署](docs/linux-deployment.md) · [服务与升级](docs/service-management.md) · [发版流程](docs/release.md) · [反馈问题](https://github.com/lonnnnnng/shipin/issues)

> 管理台没有登录或访问令牌，仅适合可信局域网。默认监听 `127.0.0.1:4444`，不要将管理端口暴露到公网。

## 功能

- **资源站聚合**：导入 JSON 站源，检测连通性与搜索能力，选择默认源，搜索影片和查看分集。
- **自动追更**：按计划检查新集，可自动下载，也可仅记录更新。
- **下载队列**：限制同时下载数量和分片并发，支持暂停、继续、重试、换线路、校正季号，以及批量管理。
- **媒体整理**：调用 FFmpeg 复制媒体流并封装 MP4，由 FFprobe 校验，按剧名与季度归档，补全 NFO 和海报。
- **Emby 入库**：发布媒体后请求扫描，继续检查 Emby 是否已识别为本地 `File` 媒体源。
- **运维**：JSON 状态持久化、磁盘空间保护、临时文件清理、systemd 管理、校验后升级和失败回滚。

浏览器可以预览站源 HLS；播放请求由浏览器直接发往站源，受站源跨域策略和客户端网络影响。下载完成后的主要播放入口是 Emby，服务端不对媒体转码。

## 快速运行

### Linux 正式版

支持 `amd64` 和 `arm64`。在新的空目录运行以下命令，服务器需预先安装 FFmpeg、FFprobe；systemd 不是手动启动的必要条件。

```bash
mkdir shipin-quickstart
cd shipin-quickstart
set -euo pipefail

version=v0.5.0
case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  *) echo "不支持的 CPU 架构"; exit 1 ;;
esac

release_url="https://github.com/lonnnnnng/shipin/releases/download/$version"
curl --fail --location "$release_url/shipin-linux-$arch" -o shipin
curl --fail --location "$release_url/SHA256SUMS" -o SHA256SUMS
# long: 缺项、重复项或格式错误都必须中止，防止空输入绕过二进制校验。
awk -v asset="shipin-linux-$arch" '
  $2 == asset {
    count++
    if (count > 1 || length($1) != 64 || $1 ~ /[^[:xdigit:]]/) exit 1
    print $1 "  shipin"
  }
  END { if (count != 1) exit 1 }
' SHA256SUMS | sha256sum --check --strict -
chmod 0755 shipin
mkdir -p data media
./shipin --listen 127.0.0.1:4444 --data-dir ./data --media-dir ./media
```

打开 `http://127.0.0.1:4444/`。需要从局域网其他设备访问时，将 `--listen` 改为服务器的内网 IP，例如 `192.168.1.2:4444`。运行用户必须能读写数据和媒体目录。

### 从源码运行

需要 Go 1.25+。前端已嵌入程序，运行不需要 Node.js 或单独构建网页。

```bash
git clone https://github.com/lonnnnnng/shipin.git
cd shipin
go build -trimpath -o ./bin/shipin ./cmd/shipin
./bin/shipin --listen 127.0.0.1:4444 --data-dir ./data --media-dir ./media
```

macOS 也可执行 `./scripts/build.sh` 和 `./scripts/run.sh`；修改源码后重新构建再启动。

## 使用流程

1. 打开“资源站”，刷新清单并检测可用性，按需设置默认源。
2. 在首页找剧，打开详情后核对线路和季号，选择要下载的分集或加入追更。
3. 在下载队列查看进度与失败原因，按需重试、调整线路或批量管理任务。
4. 在 Emby 创建“电视节目”媒体库，指向与 shipin 共享的媒体目录。
5. 在 shipin 设置中填写 Emby 地址和 API Key，启用自动扫描，检查队列中的入库识别结果。

Emby 必须能够遍历剧集目录并读取 MP4、NFO 与图片。容器部署时两边需要挂载同一批媒体文件。扫描请求成功表示 Emby 接受了刷新，实际识别完成时间由 Emby 决定。

## 配置与文件

| 参数 | 默认值 | 用途 |
| --- | --- | --- |
| `--listen` | `127.0.0.1:4444` | HTTP 监听地址 |
| `--data-dir` | `./data` | 状态文件目录，生产部署建议用固定绝对路径 |
| `--media-dir` | `./media` | 首次启动的媒体目录；已有配置以保存的设置为准 |

下载并发、分片线程、重试次数、追更间隔、FFmpeg/FFprobe 路径及 Emby 连接参数在管理台设置。

平铺部署可采用以下布局；这是新部署示例，已有服务器的路径不会随仓库改名自动变化：

```text
shipin/
├── shipin
├── shipin-service.sh
├── shipin-update.py
├── data/
│   ├── settings.json
│   ├── sources.json
│   ├── follows.json
│   ├── jobs.json
│   └── emby.json
└── media/
```

管理脚本从仓库 `scripts/` 复制，两份脚本须放在一起。新部署默认管理 `shipin.service` 用户服务，也可通过 `SHIPIN_*` 变量选择系统服务和其他路径，详见[服务与升级](docs/service-management.md)。

状态与媒体需要独立备份。程序更新不替代数据备份；批量删除默认保留媒体文件，勾选删除文件前请核对确认框中的任务清单。

## 从旧版升级

`v0.5.0` 起，仓库、命令、管理脚本和 Linux 产物统一使用 `shipin`。新产物为 `shipin-linux-amd64`、`shipin-linux-arm64` 和 `SHA256SUMS`。

旧版更新器固定校验原仓库路径和资产名，不能直接通过原来的“检测更新”入口跨过这次改名。首次迁移需使用新版 `shipin-update.py`，或校验下载后手动更换程序，具体步骤见[旧版迁移](docs/service-management.md#从旧版迁移)。

既有 JSON 状态、MP4、`.moviehub/` 暂存目录及 `.moviehub.json` 收据继续兼容；不要为了改名移动媒体目录或修改收据。任务中保留了绝对媒体路径。新配置使用 `SHIPIN_*`，同时保留 `MOVIEHUB_*` 环境变量作为兼容回退，新变量优先。

## 开发与发布

```bash
go test ./...
go test -race ./...
go vet ./...
SHIPIN_VERSION=v0.5.0 ./scripts/build-linux.sh
```

发布由正式版本标签触发 GitHub Actions。流水线检查代码、构建双架构程序、生成 SHA256 校验文件，先上传草稿并回验，再公开 Release 并再次下载核验。完整步骤见[发版流程](docs/release.md)。发布与更新生产服务器是两个独立操作。
