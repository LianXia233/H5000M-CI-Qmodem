#!/bin/bash
# SPDX-License-Identifier: MIT
# 安装宿主 rustup（仅当缺失时执行）。
#
# CI 下载统一走 FluxDown（见 .github/actions/fluxdown-download）：
# rustup-init 从 static.rust-lang.org 分段下载，摘要取自同目录的 .sha256 清单；
# 安装完成后的工具链 / target 组件下载仍由 rustup 自身完成。
set -euo pipefail

if command -v rustup >/dev/null 2>&1; then
	exit 0
fi

command -v fluxdown >/dev/null 2>&1 || {
	echo "::error::未找到 fluxdown CLI；CI 中应由 .github/actions/fluxdown-download 步骤安装" >&2
	exit 1
}

TRIPLE="x86_64-unknown-linux-gnu"
BASE="https://static.rust-lang.org/rustup/dist/${TRIPLE}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> 安装 rustup（FluxDown）"
SHA="$(curl -fsSL --retry 3 --retry-all-errors --max-time 60 "${BASE}/rustup-init.sha256")" || {
	echo "::error::获取 rustup-init.sha256 失败" >&2
	exit 1
}
SHA="${SHA%% *}"
[ -n "$SHA" ] || { echo "::error::rustup-init.sha256 内容为空" >&2; exit 1; }

fluxdown add --local -d "$TMP" -o rustup-init -s 1 \
	--checksum "sha256=${SHA}" "${BASE}/rustup-init" \
	|| { echo "::error::rustup-init 下载失败" >&2; exit 1; }

chmod +x "$TMP/rustup-init"
"$TMP/rustup-init" -y --profile minimal --default-toolchain stable --no-modify-path
