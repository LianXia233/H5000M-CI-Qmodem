#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/mediatek/filogic/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
MTWIFI_SH="./package/mtk/applications/mtwifi-cfg/files/mtwifi.sh"

# 设备 WiFi 世代选择：AP3000M 为 WiFi6（802.11ax），H5000M 为 WiFi7（802.11be）。
# 无线默认值按世代区分（Config/OWRT-DEFAULT.txt 中 *_WIFI7 后缀为 WiFi7 专属默认，
# 无后缀为 WiFi6 默认，保持历史兼容）；WRT_CONFIG 由工作流按配置名传入，
# 未知设备一律按 WiFi6 处理。
if [[ "${WRT_CONFIG:-}" == *H5000M* ]]; then
	WRT_SSID="${WRT_SSID_WIFI7:-$WRT_SSID}"
	WRT_WORD="${WRT_WORD_WIFI7:-$WRT_WORD}"
	WIFI_ENCRYPTION="${WIFI_ENCRYPTION_WIFI7:-$WIFI_ENCRYPTION}"
	WIFI_COUNTRY="${WIFI_COUNTRY_WIFI7:-$WIFI_COUNTRY}"
	WIFI_2G_WIDTH="${WIFI_2G_WIDTH_WIFI7:-$WIFI_2G_WIDTH}"
	WIFI_5G_WIDTH="${WIFI_5G_WIDTH_WIFI7:-$WIFI_5G_WIDTH}"
fi

# 加密策略默认 psk-mixed（WPA/WPA2 混合，兼容新老终端）；
# MTK 闭源驱动栈（mtwifi）的 UCI 加密值需追加 +ccmp 后缀
WIFI_ENCRYPTION_UCI="${WIFI_ENCRYPTION:-psk-mixed}"
[ -f "$MTWIFI_SH" ] && WIFI_ENCRYPTION_UCI="${WIFI_ENCRYPTION_UCI}+ccmp"

if [ -f "$MTWIFI_SH" ]; then
	# 修改 MTK 闭源 Wi-Fi 驱动栈的默认名称和密码
	sed -i "s/ImmortalWrt-[[:alnum:].-]*/$WRT_SSID/g; s/encryption=none/encryption=$WIFI_ENCRYPTION_UCI/g" "$MTWIFI_SH"
	# 先移除可能存在的默认 key 行，再在 encryption 行后追加配置密钥（保证唯一且生效）
	sed -i "/set wireless.default_\${dev}.key=/d" "$MTWIFI_SH"
	sed -i "/set wireless.default_\${dev}.encryption=/a\\					set wireless.default_\${dev}.key='$WRT_WORD'" "$MTWIFI_SH"
elif [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI加密方式
	sed -i "s/encryption='none'/encryption='$WIFI_ENCRYPTION_UCI'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

# ===== 出厂无线默认参数（国家 / 频宽 / 加密）=====
# 由 Config/OWRT-DEFAULT.txt 驱动，生成首次启动脚本强制覆盖各驱动栈默认值，
# 保证 2.4G / 5G 频宽、国家码与加密策略出参一致。
# htmode 前缀按世代区分：WiFi6（802.11ax）2.4G / 5G 均用 HE；
# WiFi7（802.11be）2.4G / 5G 均用 EHT；同机两个频段世代一致。
if [[ "${WRT_CONFIG:-}" == *H5000M* ]]; then
	WIFI_2G_HTMODE="EHT${WIFI_2G_WIDTH:-40}"
	WIFI_5G_HTMODE="EHT${WIFI_5G_WIDTH:-160}"
else
	WIFI_2G_HTMODE="HE${WIFI_2G_WIDTH:-40}"
	WIFI_5G_HTMODE="HE${WIFI_5G_WIDTH:-160}"
fi

WIFI_DEFAULTS_DIR="./files/etc/uci-defaults"
mkdir -p "$WIFI_DEFAULTS_DIR"
cat > "$WIFI_DEFAULTS_DIR/10-wifi-defaults" <<EOF
#!/bin/sh
# SPDX-License-Identifier: MIT
# 出厂默认无线参数：构建时由 Scripts/Settings.sh 依据 Config/OWRT-DEFAULT.txt 生成
WIFI_SSID='${WRT_SSID:-OWRT}'
WIFI_KEY='${WRT_WORD:-12345678}'
WIFI_ENCRYPTION='$WIFI_ENCRYPTION_UCI'
WIFI_2G_WIDTH='$WIFI_2G_HTMODE'
WIFI_5G_WIDTH='$WIFI_5G_HTMODE'
WIFI_COUNTRY='${WIFI_COUNTRY:-CN}'

[ -f /etc/config/wireless ] || exit 0

for radio in radio0 radio1; do
	case "\$(uci get wireless.\$radio.band 2>/dev/null)" in
		2g) uci -q set wireless.\$radio.htmode="\$WIFI_2G_WIDTH" ;;
		5g) uci -q set wireless.\$radio.htmode="\$WIFI_5G_WIDTH" ;;
	esac
	uci -q set wireless.\$radio.country="\$WIFI_COUNTRY"
done
for def in default_radio0 default_radio1; do
	uci -q set wireless.\$def.ssid="\$WIFI_SSID"
	uci -q set wireless.\$def.encryption="\$WIFI_ENCRYPTION"
	uci -q set wireless.\$def.key="\$WIFI_KEY"
