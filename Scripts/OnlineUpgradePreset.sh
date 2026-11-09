#!/bin/bash
# SPDX-License-Identifier: MIT
# 按机型生成 luci-app-online-upgrade 的出厂预设（/etc/config/online-upgrade）
#
# 为什么在构建期生成而不是每机型提交一份静态文件：
#   升级源里「哪个 Release / 哪个资产」取决于运行期变量 —— WRT_CONFIG 同时
#   决定 Release 归组（H5000M-qmodem / H5000M-qmodem-next / X86-qmodem-next ...）
#   与产物文件名前缀（<WRT_CONFIG>-<YYYYMMDD>-...）。静态文件无法覆盖
#   「同一份配置换源码分支编译」的组合，构建期生成则与本次产物一一对应。
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
#   rust/src/upgrade.rs      expected_sha256（自定义校验值，留空则用 Release 的）
# 上游默认配置里的 enabled / keep_config / last_upgrade_version 在本版本 Rust 与
# rpcd 代码中均未被读取，故不写入预设，避免「配了却不起作用」的假象。
#
# SHA256 不写进预设：expected_sha256 是「本次 Release 的固定值」，出厂固化会让
# 之后每个版本都拿旧哈希去比对。WRT-CORE 改为把每个固件的 sha256sum 写进
# Release 正文，上游 github.rs 的 find_sha256_in_text 会按资产名自动取到，
# 既不新增资产、也不占用 UCI 键。
#
# 用法（在 OpenWrt 源码树根目录，defconfig 之前由 Settings.sh 调用）：
#   Scripts/OnlineUpgradePreset.sh

set -euo pipefail

WRT_CONFIG="${WRT_CONFIG:-}"
WRT_INFO="${WRT_INFO:-}"
WRT_BRANCH="${WRT_BRANCH:-}"
TARGET="./files/etc/config/online-upgrade"
# 与 GitHub 上的仓库名大小写保持一致（API 不区分大小写，预设里不留歧义）
UPGRADE_REPO="${ONLINE_UPGRADE_SOURCE_REPO:-LianXia233/H5000M-CI-Qmodem}"

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
# 与 WRT-CORE「Package Firmware」保持一致：资产名统一为
#   <WRT_CONFIG>-<YYYYMMDD>[-<镜像类型>].<扩展名>
# WRT_CONFIG 即 "<机型>-<模组插件>"（如 H5000M-qmodem-next），正则直接锚定
# 配置名即可天然隔离同机型三套变体，不再需要从 .config 的 TARGET_DEVICE
# 反推平台前缀（旧规则无法区分变体，且换源码分支就要跟着改）。
# 日期用 [0-9]+ 而非写死 8 位，便于兼容过渡期混合命名的 Release。
case "$WRT_CONFIG" in
	X86-*)
		# 默认取 UEFI 镜像：现代小主机/软路由主流引导方式；BIOS/Legacy 机器
		# 需把 combined-efi 改成 combined —— 两种镜像分区表不同，不能混用。
		PATTERN="^${WRT_CONFIG}-[0-9]+-combined-efi\\.img\\.gz\$"
		;;
	*)
		PATTERN="^${WRT_CONFIG}-[0-9]+-sysupgrade\\.bin\$"
		;;
esac

# tag 语义来自 rust/src/github.rs：latest 取最新 Release，
# latest@<正则> 只在该正则匹配的 Tag 里找最新。
#   Release 标签格式为 <WRT_CONFIG>-<WRT_INFO>-<WRT_BRANCH>-<WRT_DATE>。
# 三段锚定的必要性：
#   - 只写 ^<WRT_CONFIG>- 会让 H5000M-qmodem 命中 H5000M-qmodem-next 的发布
#     （前者是后者的字符串前缀）；
#   - 追加 <WRT_INFO>-（源码 owner）后两者不再互相误匹配；
#   - 再追加 <WRT_BRANCH>- 可防止同一 owner 换分支编译时跨分支取最新。
# 分支名可能含点（如 openwrt-24.10），正则里 . 是通配符，需转义成 \. 。
BRANCH_RE="${WRT_BRANCH//./\\.}"
if [ -n "$BRANCH_RE" ]; then
	TAG="latest@^${WRT_CONFIG}-${WRT_INFO}-${BRANCH_RE}-"
else
	# 非 CI 手动调用、未提供分支时退回两段锚定，仍不会跨变体误匹配
	TAG="latest@^${WRT_CONFIG}-${WRT_INFO}-"
fi

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
grep -qF "option repo '${UPGRADE_REPO}'" "$TARGET" || {
	echo "::error::${TARGET} 的 repo 与推导值不一致"
	exit 1
}

# 正则自检：构造示例产物名 / 示例标签，确认两条规则真能命中，
# 避免上游 Regex::new 编译失败或锚点写错导致设备端 OTA 找不到固件。
case "$WRT_CONFIG" in
	X86-*) SAMPLE="${WRT_CONFIG}-20261109-combined-efi.img.gz" ;;
	*)     SAMPLE="${WRT_CONFIG}-20261109-sysupgrade.bin" ;;
esac
if [[ ! "$SAMPLE" =~ $PATTERN ]]; then
	echo "::error::firmware_pattern 未匹配示例产物 ${SAMPLE}（规则=${PATTERN}）"
	exit 1
fi
SAMPLE_TAG="${WRT_CONFIG}-${WRT_INFO}-${WRT_BRANCH:-master}-26.11.09-08.31.52"
if [[ ! "$SAMPLE_TAG" =~ ${TAG#latest@} ]]; then
	echo "::error::tag 正则未匹配示例标签 ${SAMPLE_TAG}（规则=${TAG}）"
	exit 1
fi

echo "==> 在线升级预设：机型=${WRT_CONFIG} tag正则=${TAG} 资产正则=${PATTERN}"
