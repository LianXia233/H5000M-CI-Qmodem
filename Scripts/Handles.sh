#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

if [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "$GITHUB_WORKSPACE/wrt/package" ]; then
	PKG_PATH="$GITHUB_WORKSPACE/wrt/package"
else
	PKG_PATH="$(pwd)"
fi

#预置HomeProxy数据
HP_DIR="$(find "$PKG_PATH" -maxdepth 1 -type d -name '*homeproxy*' -print -quit)"
if [ -n "$HP_DIR" ]; then
	echo " "

	HP_RESOURCES="$HP_DIR/root/etc/homeproxy/resources"
	HP_DASHBOARD="$HP_DIR/root/etc/homeproxy/dashboard"
	HP_IP_SOURCE="https://cdn.jsdelivr.net/gh/Loyalsoldier/surge-rules@release/cncidr.txt"
	HP_GEOSITE_SOURCE="https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set-unstable/geosite-cn.srs"
	HP_IP_VERSION_URL="https://github.com/Loyalsoldier/surge-rules/releases/latest"
	HP_GEOSITE_VERSION_URL="https://github.com/SagerNet/sing-geosite/releases/latest"
	HP_DASHBOARD_SOURCE="https://codeload.github.com/SagerNet/sing-box-dashboard/zip/refs/heads/gh-pages"
	HP_DASHBOARD_VERSION_URL="https://github.com/SagerNet/sing-box-dashboard/commits/gh-pages.atom"
	HP_USER_AGENT="HomeProxy resource preset"

	HP_PREREQUISITES_MISSING=0
	for HP_COMMAND in curl awk; do
		command -v "$HP_COMMAND" > /dev/null 2>&1 || {
			echo "homeproxy resource preset requires $HP_COMMAND!"
			HP_PREREQUISITES_MISSING=1
		}
	done
	HP_PRESET_FAILED=0
	if [ "${HP_PREREQUISITES_MISSING:-0}" -eq 1 ]; then
		HP_PRESET_FAILED=1
	else
		HP_TMP="$(mktemp -d)"
		if [ -z "$HP_TMP" ]; then
			echo "failed to prepare homeproxy resource preset directory!"
			HP_PRESET_FAILED=1
		fi
	fi
	HP_DASHBOARD_STAGE="${HP_DASHBOARD}.new.$$"
	if [ "$HP_PRESET_FAILED" -eq 0 ]; then
		trap 'rm -rf "$HP_TMP" "$HP_DASHBOARD_STAGE"' EXIT INT TERM
	fi

	hp_fetch_release_version() {
		local effective_url version

		effective_url="$(curl -fsSL --compressed --retry 3 --retry-all-errors \
			--retry-delay 1 \
			--connect-timeout 10 --max-time 30 -A "$HP_USER_AGENT" \
			-o /dev/null -w '%{url_effective}' "$1")" || return 1
		version="${effective_url##*/}"
		case "$version" in
		''|*[!0-9]*) return 1 ;;
		esac
		printf '%s\n' "$version"
	}

	hp_download() {
		curl -fsSL --compressed --retry 3 --retry-all-errors --retry-delay 1 \
			--connect-timeout 10 \
			--max-time 60 -A "$HP_USER_AGENT" -o "$2" "$1" && [ -s "$2" ]
	}

	hp_fetch_dashboard_version() {
		local feed version

		feed="$(curl -fsSL --compressed --retry 3 --retry-all-errors \
			--retry-delay 1 --connect-timeout 10 --max-time 30 \
			-A "$HP_USER_AGENT" "$HP_DASHBOARD_VERSION_URL")" || return 1
		version="$(printf '%s\n' "$feed" | awk -F '[<>]' '
			/<updated>/ {
				version = $3
				gsub(/[-:TZ]/, "", version)
				print version
				exit
			}
		')"
		case "$version" in
		??????????????) case "$version" in *[!0-9]*) return 1 ;; esac ;;
		*) return 1 ;;
		esac
		printf '%s\n' "$version"
	}

	hp_replace_file() {
		local source_file="$1" target_file="$2" temporary_file

		temporary_file="${target_file}.tmp.$$"
		cp "$source_file" "$temporary_file" || return 1
		chmod 0644 "$temporary_file" || return 1
		mv -f "$temporary_file" "$target_file"
	}

	hp_update_ip() {
		local version file

		version="$(hp_fetch_release_version "$HP_IP_VERSION_URL")" || return 1
		hp_download "$HP_IP_SOURCE?v=$version" "$HP_TMP/cncidr.txt" || return 1
		awk -F, -v ipv4="$HP_TMP/china_ip4.txt" -v ipv6="$HP_TMP/china_ip6.txt" '
			$1 == "IP-CIDR" { print $2 > ipv4 }
			$1 == "IP-CIDR6" { print $2 > ipv6 }
		' "$HP_TMP/cncidr.txt" || return 1
		[ -s "$HP_TMP/china_ip4.txt" ] && [ -s "$HP_TMP/china_ip6.txt" ] || return 1
		awk '
			BEGIN {
				print "{\"version\":5,\"rules\":[{\"ip_cidr\":["
				first = 1
			}
			NF {
				printf "%s\"%s\"", first ? "" : ",", $0
				first = 0
			}
			END { print "]}]}" }
		' "$HP_TMP/china_ip4.txt" "$HP_TMP/china_ip6.txt" > "$HP_TMP/geoip_cn.json" || return 1
		[ -s "$HP_TMP/geoip_cn.json" ] || return 1
		printf '%s\n' "$version" > "$HP_TMP/china_ip4.ver"
		printf '%s\n' "$version" > "$HP_TMP/china_ip6.ver"
		for file in china_ip4.txt china_ip4.ver china_ip6.txt china_ip6.ver geoip_cn.json; do
			hp_replace_file "$HP_TMP/$file" "$HP_RESOURCES/$file" || return 1
		done
		echo "homeproxy resources: china_ip $version"
	}

	hp_update_geosite() {
		local version

		version="$(hp_fetch_release_version "$HP_GEOSITE_VERSION_URL")" || return 1
		hp_download "$HP_GEOSITE_SOURCE?v=$version" "$HP_TMP/geosite_cn.srs" || return 1
		printf '%s\n' "$version" > "$HP_TMP/geosite_cn.ver"
		hp_replace_file "$HP_TMP/geosite_cn.srs" "$HP_RESOURCES/geosite_cn.srs" || return 1
		hp_replace_file "$HP_TMP/geosite_cn.ver" "$HP_RESOURCES/geosite_cn.ver" || return 1
		echo "homeproxy resources: geosite_cn $version"
	}

	hp_update_dashboard() {
		local version source_dir old_dir

		command -v unzip > /dev/null 2>&1 || return 1
		command -v find > /dev/null 2>&1 || return 1
		version="$(hp_fetch_dashboard_version)" || return 1
		hp_download "$HP_DASHBOARD_SOURCE?v=$version" "$HP_TMP/dashboard.zip" || return 1
		unzip -q "$HP_TMP/dashboard.zip" -d "$HP_TMP/dashboard" || return 1
		source_dir="$(find "$HP_TMP/dashboard" -mindepth 1 -maxdepth 1 -type d -print -quit)"
		[ -n "$source_dir" ] && [ -f "$source_dir/index.html" ] || return 1

		rm -rf "$HP_DASHBOARD_STAGE"
		mkdir -p "$HP_DASHBOARD_STAGE" &&
			cp -a "$source_dir/." "$HP_DASHBOARD_STAGE/" &&
			printf '%s\n' "$version" > "$HP_DASHBOARD_STAGE/dashboard.ver" || return 1
		rm -f "$HP_DASHBOARD_STAGE/.etag"
		chmod -R a+rX "$HP_DASHBOARD_STAGE" || return 1

		old_dir="${HP_DASHBOARD}.old.$$"
		rm -rf "$old_dir"
		{ [ ! -d "$HP_DASHBOARD" ] || mv "$HP_DASHBOARD" "$old_dir"; } || return 1
		if mv "$HP_DASHBOARD_STAGE" "$HP_DASHBOARD"; then
			rm -rf "$old_dir"
			echo "homeproxy dashboard: $version"
			return 0
		fi
		rm -rf "$HP_DASHBOARD"
		[ ! -d "$old_dir" ] || mv "$old_dir" "$HP_DASHBOARD"
		return 1
	}

	if [ "$HP_PRESET_FAILED" -eq 0 ] && ! mkdir -p "$HP_RESOURCES" "$HP_DASHBOARD"; then
		echo "failed to prepare homeproxy resource directories!"
		HP_PRESET_FAILED=1
	fi

	if [ "$HP_PRESET_FAILED" -eq 0 ]; then
		if ! hp_update_ip; then
			echo "failed to update homeproxy IP resources; continuing!"
			HP_PRESET_FAILED=1
		fi

		if ! hp_update_geosite; then
			echo "failed to update homeproxy geosite; continuing!"
			HP_PRESET_FAILED=1
		fi

		if ! hp_update_dashboard; then
			echo "failed to update homeproxy dashboard; continuing!"
			HP_PRESET_FAILED=1
		fi

		rm -rf "$HP_TMP" "$HP_DASHBOARD_STAGE"
		trap - EXIT INT TERM
	fi

	if [ "$HP_PRESET_FAILED" -eq 0 ]; then
		echo "homeproxy data has been updated!"
	else
		echo "homeproxy resource preset completed with errors; continuing other handlers!"
	fi
