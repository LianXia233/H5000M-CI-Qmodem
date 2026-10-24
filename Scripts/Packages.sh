#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

# 任何克隆 / 解包 / feed 注册失败都必须让 CI 立即失败。
# 之前的实现没有 set -e：REGISTER_QMODEM_FEED 等函数内部虽然 return 1，
# 但调用处是普通语句，失败后脚本继续执行，最终退出码取自末尾的 PRIVATE.sh 判断，
# 于是"QModem 未进固件"的构建仍显示成功。
set -e -o pipefail

#安装和更新软件包
UPDATE_PACKAGE() {
	local PKG_NAME=$1
	local PKG_REPO=$2
	local PKG_BRANCH=$3
	local PKG_SPECIAL=$4
	local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
	local REPO_NAME=${PKG_REPO#*/}

	echo " "

	# 删除本地可能存在的不同名称的软件包
	for NAME in "${PKG_LIST[@]}"; do
		# 查找匹配的目录
		echo "Search directory: $NAME"
		local FOUND_DIRS=$(find ../feeds/luci/ ../feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

		# 删除找到的目录
		if [ -n "$FOUND_DIRS" ]; then
			while read -r DIR; do
				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	# 克隆 GitHub 仓库
	if ! git clone --depth=1 --single-branch --branch "$PKG_BRANCH" "https://github.com/$PKG_REPO.git"; then
		echo "::error title=Package clone failed::无法克隆 $PKG_REPO（分支 $PKG_BRANCH），构建中止"
		return 1
	fi

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		local MATCHES
		MATCHES=$(find "./$REPO_NAME"/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune 2>/dev/null || true)
		if [ -z "$MATCHES" ]; then
			echo "::error title=Package extraction failed::$PKG_REPO 中未找到匹配 '$PKG_NAME' 的软件包目录"
			return 1
		fi
		while read -r DIR; do
			[ -n "$DIR" ] && cp -rf "$DIR" ./
		done <<< "$MATCHES"
		rm -rf "./$REPO_NAME/"
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f "$REPO_NAME" "$PKG_NAME"
	elif [[ "$PKG_SPECIAL" == "all" ]]; then
		find "./$REPO_NAME/" -mindepth 1 -maxdepth 1 -type d -exec cp -rf {} ./ +
		rm -rf "./$REPO_NAME/"
	fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg/name/all，可选，pkg为提取匹配包；name为重命名；all为提取全部一级包"
# 主题：保留 aurora（默认）与 argon（含配套修复），其余精简
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "luci-app-tailscale" "asvow/luci-app-tailscale" "main"

#UPDATE_PACKAGE "athena-led" "unraveloop/JDC-AX6600-Athena-LED-Controller" "main"
UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
# QModem 仓库按 feed（src-git）设计：顶层没有 Makefile，包分散在 application/、luci/、
# driver/ 等二级目录。若只把克隆目录放进 package/，构建系统虽然能递归扫描到二级
# Makefile，但会把它们当作 core package；随后 feeds install 因 "Not overriding core
# package" 拒绝创建链接，defconfig 阶段 CONFIG_PACKAGE_luci-app-qmodem* / qmodem /
# sms-forwarder-next 等符号被静默丢弃，固件里没有 qmodem。这里仿照上游 CI 的
# src-link 方式把克隆目录注册为本地 feed，scripts/feeds 会把各包链接到
# package/feeds/qmodem/ 下。
# feeds 目录在 WRT-CORE 的 Update Feeds 步骤已就绪，此处仅增量处理 qmodem feed。
REGISTER_QMODEM_FEED() {
	# 先把克隆目录移出 package/：否则 package/ 主扫描会提前命中 QModem 二级目录里的
	# Makefile（application/*、luci/*），把 luci-app-qmodem / qmodem 等注册为 core
	# package，feeds install 时 "Not overriding core package" 直接跳过链接。
	if [ -d "./QModem" ] && [ -d "../QModem" ]; then
		echo "::error title=Stale QModem checkout::package/QModem 与 ../QModem 同时存在，无法确定使用哪一份"
		return 1
	fi
	if [ -d "./QModem" ]; then
		mv -f ./QModem ../QModem
		echo "qmodem: 克隆目录已移出 package/ 至 ../QModem"
	fi
	local QMODEM_DIR="../QModem"
	if [ ! -d "$QMODEM_DIR" ]; then
		echo "::error title=QModem feed missing::QModem 克隆目录不存在，拒绝继续构建（固件将不含 qmodem 包）"
		return 1
	fi

	# scripts/feeds 的解析顺序：feeds.conf 存在则完全替代 feeds.conf.default
	local FEEDS_CONF="../feeds.conf"
	if [ ! -f "$FEEDS_CONF" ]; then
		FEEDS_CONF="../feeds.conf.default"
	fi
	if [ ! -f "$FEEDS_CONF" ]; then
		echo "::error title=Feeds config missing::../feeds.conf 与 ../feeds.conf.default 均不存在"
		return 1
	fi

	# src-link 的目标按原样传给 ln -s，必须用绝对路径
	local QMODEM_ABS
	QMODEM_ABS="$(cd "$QMODEM_DIR" && pwd)"
	if ! grep -q "^src-link qmodem " "$FEEDS_CONF" 2>/dev/null; then
		echo "src-link qmodem $QMODEM_ABS" >> "$FEEDS_CONF"
	fi

	# src-link 的 update 为空操作，只会创建 feeds/qmodem -> 克隆目录 的链接
	if ! ( cd .. && ./scripts/feeds update qmodem && ./scripts/feeds install -a -p qmodem ); then
		echo "::error title=QModem feed registration failed::scripts/feeds 无法注册 qmodem feed（固件将不含 qmodem 包）"
		return 1
	fi
	echo "qmodem: 已注册为本地 feed 并安装到 package/feeds/qmodem/"
}

# QModem 包共用 version.mk 的 QMODEM_VERSION。
# OpenWrt 新版 apk 打包器不接受 `-rc.N` / `-rcN`：版本串被拼成 "3.4.0-rc.3-rN" 后，
# apk mkpkg 报 "package version is invalid"（Error 99），阻断整个固件构建。
# 这里在克隆后把 X.Y.Z-rc.N / X.Y.Z-rcN 改写为 apk 合法的 X.Y.Z_rcN；
# QModem 各包源码均内嵌仓库 src/，无版本化下载依赖，改写只影响包版本元数据。
# 上游当前版本为 3.4.0_rc3（已合法），函数会自动跳过；保留它是为了在上游回退
# 到旧版本格式时仍能构建，不要删除。
FIX_QMODEM_VERSION() {
	local VER_FILE="../QModem/version.mk"
	[ -f "$VER_FILE" ] || { echo "qmodem: version.mk not found, skip"; return 0; }
	if grep -qE '^QMODEM_VERSION:=[0-9]+\.[0-9]+\.[0-9]+-rc\.?[0-9]+$' "$VER_FILE"; then
		sed -i -E 's/^(QMODEM_VERSION:=)([0-9]+\.[0-9]+\.[0-9]+)-rc\.?([0-9]+)$/\1\2_rc\3/' "$VER_FILE"
		echo "qmodem: QMODEM_VERSION sanitized to $(grep -E '^QMODEM_VERSION:=' "$VER_FILE")"
	else
		echo "qmodem: QMODEM_VERSION already apk-valid, no change"
	fi
}

# *-modem-pro 使用独立的 modem-pro-unified 方案，绝不能拉取 QModem：
# QModem feed 会带来 qmodem 核心、两套前端及短信栈的包元数据，虽然 MODEM-PRO.txt
# 已将它们设为 n，但克隆与 feed 注册仍会污染包索引、增加扫描时间，并可能在
# 上游依赖变化时被意外选中（例如 qmodem-generic 的 DEPENDS:=+qmodem）。
# 因此在源头按配置隔离，Modem Pro 构建完全不接触 QModem 仓库。
if [[ "${WRT_CONFIG:-}" != *modem-pro ]]; then
	# 所有 QModem 变体共用核心脚本包；前端由 QMODEM*.txt 选择
	UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
	REGISTER_QMODEM_FEED
	FIX_QMODEM_VERSION

	# 通用 QModem 管理界面（依赖 qmodem 核心），Modem Pro 配置不编入
	UPDATE_PACKAGE "luci-app-qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"
else
	echo "modem-pro: 跳过 QModem 克隆、feed 注册与 luci-app-qmodem-generic（隔离 QModem 依赖链）"
fi

# ===== modem-pro-unified：单一包 modem-pro（H5000M / AP3000M 共用，替代 QModem 模组管理）=====
# 仓库顶层即唯一 Makefile，包位于 feed 根目录。但 OpenWrt 的 scripts/feeds 扫描要求包
# Makefile 位于 feed 的【子目录】下（feed_dir/<pkg>/Makefile）——直接用 src-link 指向
# 仓库根时，scan.mk 的路径截断逻辑会把 `call BuildPackage` 的 grep 输出误当包路径，
# 报 "target pattern contains no '%'"，install 阶段也找不到包（No feed for package）。
# 故先把克隆目录整理成一个规范 feed：feed 根 ../modem-pro-feed 下放 modem-pro/ 子目录，
# 再以 src-link 注册（feed 名只允许 [A-Za-z0-9_]，故用 modem_pro）。
# 仅 *-modem-pro 配置引入：其余机型继续使用 QModem，无需拉取（省一次克隆与包扫描）。
if [[ "${WRT_CONFIG:-}" == *modem-pro ]]; then
	UPDATE_PACKAGE "modem-pro-unified" "LianXia233/modem-pro-unified" "main"

	MODEM_PRO_SRC="./modem-pro-unified"
	if [ -d "$MODEM_PRO_SRC" ]; then
		# 仅复制构建必需项；真实复制（禁止 symlink —— symlink 同样会触发上述扫描 bug）
		MODEM_PRO_FEED="../modem-pro-feed"
		rm -rf "$MODEM_PRO_FEED"
		mkdir -p "$MODEM_PRO_FEED/modem-pro"
		for ITEM in Makefile VERSION rust luci files packaging; do
			if [ -e "$MODEM_PRO_SRC/$ITEM" ]; then
				cp -r "$MODEM_PRO_SRC/$ITEM" "$MODEM_PRO_FEED/modem-pro/$ITEM"
			fi
		done
		# 克隆目录必须移出 package/：否则 package/ 主扫描会提前命中仓库根 Makefile，
		# 把 modem-pro 注册为 core package，feeds install 时 "Not overriding core package"
		# 直接跳过链接，配置符号在 defconfig 阶段又被静默丢弃。
		rm -rf "$MODEM_PRO_SRC"
		# 清掉可能混入的 Rust 构建产物（体积大且会污染 feed 索引）
		find "$MODEM_PRO_FEED/modem-pro" -name target -type d -prune -exec rm -rf {} + 2>/dev/null

		MODEM_PRO_FEEDS_CONF="../feeds.conf"
		if [ ! -f "$MODEM_PRO_FEEDS_CONF" ]; then
			MODEM_PRO_FEEDS_CONF="../feeds.conf.default"
		fi
		if [ ! -f "$MODEM_PRO_FEEDS_CONF" ]; then
			echo "::error title=Feeds config missing::../feeds.conf 与 ../feeds.conf.default 均不存在"
			exit 1
		fi

		MODEM_PRO_ABS="$(cd "$MODEM_PRO_FEED" && pwd)"
		if ! grep -q "^src-link modem_pro " "$MODEM_PRO_FEEDS_CONF" 2>/dev/null; then
			echo "src-link modem_pro $MODEM_PRO_ABS" >> "$MODEM_PRO_FEEDS_CONF"
		fi

		if ! ( cd .. && ./scripts/feeds update modem_pro && ./scripts/feeds install -a -p modem_pro ); then
			echo "::error title=Modem Pro feed registration failed::scripts/feeds 无法注册 modem-pro feed（固件将不含 modem-pro 包）"
			exit 1
		fi
		echo "modem-pro: 已注册为本地 feed 并安装到 package/feeds/modem_pro/"
	else
		echo "::error title=Modem Pro source missing::未找到 modem-pro-unified 克隆目录，拒绝继续构建"
		exit 1
	fi
fi

# 注：上游曾把 +qmodem-sipd 追加进 sms-forwarder-next 的 DEPENDS，与 ttyd 的
# libwebsockets-full 互斥导致 -next 变体 rootfs 组装失败；上游现已将其降级为
# PKG_RECOMMENDS（apk rootfs 组装不安装 RECOMMENDS，NEXT manifest 无 qmodem-sipd），
# 冲突自上游侧消解，此处不再需要补丁脚本。FIX_QMODEM_VERSION 保留作为上游版本
# 格式回退（-rc.N / -rcN）时的构建保护。
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac sing-box luci-app-homeproxy luci-app-timewol luci-app-wolplus luci-app-wolultra"

# ===== sing-box 过时补丁清理（2026-09-24 MTK-AUTO / OWRT-ALL 同时失败根因）=====
# VIKINGYFY/packages 的 sing-box 自带 patches/100-fix-dns-tcp-close.patch，它是针对
# 旧版 sing-box 的反向移植（引入上游从未合入的 HandleStreamDNSConnection）。当 feed 把
# sing-box 升到 1.15.0_alpha8 后，该补丁上下文已与上游源码（仍是 HandleStreamDNSRequest）
# 不匹配，OpenWrt 在 Build/Prepare 阶段应用补丁报 "Patch failed!" 并 Error 1，
# 进而令整个固件编译中断（今日 MTK-AUTO 与 OWRT-ALL 两个定时构建同时失败即此因）。
# 上游 immortalwrt/packages 的 sing-box 根本不携带该补丁也能正常构建，故这里在补丁确为
# 旧版（内容含 HandleStreamDNSConnection）时移除它，恢复构建。若 VIKINGYFY 后续刷新该补丁
# 为适配新源码的版本，本规则因标记不匹配而自动跳过，不会误删新版补丁。
FIX_SINGBOX_STALE_PATCH() {
	local PATCH="./packages/sing-box/patches/100-fix-dns-tcp-close.patch"
	[ -f "$PATCH" ] || { echo "sing-box: 无 100-fix-dns-tcp-close.patch，跳过"; return 0; }
	# 仅当补丁仍为旧版（引入未合入上游的 HandleStreamDNSConnection）时才移除
	if grep -q "HandleStreamDNSConnection" "$PATCH"; then
		rm -f "$PATCH"
		echo "sing-box: 移除过时补丁 100-fix-dns-tcp-close.patch（与 1.15.0_alpha8 源码不匹配）"
	else
		echo "sing-box: 100-fix-dns-tcp-close.patch 已非旧版，保留"
	fi
}
FIX_SINGBOX_STALE_PATCH

# FAN789 插件及其他专用硬件插件
UPDATE_PACKAGE "luci-app-h5000m-fancontrol" "FAN789/luci-app-h5000m-fancontrol" "main"
# AirPi AP3000M 专用（luci-app-airpi-fancontrol + airpi-gpio-fan 内核模块）：
# 仅 AP3000M 配置引入。该插件按 AP3000M 的 GPIO / PWM / 温度传感器适配，
# H5000M 与 X86 用不到，也不具备对应硬件依赖，无需拉取（省一次克隆与包扫描）
if [[ "${WRT_CONFIG:-}" == *AP3000M* ]]; then
	UPDATE_PACKAGE "luci-app-airpi-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main" "all"
fi
UPDATE_PACKAGE "luci-app-mt5700m" "LianXia233/luci-app-mt5700m" "main"
UPDATE_PACKAGE "luci-app-h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"

# ===== luci-app-h5000m-netmode 的 src/ 目录清理（2026-09-29 MTK-AUTO #100 全矩阵失败根因）=====
# 该插件后端已重写为 Rust crate，仓库里保留 src/（Rust 源码），并把预编译的静态 ELF
# 直接随包发布在 root/usr/sbin 下（见插件 Makefile 顶部注释：buildroot 内没有 Rust 工具链）。
# 但 feeds/luci/luci.mk 的两个分支判断条件并不一致：
#   Build/Compile      按 $(wildcard ${CURDIR}/src/Makefile) 判断 —— 需要"有 Makefile"
#   Package/.../install 按 $(wildcard ${CURDIR}/src)        判断 —— 只要"目录存在"即可
# 于是 "有 src/ 但没有 src/Makefile" 这个组合会踩坑：Compile 被跳过、ipkg-install 目录
# 永远不会生成，install 阶段却仍执行 Build/Install/Default，即 make -C $(PKG_BUILD_DIR) install；
# 该目录顶层没有 Makefile，make 报 "No rule to make target 'install'" 并以 exit code 2 退出，
# 表现为 luci.mk 末尾 BuildPackage 展开的打包规则报错（luci.mk:408），进而整个 world 编译中断。
# 证据链：src/ 由插件 2026-09-28 的 c68ac211（rewrite backend as single static Rust ELF）引入，
# 9-27 的 CI #99 仍成功，9-29 的 #100 是首个带 src/ 的构建，4 个 job 报错行与退出码完全一致。
# 删除 src/ 不影响产物：真正被打进包的是 root/、htdocs/、po/，二进制本来就已在仓库内预编译好。
FIX_H5000M_NETMODE_SRC() {
	local SRC_DIR="./luci-app-h5000m-netmode/src"
	if [ -d "$SRC_DIR" ]; then
		rm -rf "$SRC_DIR"
		echo "h5000m-netmode: 移除无 Makefile 的 src/（否则 luci.mk install 分支会误走 Build/Install/Default）"
	else
		echo "h5000m-netmode: 无 src/ 目录，跳过"
	fi
}
FIX_H5000M_NETMODE_SRC

# 在线升级插件：从 GitHub Releases 按本机实际刷入的固件版本/类型自动匹配更新包
# 具体脚本与默认值在 Scripts/online-upgrade/ 中按本仓库需求定制（构建时覆盖上游）
UPDATE_PACKAGE "luci-app-online-upgrade" "gooyjq/luci-app-online-upgrade" "main"

#更新软件包版本
UPDATE_VERSION() {
	local PKG_NAME=$1
	local PKG_MARK=${2:-false}
	local PKG_FILES=$(find ./ ../feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

	if [ -z "$PKG_FILES" ]; then
		echo "$PKG_NAME not found!"
		return
	fi

	echo -e "\n$PKG_NAME version update has started!"

	for PKG_FILE in $PKG_FILES; do
		local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
		local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

		local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
		local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
		local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
		local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

		local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

		local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
		local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
		local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

		echo "old version: $OLD_VER $OLD_HASH"
		echo "new version: $NEW_VER $NEW_HASH"

		if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
			sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
			sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
			echo "$PKG_FILE version has been updated!"
		else
			echo "$PKG_FILE version is already the latest!"
		fi
	done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
	source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
