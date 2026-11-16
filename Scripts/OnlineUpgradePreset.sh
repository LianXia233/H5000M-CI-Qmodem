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
# v2.7 三仓库统一命名：<WRT_CONFIG>-<架构>-<YY.MM.DD>-<类型>.<扩展名>
# WRT_CONFIG 即 "<机型>-<模组插件>"（如 H5000M-qmodem-next），正则锚定它即可
# 隔离同机型三套变体。日期用点分 [0-9.]+ 兼容新旧过渡（旧格式为 8 位紧凑），
# 架构段用 (aarch64|x86-64) 精确声明，供升级插件 compat 判定。
WRT_ARCH="${WRT_ARCH:-aarch64}"
case "$WRT_CONFIG" in
	X86-*)
		# 默认取 UEFI 镜像：现代小主机/软路由主流引导方式；BIOS/Legacy 机器
		# 需把 combined-efi 改成 combined —— 两种镜像分区表不同，不能混用。
		PATTERN="^${WRT_CONFIG}-${WRT_ARCH}-[0-9.]+-combined-efi\\.img\\.gz\$"
		;;
	*)
		PATTERN="^${WRT_CONFIG}-${WRT_ARCH}-[0-9.]+-sysupgrade\\.bin\$"
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
# v2.7 统一规则：TAG 追踪模式与过滤正则解耦（与另两个 CI 仓库一致）。
#   tag      = latest
#   tag_rule = ^<WRT_CONFIG>-<WRT_INFO>-<BRANCH>-
BRANCH_RE="${WRT_BRANCH//./\\.}"
if [ -n "$BRANCH_RE" ]; then
	TAG_RULE="^${WRT_CONFIG}-${WRT_INFO}-${BRANCH_RE}-"
else
	TAG_RULE="^${WRT_CONFIG}-${WRT_INFO}-"
fi
TAG='latest'

mkdir -p "$(dirname "$TARGET")"
{
	printf '# 出厂预设：构建期由 Scripts/OnlineUpgradePreset.sh 按机型生成，勿手改\n'
	printf "config online-upgrade 'settings'\n"
	printf "\toption repo '%s'\n" "$UPGRADE_REPO"
	printf "\toption tag '%s'\n" "$TAG"
	printf "\toption tag_rule '%s'\n" "$TAG_RULE"
	printf "\toption firmware_pattern '%s'\n" "$PATTERN"
	printf "\toption min_size_mb '15'\n"
	printf "\toption proxy 'https://gh.acg2.mom/'\n"
	printf "\toption expected_sha256 ''\n"
	printf "\toption dl_workers '6'\n"
	printf "\toption dl_chunk_mb '4'\n"
	printf "\toption dl_stall_sec '30'\n"
	printf "\toption dl_retries '3'\n"
} > "$TARGET"

# 生成后自检：11 个键一个不少，且关键项与推导值一致。
EXPECT_KEYS=11
GOT_KEYS=$(grep -c '^[[:space:]]*option ' "$TARGET" || true)
if [ "$GOT_KEYS" -ne "$EXPECT_KEYS" ]; then
	echo "::error::${TARGET} 生成异常：期望 ${EXPECT_KEYS} 个 option，实际 ${GOT_KEYS}"
	exit 1
fi
grep -qF "option tag '${TAG}'" "$TARGET" || {
	echo "::error::${TARGET} 的 tag 与推导值不一致"
	exit 1
}
grep -qF "option tag_rule '${TAG_RULE}'" "$TARGET" || {
	echo "::error::${TARGET} 的 tag_rule 与推导值不一致"
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
	X86-*) SAMPLE="${WRT_CONFIG}-${WRT_ARCH}-26.11.09-combined-efi.img.gz" ;;
	*)     SAMPLE="${WRT_CONFIG}-${WRT_ARCH}-26.11.09-sysupgrade.bin" ;;
esac
if [[ ! "$SAMPLE" =~ $PATTERN ]]; then
	echo "::error::firmware_pattern 未匹配示例产物 ${SAMPLE}（规则=${PATTERN}）"
	exit 1
fi
SAMPLE_TAG="${WRT_CONFIG}-${WRT_INFO}-${WRT_BRANCH:-master}-26.11.09-08.31.52"
if [[ ! "$SAMPLE_TAG" =~ $TAG_RULE ]]; then
	echo "::error::tag_rule 正则未匹配示例标签 ${SAMPLE_TAG}（规则=${TAG_RULE}）"
	exit 1