fi

#修复homeproxy ucode兼容性问题
# update_subscriptions.uc: luci.sys.init_action不存在 → system()调用
# generate_client.uc: math.isnan不存在 → type() === 'double'
HP_SCRIPTS="$HP_DIR/root/etc/homeproxy/scripts"
HP_FIXES="$GITHUB_WORKSPACE/Scripts/homeproxy"
if [ -n "$HP_DIR" ] && [ -d "$HP_SCRIPTS" ] && [ -d "$HP_FIXES" ]; then
	echo " "
	if cp -f "$HP_FIXES/update_subscriptions.uc" "$HP_SCRIPTS/" && \
	   cp -f "$HP_FIXES/generate_client.uc" "$HP_SCRIPTS/"; then
		echo "homeproxy ucode compatibility fixes applied!"
	else
		echo "homeproxy ucode fix failed; continuing!"
	fi
fi

#修改argon主题字体和颜色
if [ -d "$PKG_PATH/luci-theme-argon" ]; then
	echo " "
	if sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" \
		"$PKG_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"; then
		echo "theme-argon has been fixed!"
	else
		echo "theme-argon fix failed; continuing!"
	fi
fi

#修改aurora菜单式样
if [ -d "$PKG_PATH/luci-app-aurora-config" ]; then
	echo " "
	if find "$PKG_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec \
		sed -i "s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +; then
		echo "theme-aurora has been fixed!"
	else
		echo "theme-aurora fix failed; continuing!"
	fi
