#!/bin/bash
# SPDX-License-Identifier: MIT
# 全机型通用：把 luci-app-online-upgrade 源码放进 package/
#
# 为什么独立成脚本而不是塞进 Scripts/Packages.sh：Packages.sh 是「每个机型都会
# 执行」的公共入口，但它只负责 clone/裁剪阶段的工作；本包还需要在 defconfig
# 之后交叉编译 Rust 后端（见 WRT-CORE「Precompile online-upgrade Rust Backend」）。
# 导入与预编译各自独立，WRT-CORE 中按顺序调用，失败点清晰可归因。
#
# 上游仓库是「包即仓库根」的形态：Makefile / root/ / rust/ 都在仓库根目录，
# 因此 clone 后直接把仓库内容搬成 package/luci-app-online-upgrade/，不需要
# 像 feeds 那样再下钻一层子目录。不加入 feeds：仓库不是 feeds 布局
# （feeds 要求 <feed>/<包名>/Makefile），硬套 src-git 会扫不到包。
#
# 用法（在 OpenWrt 源码树的 package/ 目录下执行）：
#   $GITHUB_WORKSPACE/Scripts/Packages-OnlineUpgrade.sh
#
# 环境变量（可选）：
#   ONLINE_UPGRADE_BRANCH   上游分支，默认 main
#   ONLINE_UPGRADE_REPO     上游仓库，默认 LianXia233/luci-app-online-upgrade

set -euo pipefail

PKG_NAME=luci-app-online-upgrade
PKG_REPO="${ONLINE_UPGRADE_REPO:-LianXia233/luci-app-online-upgrade}"
PKG_BRANCH="${ONLINE_UPGRADE_BRANCH:-main}"

# clone 到临时目录再搬移，避免与目标包目录同名互相覆盖
REPO_DIR=".${PKG_NAME}-upstream"

echo "==> 拉取 ${PKG_NAME}（${PKG_REPO}@${PKG_BRANCH}）"

# 幂等：重复执行先清干净，避免旧版本文件残留造成包内容混杂
rm -rf "./${PKG_NAME}" "./${REPO_DIR}"

# 托管 runner 在境外，直连为主；本机（国内网络）直连不稳时走加速镜像。
# 镜像只用于拉取，不涉及任何凭据。
if ! git clone --depth=1 --single-branch --branch "${PKG_BRANCH}" \
	"https://github.com/${PKG_REPO}.git" "./${REPO_DIR}" 2>/dev/null; then
	echo "::warning::直连 clone 失败，改用加速镜像重试"
	git clone --depth=1 --single-branch --branch "${PKG_BRANCH}" \
		"https://gh.acg2.mom/https://github.com/${PKG_REPO}.git" "./${REPO_DIR}"
fi

# 发布构建用不到的目录：.git 体积大，.github 是上游 CI
rm -rf "./${REPO_DIR}/.git" "./${REPO_DIR}/.github"

[ -f "./${REPO_DIR}/Makefile" ] || {
	echo "::error::${REPO_DIR}/Makefile 不存在：上游仓库布局可能已变更"
	echo "目录内容：$(ls -A "./${REPO_DIR}" | tr '\n' ' ')"
	exit 1
}

mv "./${REPO_DIR}" "./${PKG_NAME}"

# ===== 行尾归一化：CRLF → LF =====
# 只处理文本类文件。上游若在 Windows 下提交过 uci-defaults / rpcd 脚本，
# 行尾 \r 会让 shebang 变成 "#!/bin/sh\r"，设备上表现为脚本解释器不存在；
# Makefile 的 include 行带 \r 会直接报 luci.mk 找不到。
# 二进制（截图等）不参与转换：sed 对含 0x0d 的二进制会破坏内容。
mapfile -t PKG_TEXT_FILES < <(
	find "./${PKG_NAME}" -type f \
		\( -name '*.sh' -o -name '*.uc' -o -name '*.js' -o -name '*.css' \
		-o -name '*.json' -o -name '*.ut' -o -name '*.md' -o -name '*.txt' \
		-o -name '*.toml' -o -name '*.rs' -o -name '*.lock' -o -name 'Makefile' \)
)
if [ "${#PKG_TEXT_FILES[@]}" -gt 0 ]; then
	sed -i 's/\r$//' "${PKG_TEXT_FILES[@]}"
fi