done
uci -q commit wireless 2>/dev/null
exit 0
EOF
chmod +x "$WIFI_DEFAULTS_DIR/10-wifi-defaults"
echo "wifi defaults injected: 2G=${WIFI_2G_HTMODE} 5G=${WIFI_5G_HTMODE} country=${WIFI_COUNTRY:-CN} encryption=${WIFI_ENCRYPTION_UCI}"

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE
#修改默认时区（由 Config/OWRT-DEFAULT.txt 的 WRT_TIMEZONE / WRT_ZONENAME 驱动）
sed -i "s/timezone='GMT0'/timezone='${WRT_TIMEZONE:-CST-8}'/g" $CFG_FILE
# zonename 含 "/"（Asia/Shanghai），必须换用 | 作分隔符；否则 sed 报
# "unknown option to `s'"，时区名静默保留为 UTC（run #133 日志中即此报错）
sed -i "s|zonename='UTC'|zonename='${WRT_ZONENAME:-Asia/Shanghai}'|g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config

# ===== 主题配套包 =====
# 默认主题由 WRT_THEME 决定（当前 vantage）；luci-theme-bootstrap 已在脚本开头被
# 替换成 luci-theme-$WRT_THEME，故未安装的主题不会抢占默认样式。
# 各主题的配套包名并不统一（aurora → luci-app-aurora-config、vantage →
# luci-app-vantage 仪表盘、argon → luci-app-argon-config），无脑拼
# luci-app-$WRT_THEME-config 会写出不存在的符号；这类符号在 defconfig 阶段被
# 静默丢弃，直接触发 check_defconfig.py 的「请求 y 却未生效」硬断言（构建失败）。
THEME_PKG=""
case "$WRT_THEME" in
	aurora)  THEME_PKG="luci-app-aurora-config" ;;
	vantage) THEME_PKG="luci-app-vantage" ;;
	argon)   THEME_PKG="luci-app-argon-config" ;;
esac
if [ -n "$THEME_PKG" ]; then
	echo "CONFIG_PACKAGE_$THEME_PKG=y" >> ./.config
fi

# Aurora 保留为可选主题（编入固件但不再默认），可在「系统 → 语言和界面」切回
if [ "$WRT_THEME" != "aurora" ]; then
	echo "CONFIG_PACKAGE_luci-theme-aurora=y" >> ./.config
	echo "CONFIG_PACKAGE_luci-app-aurora-config=y" >> ./.config
fi

# ===== 默认主题种子（首启动 uci-defaults）=====
# 集合依赖换成 luci-theme-$WRT_THEME 只能保证「该主题被安装」，无法保证
# /etc/config/luci 的 mediaurlbase 指向它：该文件是 conffile，sysupgrade 保留旧
# 配置时仍写着上一代默认（/luci-static/aurora），而主题包自带的 30_luci-theme-*
# 脚本只在 luci.themes.<Name> 首次注册时才写 mediaurlbase，升级路径不会切换。
# 这里生成一个排在 30_* 之后执行的种子脚本：
#   - 主题目录不存在（未编入）则不动配置，避免留下坏路径；
#   - 用 luci.main.theme_seeded 记录已种子过的默认主题，同一代主题只种一次，
#     用户此后在 LuCI 里改的主题不会被每次升级重置；日后更换默认主题时该值
#     不等，种子脚本会重新生效。
THEME_SEED_DIR="./files/etc/uci-defaults"
mkdir -p "$THEME_SEED_DIR"
THEME_NAME="$(printf '%s' "${WRT_THEME:0:1}" | tr '[:lower:]' '[:upper:]')${WRT_THEME:1}"
cat > "$THEME_SEED_DIR/40-luci-default-theme" <<EOF
#!/bin/sh
# 出厂默认主题：构建时由 Scripts/Settings.sh 依据 WRT_THEME 生成，勿手改
THEME='$WRT_THEME'
THEME_NAME='$THEME_NAME'

[ -n "\$THEME" ] || exit 0
[ -d "/www/luci-static/\$THEME" ] || exit 0
[ "\$(uci -q get luci.main.theme_seeded)" = "\$THEME" ] && exit 0

uci -q set "luci.themes.\$THEME_NAME=/luci-static/\$THEME"
uci -q set luci.main.mediaurlbase="/luci-static/\$THEME"
uci -q set luci.main.theme_seeded="\$THEME"
uci -q commit luci
exit 0
EOF
chmod +x "$THEME_SEED_DIR/40-luci-default-theme"
echo "default theme seeded: $WRT_THEME"

# ===== kmod-nft-fullcone 按源码实际能力裁剪 =====
# 该内核模块由 immortalwrt 系源码提供（package/network/utils/fullconenat-nft，
# 且 firewall4 自身 DEPENDS:=+kmod-nft-fullcone，两个分支都会自动编入）；
# 但 VIKINGYFY/immortalwrt 改用 fullconenat-sonic 内核补丁实现 fullcone
# （firewall4 默认 option fullcone 1），树里根本没有这个包。
# 请求树中不存在的符号会被 defconfig 静默丢弃，Verify Config 直接判失败
# （run #133 的 H5000M-modem-pro 即此因）。这里以源码树中的包定义为准：
# 找不到 KernelPackage/nft-fullcone 就删掉请求，避免误报。
if ! grep -rqs --include=Makefile "KernelPackage/nft-fullcone" ./package/; then
	sed -i "/^CONFIG_PACKAGE_kmod-nft-fullcone=/d" ./.config
	echo "kmod-nft-fullcone: 当前源码未提供该包（fullcone 由源码内置方案实现），已从请求配置移除"
fi

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi
