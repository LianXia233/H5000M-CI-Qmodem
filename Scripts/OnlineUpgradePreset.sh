#!/bin/bash
# SPDX-License-Identifier: MIT
# 按机型生成 luci-app-online-upgrade 的出厂预设（/etc/config/online-upgrade）
#
# 为什么在构建期生成而不是每机型提交一份静态文件：
#   升级源里「哪个 Release / 哪个资产」取决于运行期变量 —— WRT_CONFIG 决定
#   Release 归组（H5000M-qmodem / H5000M-qmodem-next / X86-qmodem-next ...），
#   .config 里的 TARGET_DEVICE 决定资产名前缀（hiveton_h5000m / airpi_ap3000m /
#   x86-64-generic）。静态文件无法覆盖「同一份配置换源码分支编译」的组合，
#   构建期生成则与本次产物一一对应。
#
# 落点遵循仓库既有 overlay 约定：$(TOPDIR)/files 会被原样并入 rootfs，
# Scripts/Settings.sh 也已用 ./files/etc/uci-defaults 生成无线种子。
# 因此这里写 ./files/etc/config/online-upgrade，覆盖包自带的同名 conffile，
# 首次开机即为对应机型的升级源；用户在 LuCI 里改过后由 keep.d 保留。
#
# 键名全部取自上游代码，不是猜测：
#   rust/src/uci.rs          const BASE = "online-upgrade.settings"
#   rust/src/github.rs       repo / tag / proxy / firmware_pattern / min_size_mb
#   rust/src/downloader.rs   dl_workers / dl_chunk_mb / dl_stall_sec / dl_retries
#   rust/src/upgrade.rs      expected_sha256（自定义校验值，留空则用 Release 资产的）
# 上游默认配置里的 enabled / keep_config / last_upgrade_version 在本版本 Rust 与
# rpcd 代码中均未被读取，故不写入预设，避免「配了却不起作用」的假象。
#
# 用法（在 OpenWrt 源码树根目录，defconfig 之前由 Settings.sh 调用）：
#   Scripts/OnlineUpgradePreset.sh

set -euo pipefail

WRT_CONFIG="${WRT_CONFIG:-}"
WRT_INFO="${WRT_INFO:-}"
TARGET="./files/etc/config/online-upgrade"
UPGRADE_REPO="${ONLINE_UPGRADE_SOURCE_REPO:-LianXia233/H5000M-CI-QModem}"

# 包未选中时不生成预设：文件会随 files/ 打进固件，但设备上没有对应软件，
# 只会留下一个没人读的配置。Config/GENERAL.txt 默认选中它，这里只是防御。
if [ -f ./.config ] && ! grep -q '^CONFIG_PACKAGE_luci-app-online-upgrade=y' ./.config; then
	echo "==> luci-app-online-upgrade 未选中，跳过升级预设生成"
	exit 0
fi

if [ -z "$WRT_CONFIG" ] || [ -z "$WRT_INFO" ]; then
	echo "::warning::WRT_CONFIG / WRT_INFO 缺失（非 CI 环境？），跳过升级预设生成"
	exit 0
fi

# ===== 资产名规则 =====
# 取自 WRT-CORE「Package Firmware」：资产名为
#   <TARGET_DIR>-<SUBTARGET>-<DEVICE>-squashfs-sysupgrade-<INFO>-<BRANCH>-<WIFI>-<DATE>.bin
# （x86 为 <TARGET>-<SUBTARGET>-generic-squashfs-combined-efi-…img.gz）。
# 因此从 .config 的 TARGET_DEVICE 反推前缀，与真实产物保持一致。
PATTERN=""

if grep -q '^CONFIG_TARGET_x86=y' ./.config 2>/dev/null; then
	# x86/64 用 ALL_PROFILES，.config 里没有 TARGET_DEVICE 行。
	# 默认取 UEFI 镜像：现代小主机/软路由主流引导方式；BIOS/Legacy 机器需把
	# firmware_pattern 改成 ^x86-64-generic-squashfs-combined-.*\.img\.gz$ ——
	# 两种镜像的分区表不同，不能混用。
	PATTERN='^x86-64-generic-squashfs-combined-efi-.*\.img\.gz$'