# 复核：按字节比较转换前后长度，确认不再有 CR（与 Packages-NetWiz.sh 同思路，
# 不用 grep -qU $'\r'：该写法在 Git Bash / MSYS 下对 CR 的判定不可靠）
CR_LEFT=()
for F in "${PKG_TEXT_FILES[@]}"; do
	ORIG_LEN=$(wc -c < "$F")
	STRIPPED_LEN=$(tr -d '\r' < "$F" | wc -c)
	if [ "$ORIG_LEN" != "$STRIPPED_LEN" ]; then
		CR_LEFT+=("$F")
	fi
done
if [ "${#CR_LEFT[@]}" -ne 0 ]; then
	echo "::error::${PKG_NAME} 仍存在含 CR 的文件，行尾归一化未完成"
	for F in "${CR_LEFT[@]}"; do
		echo "  含 CR: $F"
	done
	exit 1
fi
echo "==> 行尾复核通过：${#PKG_TEXT_FILES[@]} 个文本文件均为 LF"

# ===== 结构断言：上游改动导致接入前提失效时立即红掉 =====
# 1) 必需 feeds/luci/luci.mk：包是 LuCI 应用，缺它 make 直接失败
grep -q 'feeds/luci/luci.mk' "./${PKG_NAME}/Makefile" || {
	echo "::error::${PKG_NAME}/Makefile 未引用 feeds/luci/luci.mk：上游打包方式可能已变更"
	grep -n 'luci.mk' "./${PKG_NAME}/Makefile" || echo "（Makefile 中无 luci.mk 引用）"
	exit 1
}

# 2) 安装段必须从 ./root/usr/bin/online-upgrade 取二进制：本仓库不在
#    buildroot 内编译 Rust，而是在 WRT-CORE 里用官方 Rust SDK 预编译后放到该路径。
#    上游若改成 buildroot 内编译，这里会先失败，提示接入方式需要同步调整。
grep -q './root/usr/bin/online-upgrade' "./${PKG_NAME}/Makefile" || {
	echo "::error::${PKG_NAME}/Makefile 不再安装 ./root/usr/bin/online-upgrade："
	echo "  预编译产物落点与本仓库接入方式需要同步调整"
	exit 1
}

# 3) Rust 工程目录：预编译步骤按 <包>/rust 取源码
[ -f "./${PKG_NAME}/rust/Cargo.toml" ] || {
	echo "::error::${PKG_NAME}/rust/Cargo.toml 不存在：上游 Rust 后端目录可能已改名"
	exit 1
}

# 4) 默认 UCI 配置文件：预设配置的键名以它为基线
[ -f "./${PKG_NAME}/root/etc/config/online-upgrade" ] || {
	echo "::error::${PKG_NAME}/root/etc/config/online-upgrade 不存在：上游默认配置路径可能已变更"
	exit 1
}

# ===== 守卫路径一致性：90-online-upgrade-auto 的存在性判定 =====
# 该脚本本意是「仅在插件确实缺失时尝试重装」。v1 判的是 /usr/bin/online-upgrade.sh，
# v2 只安装 /usr/bin/online-upgrade；若沿用 v1 判定，每次刷机首启都会误判「插件丢失」，
# 转而下载 .apk 并 apk add --allow-untrusted，把本仓库自编的二进制覆盖掉。
#
# 上游已于 98a966a（fix: 修复 uci-defaults 存在性守卫对 v2 二进制路径判定错误）
# 自行修复为 [ -x /usr/bin/online-upgrade ]。因此这里必须「按内容判定」，
# 不能硬编码 sed：上游已修复时再改写属于无意义改动，且一旦上游改回或调整行文，
# 无条件替换会静默失效或被误判为成功。只有真的检出 v1 路径才改写，并双向断言。
#
# 时序约束：upgrade.rs 用 include_str! 把该脚本编进二进制（升级时用它重写设备上的
# /etc/uci-defaults/90-online-upgrade-auto），所以改写必须发生在 cargo build 之前。
# WRT-CORE 中「Import」步骤排在「Precompile Rust Backend」之前，顺序不可调换。
AUTO_UCI="./${PKG_NAME}/root/etc/uci-defaults/90-online-upgrade-auto"
V2_BIN='/usr/bin/online-upgrade'
V1_BIN='/usr/bin/online-upgrade.sh'

[ -f "$AUTO_UCI" ] || {
	echo "::error::${AUTO_UCI} 缺失：上游目录结构可能已调整"
	exit 1
}

