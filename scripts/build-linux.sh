#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# long: 新名称优先，旧变量继续支持已有构建环境，避免改名时丢失版本注入。
dist_dir="${SHIPIN_DIST_DIR:-${MOVIEHUB_DIST_DIR:-${project_root}/dist}}"
version="${SHIPIN_VERSION:-${MOVIEHUB_VERSION:-dev}}"
release_time="${SHIPIN_RELEASE_TIME:-${MOVIEHUB_RELEASE_TIME:-}}"
mkdir -p "$dist_dir"

# long: 一次生成两种常见 Linux 架构的静态程序，部署机无需 Go 工具链或 CGO 运行库。
for arch in amd64 arm64; do
  output="${dist_dir}/shipin-linux-${arch}"
  CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go -C "$project_root" build -trimpath -ldflags "-X shipin/internal/hub.Version=${version} -X shipin/internal/hub.ReleaseTime=${release_time}" -o "$output" ./cmd/shipin
  printf '已构建：%s\n' "$output"
done

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$dist_dir" && sha256sum shipin-linux-amd64 shipin-linux-arm64 > SHA256SUMS)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$dist_dir" && shasum -a 256 shipin-linux-amd64 shipin-linux-arm64 > SHA256SUMS)
else
  printf '缺少 sha256sum 或 shasum，无法生成部署校验文件\n' >&2
  exit 1
fi
printf '校验文件：%s/SHA256SUMS\n' "$dist_dir"