else
	DEVICE_LINE="$(grep -m1 -oE '^CONFIG_TARGET_DEVICE_[A-Za-z0-9_]+=y' ./.config || true)"
	if [ -n "$DEVICE_LINE" ]; then
		KEY="${DEVICE_LINE#CONFIG_TARGET_DEVICE_}"
		KEY="${KEY%=y}"
		# KEY 形如 <target>_<subtarget>_DEVICE_<device>，设备名本身可能含下划线
		TARGET_PREFIX="${KEY%%_DEVICE_*}"
		DEVICE_NAME="${KEY#*_DEVICE_}"
		TARGET_PREFIX="$(printf '%s' "$TARGET_PREFIX" | tr '_' '-')"
		PATTERN="^${TARGET_PREFIX}-${DEVICE_NAME}-squashfs-sysupgrade-.*\\.bin\$"
	fi
fi

if [ -z "$PATTERN" ]; then
	# 兜底：未知平台只按 sysupgrade.bin 结尾匹配，并明确告警要求人工核对。
	echo "::warning::无法从 .config 推导机型资产前缀（WRT_CONFIG=${WRT_CONFIG}），使用通用 sysupgrade 正则"
	PATTERN='-squashfs-sysupgrade-.*\.bin$'
fi

# tag 语义来自 rust/src/github.rs：latest 取最新 Release，
# latest@<正则> 只在该正则匹配的 Tag 里找最新。
# 这里锚定「配置名-源码 owner-」：
#   Release 标签格式为 <WRT_CONFIG>-<WRT_INFO>-<WRT_BRANCH>-<WRT_DATE>；
#   只写 ^<WRT_CONFIG>- 会让 H5000M-qmodem 命中 H5000M-qmodem-next 的发布
#   （前者是后者的字符串前缀），加上 <WRT_INFO>- 后两者不会互相误匹配。
TAG="latest@^${WRT_CONFIG}-${WRT_INFO}-"

mkdir -p "$(dirname "$TARGET")"
{
	printf '# 出厂预设：构建期由 Scripts/OnlineUpgradePreset.sh 按机型生成，勿手改\n'
	printf "config online-upgrade 'settings'\n"
	printf "\toption repo '%s'\n" "$UPGRADE_REPO"
	printf "\toption tag '%s'\n" "$TAG"
	printf "\toption firmware_pattern '%s'\n" "$PATTERN"
	printf "\toption min_size_mb '15'\n"
	printf "\toption proxy 'https://gh.acg2.mom/'\n"
	printf "\toption expected_sha256 ''\n"
	printf "\toption dl_workers '6'\n"
	printf "\toption dl_chunk_mb '4'\n"
	printf "\toption dl_stall_sec '30'\n"
	printf "\toption dl_retries '3'\n"
} > "$TARGET"

# 生成后自检：10 个键一个不少，且关键项与推导值一致。
# 任何一项不匹配都说明模板被改坏，直接红掉而不是带着坏预设编译。
EXPECT_KEYS=10
GOT_KEYS=$(grep -c '^[[:space:]]*option ' "$TARGET" || true)
if [ "$GOT_KEYS" -ne "$EXPECT_KEYS" ]; then
	echo "::error::${TARGET} 生成异常：期望 ${EXPECT_KEYS} 个 option，实际 ${GOT_KEYS}"
	exit 1
fi
grep -qF "option tag '${TAG}'" "$TARGET" || {
	echo "::error::${TARGET} 的 tag 与推导值不一致"
	exit 1
}
grep -qF "option firmware_pattern '${PATTERN}'" "$TARGET" || {
	echo "::error::${TARGET} 的 firmware_pattern 与推导值不一致"
	exit 1
}

echo "==> 在线升级预设：机型=${WRT_CONFIG} tag正则=${TAG} 资产正则=${PATTERN}"