# 统计 v1 引用处数（grep -c 在有命中时返回 0，无命中返回 1，
# set -e 下需吞掉非零退出码）
V1_HITS=$(grep -c -F "$V1_BIN" "$AUTO_UCI" || true)
V1_HITS=${V1_HITS:-0}
if [ "$V1_HITS" -gt 0 ]; then
	# 转义点号，避免 . 被当作通配符（虽不影响本例，但防止上游出现
	# /usr/bin/online-upgradeXsh 之类的近似串被误改）
	V1_BIN_ESC=${V1_BIN//./\\.}
	sed -i "s#${V1_BIN_ESC}#${V2_BIN}#g" "$AUTO_UCI"
	echo "==> 检出 v1 守卫路径 ${V1_HITS} 处，已改写为 ${V2_BIN}"
else
	echo "==> 守卫已是 v2 路径（上游已修复），跳过改写"
fi

# 断言一：不得残留 v1 路径
if grep -q -F "$V1_BIN" "$AUTO_UCI"; then
	echo "::error::${AUTO_UCI} 仍残留 v1 路径 ${V1_BIN}，守卫修正未生效"
	grep -n -F "$V1_BIN" "$AUTO_UCI"
	exit 1
fi
# 断言二：必须存在针对真实二进制的存在性判定。
# 接受 -x / -f 两种写法：上游修复用 -x（可执行），若将来退回 -f，改写后同样成立，
# 断言只要求「判定对象是 /usr/bin/online-upgrade」，不绑定测试开关。
grep -q -E -- "-[xf][[:space:]]+${V2_BIN}([[:space:]]|$)" "$AUTO_UCI" || {
	echo "::error::${AUTO_UCI} 未找到针对 ${V2_BIN} 的存在性判定（-x/-f）：上游守卫逻辑可能已变更"
	grep -n 'exit 0' "$AUTO_UCI" || true
	exit 1
}

# ===== 安装路径三方一致性 =====
# ① Makefile 安装项；② 守卫判定路径；③ WRT-CORE 预编译产物落点
# （③ 由上面第 2 条结构断言保证：Makefile 取 ./root/usr/bin/online-upgrade）。
grep -q -F -- '$(1)/usr/bin/online-upgrade' "./${PKG_NAME}/Makefile" || {
	echo "::error::Makefile 未把二进制安装到 \$(1)/usr/bin/online-upgrade："
	echo "  与守卫判定的 ${V2_BIN} 不一致，装出的包会被自身判为「插件丢失」"
	exit 1
}
echo "==> 路径一致性通过：Makefile 安装项 / 守卫判定 / 预编译落点均为 ${V2_BIN}"

# ===== 全局 v1 残留扫描 =====
# 唯一允许保留的是 99-online-upgrade 里的清理语句（rm -f v1 旧脚本），
# 它删除的是 v1 遗留文件，本身正确且必要 —— 若被无差别改写，
# 会变成删除 v2 真实二进制，属严重回归。
PKG_V1_LEFT=$(cd "./${PKG_NAME}" && grep -rn -F "$V1_BIN" . 2>/dev/null || true)
if [ -n "$PKG_V1_LEFT" ]; then
	echo "==> 包内 v1 路径引用："
	printf '%s\n' "$PKG_V1_LEFT" | sed 's/^/    /'
	PKG_V1_BAD=$(printf '%s\n' "$PKG_V1_LEFT" | grep -v -F 'rm -f' || true)
	if [ -n "$PKG_V1_BAD" ]; then
		echo "::error::以下 v1 引用不是清理语句，需人工确认："
		printf '%s\n' "$PKG_V1_BAD" | sed 's/^/    /'
		exit 1
	fi
	echo "    （以上均为清理语句，保留）"
fi

# 可执行位补齐：git clone 一般保留 mode，但上游经 Windows 提交或 archive
# 分发时 x 位可能丢失，导致 uci-defaults 在设备上不执行。
for FILE in root/etc/uci-defaults/99-online-upgrade root/etc/uci-defaults/90-online-upgrade-auto; do
	if [ -f "./${PKG_NAME}/${FILE}" ]; then
		chmod +x "./${PKG_NAME}/${FILE}"
	else
		echo "::warning::${PKG_NAME}/${FILE} 缺失：上游目录结构可能已调整"
	fi
done

echo "==> ${PKG_NAME} 就位：$(cd "./${PKG_NAME}" && ls -A | tr '\n' ' ')"