fi

# ---- 固件版本标记：自动注入 /etc/online-upgrade/firmware-version ----
# luci-app-online-upgrade 读取它作为本机固件版本的强依据（basis_score 85 起），
# 避免只用构建时间/过期锚点推断而显示「判定依据较弱」。
# 结构化格式（shell key=value，字段名稳定；与 /etc/os-release 风格一致）：
#   DEVICE='H5000M'                       机型
#   ARCH='aarch64'                        目标架构
#   BUILD_TIME='2026-11-17T01:35:20+08:00' 完整编译时间（秒 + 时区）
#   BUILD_SEQ='3'                         当天第几次编译（见下）
#   VERSION='26.11.17'                    版本（与 tag/资产同源）
# 插件只从 VERSION 字段取版本，其余字段进判定依据展示，不改变版本比较。
# 兼容：字段缺失时插件逐级降级（缺 VERSION 才回退整段文本当纯版本号）。
#
# 版本：三仓库变量名不统一（本仓库/H5000M 用 WRT_DATE_DOT，OpenWRT-CI 用
# WRT_DATE_SHORT），逐个尝试并校验 YY.MM.DD 形状，都缺失时 UTC+8 现算兜底。
FW_VERSION=""
for cand in "${WRT_DATE_DOT:-}" "${WRT_DATE_SHORT:-}" "$(TZ=UTC-8 date +'%y.%m.%d')"; do
	case "$cand" in
		[0-9][0-9].[0-9][0-9].[0-9][0-9]) FW_VERSION="$cand"; break ;;
	esac
done
if [ -z "$FW_VERSION" ]; then
	echo "::error::无法生成固件版本标记 VERSION（期望 YY.MM.DD），停止构建"
	exit 1
fi

# 机型 / 架构：由本 workflow 的构建变量提供；缺失时按已知约定回退。
FW_DEVICE="${WRT_CONFIG:-unknown}"
FW_ARCH="${WRT_ARCH:-aarch64}"

# 完整编译时间：精确到秒，显式标注 UTC+8（Asia/Shanghai）时区。
if FW_BUILD_TIME="$(TZ=UTC-8 date +'%Y-%m-%dT%H:%M:%S+08:00' 2>/dev/null)" && [ -n "$FW_BUILD_TIME" ]; then
	:
else
	FW_BUILD_TIME="$(date -u +'%Y-%m-%dT%H:%M:%S+00:00')"
fi

# 当天第几次编译：用 GitHub run_id（全局唯一、单调，重跑不变 → 可重复，
# 不同 run 不撞号）；本地手跑回退 UTC+8 秒级时间戳。详见 OpenWRT-CI 同段说明。
FW_BUILD_SEQ="seq-${GITHUB_RUN_ID:-$(TZ=UTC-8 date +'%Y%m%d%H%M%S' 2>/dev/null || date -u +'%Y%m%d%H%M%S')}"

FW_MARKER_DIR="./files/etc/online-upgrade"
FW_MARKER="$FW_MARKER_DIR/firmware-version"
mkdir -p "$FW_MARKER_DIR"
{
	printf "DEVICE='%s'\n" "$FW_DEVICE"
	printf "ARCH='%s'\n" "$FW_ARCH"
	printf "BUILD_TIME='%s'\n" "$FW_BUILD_TIME"
	printf "BUILD_SEQ='%s'\n" "$FW_BUILD_SEQ"
	printf "VERSION='%s'\n" "$FW_VERSION"
} > "$FW_MARKER"
grep -qF "VERSION='${FW_VERSION}'" "$FW_MARKER" || {
	echo "::error::${FW_MARKER} 的 VERSION 写入失败（期望 ${FW_VERSION}）"
	exit 1
}
if grep -qE "^[A-Z_]+='[^']*$" "$FW_MARKER"; then
	echo "::error::${FW_MARKER} 存在未闭合的字段值"
	exit 1
fi

echo "==> 在线升级预设：机型=${WRT_CONFIG} tag规则=${TAG_RULE} 资产正则=${PATTERN}"
echo "==> 固件版本标记：${FW_MARKER} DEVICE=${FW_DEVICE} ARCH=${FW_ARCH} BUILD_TIME=${FW_BUILD_TIME} BUILD_SEQ=${FW_BUILD_SEQ} VERSION=${FW_VERSION}"