fi

#修改mini-diskmanager菜单位置
if [ -d "$PKG_PATH/luci-app-mini-diskmanager" ]; then
	echo " "
	if sed -i "s/services/system/g" \
		"$PKG_PATH/luci-app-mini-diskmanager/luci-app-mini-diskmanager/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"; then
		echo "mini-diskmanager has been fixed!"
	else
		echo "mini-diskmanager fix failed; continuing!"
	fi
fi

#修复TailScale配置文件冲突
FEEDS_PACKAGES="$PKG_PATH/../feeds/packages"
TS_FILE="$(find "$FEEDS_PACKAGES" -maxdepth 3 -type f -wholename '*/tailscale/Makefile' -print -quit 2>/dev/null)"
if [ -f "$TS_FILE" ]; then
	echo " "

	if sed -i '/\/files/d' "$TS_FILE"; then
		echo "tailscale has been fixed!"
	else
		echo "tailscale fix failed; continuing!"
	fi
fi

#修复Rust编译失败
RUST_FILE="$(find "$FEEDS_PACKAGES" -maxdepth 3 -type f -wholename '*/rust/Makefile' -print -quit 2>/dev/null)"
if [ -f "$RUST_FILE" ]; then
	echo " "

	if sed -i 's/ci-llvm=true/ci-llvm=false/g' "$RUST_FILE"; then
		echo "rust has been fixed!"
	else
		echo "rust fix failed; continuing!"
	fi
fi

# ovpn-dco recvmsg 兼容性说明：上游 ovpn-backports 7.1.0.2026080300 已内置
# OVPN_PROTO_RECVMSG_HAS_ADDR_LEN 修复（linux-compat.h + tcp.c），
# 不再需要注入 0002 补丁（注入反而会导致 patch hunk 失败）。

