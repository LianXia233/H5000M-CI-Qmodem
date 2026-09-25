#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

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
	git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git"

	# 处理克隆的仓库
	if [[ "$PKG_SPECIAL" == "pkg" ]]; then
		find ./$REPO_NAME/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
	elif [[ "$PKG_SPECIAL" == "name" ]]; then
		mv -f $REPO_NAME $PKG_NAME
	elif [[ "$PKG_SPECIAL" == "all" ]]; then
		find ./$REPO_NAME/ -mindepth 1 -maxdepth 1 -type d -exec cp -rf {} ./ \;
		rm -rf ./$REPO_NAME/
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
# qmodem-next 使用此核心脚本包；旧版 luci-app-qmodem 在配置中禁用
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"

# QModem 包共用 version.mk 的 QMODEM_VERSION（当前上游发布 "3.4.0-rc.3"）。
# OpenWrt 新版 apk 打包器不接受 `-rc.N`：版本串被拼成 "3.4.0-rc.3-rN" 后，
# apk mkpkg 报 "package version is invalid"（Error 99），阻断整个固件构建
# （libqmodem-sms / sms-tool_q 今日 6 job 全灭即此因）。这里在克隆后把
# X.Y.Z-rc.N 改写为 apk 合法的 X.Y.Z_rcN；QModem 各包源码均内嵌仓库 src/，
# 无版本化下载依赖，改写只影响包版本元数据。若上游已改为合法版本，自动跳过。
FIX_QMODEM_VERSION() {
	local VER_FILE="./QModem/version.mk"
	[ -f "$VER_FILE" ] || { echo "qmodem: version.mk not found, skip"; return 0; }
	if grep -qE '^QMODEM_VERSION:=[0-9]+\.[0-9]+\.[0-9]+-rc\.[0-9]+$' "$VER_FILE"; then
		sed -i -E 's/^(QMODEM_VERSION:=)([0-9]+\.[0-9]+\.[0-9]+)-rc\.([0-9]+)$/\1\2_rc\3/' "$VER_FILE"
		echo "qmodem: QMODEM_VERSION sanitized to $(grep -E '^QMODEM_VERSION:=' "$VER_FILE")"
	else
		echo "qmodem: QMODEM_VERSION already apk-valid, no change"
	fi
}
FIX_QMODEM_VERSION

# QModem 上游 2026-09-11 提交 86102c2a6f（"integrate independent SIP SMS and VoIP
# services"）给 sms-forwarder-next 的 DEPENDS 追加了 +qmodem-sipd，形成依赖链
# luci-app-qmodem-next → sms-forwarder-next → qmodem-sipd → qmodem-voip →
# libwebsockets-mbedtls；而 ttyd 依赖 libwebsockets-full，两个 libwebsockets
# 变体互斥（均提供 libwebsockets=4.5.8-r1 并互设 CONFLICTS），导致 rootfs 组装
# 阶段 apk 报 "unable to select packages"，-next 变体全部编译失败。
# 这里在克隆后把 +qmodem-sipd 从 sms-forwarder-next 的 DEPENDS 中摘除：
# SMS 转发（ServerChan / Webhook / 自定义脚本）不受影响，仅去掉依赖 VoIP 栈的
# SIP MESSAGE 通道。若上游调整依赖后已不含 +qmodem-sipd，自动跳过。
FIX_QMODEM_VOIP_DEP() {
	local SFN_FILE="./QModem/application/sms_forwarder_next/Makefile"
	[ -f "$SFN_FILE" ] || { echo "qmodem: sms_forwarder_next/Makefile not found, skip"; return 0; }
	if grep -q '+qmodem-sipd' "$SFN_FILE"; then
		sed -i 's/ +qmodem-sipd//' "$SFN_FILE"
		echo "qmodem: removed +qmodem-sipd from sms-forwarder-next DEPENDS (libwebsockets variant conflict workaround)"
	else
		echo "qmodem: sms-forwarder-next DEPENDS already clean, no change"
	fi
}
FIX_QMODEM_VOIP_DEP
UPDATE_PACKAGE "luci-app-qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac sing-box luci-app-homeproxy luci-app-timewol luci-app-wolplus luci-app-wolultra"

# ===== sing-box 过时补丁清理（2026-09-24 MTK-AUTO / OWRT-ALL 同时失败根因）=====
# VIKINGYFY/packages 的 sing-box 自带 patches/100-fix-dns-tcp-close.patch，它是针对
# 旧版 sing-box 的反向移植（引入上游从未合入的 HandleStreamDNSConnection）。当 feed 把
# sing-box 升到 1.15.0_alpha8 后，该补丁上下文已与上游源码（仍是 HandleStreamDNSRequest）
# 不匹配，OpenWrt 在 Build/Prepare 阶段应用补丁报 “Patch failed!” 并 Error 1，
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

UPDATE_PACKAGE "vnt" "lmq8267/luci-app-vnt" "main"

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