# AP3000M EEPROM 模板注入 (MT7981 + MT7976 DBDC 开源驱动)
# 将备份的 EEPROM 模板（含原厂校准数据）和首次启动初始化脚本注入固件
# 解决 eMMC 设备 factory 分区空白导致 mt76 驱动 eeprom load fail 的问题
AP3000M_EEPROM_DIR="$GITHUB_WORKSPACE/AP3000M-EEPROM"
if [ -d "$AP3000M_EEPROM_DIR" ]; then
	FILES_DIR="../files"
	mkdir -p "$FILES_DIR/lib/firmware/mediatek/"
	mkdir -p "$FILES_DIR/etc/uci-defaults/"

	if cp "$AP3000M_EEPROM_DIR/mt7981_eeprom_mt7976_dbdc.bin" \
		"$FILES_DIR/lib/firmware/mediatek/mt7981_eeprom_mt7976_dbdc.bin" && \
	   cp "$AP3000M_EEPROM_DIR/99-ap3000m-eeprom" \
		"$FILES_DIR/etc/uci-defaults/99-ap3000m-eeprom" && \
	   chmod +x "$FILES_DIR/etc/uci-defaults/99-ap3000m-eeprom"; then
		echo "AP3000M: EEPROM template and init script has been injected!"
	else
		echo "AP3000M: EEPROM injection failed; continuing!"
	fi
fi

# ===== luci-app-online-upgrade：设备身份烙入 + 定制脚本覆盖 =====
# 1) 将本机构建身份写入固件（/etc/online-upgrade-device），供在线升级插件按机型动态匹配 Release。
#    发布标签格式为 {配置名}-{源码owner}-{分支}-{日期}（与 WRT-CORE 的 Release 标签完全一致）。
ONLINE_FILES_DIR="../files"
mkdir -p "$ONLINE_FILES_DIR/etc"
case "$WRT_CONFIG" in
	X86-*) ONLINE_FW_PATTERN='combined-efi.*\.img\.gz' ;;
	*)     ONLINE_FW_PATTERN='squashfs-sysupgrade.*\.bin$' ;;
esac
cat > "$ONLINE_FILES_DIR/etc/online-upgrade-device" <<EOF
# 由 H5000M-CI-Qmodem 构建流程自动生成，请勿手动修改
WRT_CONFIG=$WRT_CONFIG
WRT_INFO=$WRT_INFO
WRT_BRANCH=$WRT_BRANCH
WRT_TAG=$WRT_CONFIG-$WRT_INFO-$WRT_BRANCH-$WRT_DATE
FIRMWARE_PATTERN='$ONLINE_FW_PATTERN'
EOF
echo "online-upgrade: device identity baked (config=$WRT_CONFIG, pattern=$ONLINE_FW_PATTERN)"

# 2) 用本仓库定制版脚本/默认值覆盖上游插件，实现按机型自动匹配 Release。
ONLINE_PATCH_DIR="$GITHUB_WORKSPACE/Scripts/online-upgrade"
ONLINE_PLUGIN_DIR="./luci-app-online-upgrade"
if [ -d "$ONLINE_PLUGIN_DIR" ] && [ -d "$ONLINE_PATCH_DIR" ]; then
	if [ -f "$ONLINE_PATCH_DIR/online-upgrade.sh" ]; then
		cp -f "$ONLINE_PATCH_DIR/online-upgrade.sh" "$ONLINE_PLUGIN_DIR/root/usr/bin/online-upgrade.sh"
		echo "online-upgrade: script patched"
	fi
	if [ -f "$ONLINE_PATCH_DIR/99-online-upgrade" ]; then
		cp -f "$ONLINE_PATCH_DIR/99-online-upgrade" "$ONLINE_PLUGIN_DIR/root/etc/uci-defaults/99-online-upgrade"
		echo "online-upgrade: uci-defaults patched"
	fi

	# 3) 修复前端 JS：从 UCI 读取实际配置，不再显示硬编码默认值
	ONLINE_FRONTEND_JS="$ONLINE_PLUGIN_DIR/htdocs/luci-static/resources/view/system/online-upgrade.js"
	if [ -f "$ONLINE_FRONTEND_JS" ] && [ -f "$ONLINE_PATCH_DIR/fix-frontend.py" ]; then
		python3 "$ONLINE_PATCH_DIR/fix-frontend.py" "$ONLINE_FRONTEND_JS"
	fi
fi
