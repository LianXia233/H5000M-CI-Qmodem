# 更新日志

## [2026-10-04] 修复 qmodem 主包与 LuCI 前端仍未进固件：补上 input-support 依赖

### 背景

feed（src-link）方式集成后，`tom_modem`、`libqmodem-sms`、`sms-forwarder-next`、
`sms-tool_q` 等已成功编译进固件，但 `qmodem` 主包、`luci-app-qmodem-next` /
`luci-app-qmodem` 及 `qmodem-settings` / `qmodem-smsd` 仍缺失。根因：qmodem 各 LuCI
应用与主包的 Kconfig 均声明 `depends on PACKAGE_input-support`（LuCI 的 USB 输入设备
支持包），而 `Config/QMODEM*.txt` 未启用它，导致这些符号在 defconfig 阶段被 Kconfig
静默丢弃，即便配置中显式写了 `=y` 也不生效。

### 变更

- `Config/QMODEM-NEXT.txt`：新增 `CONFIG_PACKAGE_input-support=y`；
- `Config/QMODEM.txt`：新增 `CONFIG_PACKAGE_input-support=y`（传统前端同样依赖）。

本地复现验证：启用 input-support 后重新 defconfig，`CONFIG_PACKAGE_qmodem=y`、
`CONFIG_PACKAGE_luci-app-qmodem-next=y`、`CONFIG_PACKAGE_qmodem-smsd=y`、
`CONFIG_PACKAGE_qmodem-settings=y` 全部恢复（后三者由 luci-app-qmodem-next 的
`select` 自动拉起）。

### 变更文件

- `Config/QMODEM-NEXT.txt`
- `Config/QMODEM.txt`
- `CHANGELOG.md`

## [2026-10-04] 修复 qmodem LuCI 前端仍未编译进固件：QModem 移出 package/ 避免 core 包冲突

### 背景

2026-10-03 以 src-link 注册 qmodem feed 后，后端组件（quectel-CM-5G-M 等）已进入固件，
但 `luci-app-qmodem` / `luci-app-qmodem-next` 等 LuCI 前端包仍在固件 manifest 中缺失。
根因：`UPDATE_PACKAGE "qmodem"` 仍把克隆目录放在 `package/QModem/`，OpenWrt 主包扫描
（package/Makefile 的 `builddirs`）先于 feed 注册命中 `package/QModem/application/*`、
`package/QModem/luci/*` 下的 Makefile，把 `luci-app-qmodem` / `qmodem` / `qmodem-seal`
等提前注册为 core package；随后 `feeds install` 对同名包报
`WARNING: Not overriding core package 'luci-app-qmodem'; use -f to force` 并跳过链接，
`CONFIG_PACKAGE_luci-app-qmodem*` 等符号在 defconfig 阶段被静默丢弃。

### 变更

- `Scripts/Packages.sh`：`REGISTER_QMODEM_FEED` 开头新增目录搬移——若 `package/QModem`
  存在且工作区根尚无 `QModem`，先 `mv -f ./QModem ../QModem` 把克隆目录移出 `package/`，
  再以 `src-link qmodem` 注册 feed；`QMODEM_DIR` / `QMODEM_ABS` 同步指向 `../QModem`，
  使主包扫描不再提前抢注同名包，`feeds install -a -p qmodem` 可正常把所有二级目录包
  链接到 `package/feeds/qmodem/`；
- 同步修正 `FIX_QMODEM_VERSION`（`version.mk`）与 `FIX_QMODEM_VOIP_DEP`
  （`sms_forwarder_next/Makefile`）的路径为 `../QModem/...`。

### 变更文件

- `Scripts/Packages.sh`
- `CHANGELOG.md`

## [2026-10-03] 修复 qmodem 未编译进固件：改为 OpenWrt feed（src-link）方式集成

### 背景

qmodem（FUjr/QModem）此前一直未进入固件。根因：该仓库按 OpenWrt feed（src-git）设计，
顶层没有 Makefile，包分散在 `application/`、`luci/`、`driver/` 等二级目录；而 Packages.sh
仅把仓库克隆到 `package/QModem/`，OpenWrt 的包扫描（package/Makefile 的 `builddirs`）
只认含 Makefile 的一级子目录，导致 `luci-app-qmodem` / `luci-app-qmodem-next` / `qmodem` /
`sms-forwarder-next` 等配置符号在 defconfig 阶段不存在，配置被静默丢弃。

### 变更

- `Scripts/Packages.sh`：`UPDATE_PACKAGE "qmodem" ...` 克隆后新增 `REGISTER_QMODEM_FEED`，
  将克隆目录以 `src-link qmodem` 追加进 feeds 配置（`feeds.conf` 优先于 `feeds.conf.default`），
  再增量执行 `feeds update qmodem && feeds install -a -p qmodem`，由 scripts/feeds 递归
  扫描二级目录并把各包链接到 `package/feeds/qmodem/`，仅影响 qmodem feed、不动其它 feed；
- 各包 Makefile 的 `include ../../version.mk` 相对路径在 feed 符号链接布局下仍指向 QModem
  根目录的 `version.mk`，无需改动；既有的 FIX_QMODEM_VERSION / FIX_QMODEM_VOIP_DEP
  修改的是克隆目录真实文件，对 feed 链接同样生效。

### 变更文件

- `Scripts/Packages.sh`
- `CHANGELOG.md`

## [2026-10-03] 修正 AP3000M 5G 硬件上限：AX 160MHz（移除 80MHz 降级）

### 背景

此前误以为 AP3000M（MT7981，WiFi6）5G 硬件上限为 80MHz，并在构建期默认降级为 `HE80`。
实际硬件 5G 支持 AX 160MHz。据此移除「160MHz → 80MHz 自动降级」逻辑，默认 160MHz 直接产出
`HE160`（AX）。

### 变更

- `Config/OWRT-DEFAULT.txt`：顶部「频宽上限」与 `WIFI_5G_WIDTH` 注释由「上限 80MHz、自动降级」
  改为「AP3000M（MT7981）5G 硬件上限为 160MHz（AX），默认即 160MHz 不降级」；
- `Scripts/Settings.sh`：删除 AP3000M 的「5G 频宽 >80MHz 时降级为 HE80」分支，WiFi6 分支直接
  产出 `HE${WIFI_5G_WIDTH}`（默认 HE160），注释同步修正；
- `Scripts/Handles.sh`：AP3000M EEPROM 注入段的 5G htmode 由「默认 HE80、仅 ≤80MHz 才映射」
  改为直接映射 `HE${WIFI_5G_WIDTH}`（默认 HE160）；
- `AP3000M-EEPROM/99-ap3000m-eeprom`：模板默认 `radio1` htmode 由 `HE80` 改为 `HE160`（注入时
  仍由 Handles.sh 以 `WIFI_5G_WIDTH` 覆盖，此处仅保持模板默认一致）；
- `README.md`：WiFi6 · AP3000M 频宽行由「硬件上限 80MHz 时自动降级」改为「5G 硬件上限 160MHz」。

### 变更文件

- `Config/OWRT-DEFAULT.txt`
- `Scripts/Settings.sh`
- `Scripts/Handles.sh`
- `AP3000M-EEPROM/99-ap3000m-eeprom`
- `README.md`

## [2026-10-03] 无线默认频宽按设备世代区分：AP3000M 走 AX（HE）、H5000M 走 BE（EHT）

### 背景

两组设备频宽取值一致（2.4G `40MHz`、5G `160MHz`），但无线世代不同：AP3000M 为
WiFi6（802.11ax，MT7981B），H5000M 为 WiFi7（802.11be，MT7986 + MT5700M）。
此前 2.4G 默认频宽未按世代正确区分：H5000M 2.4G 误用 AX（`HE40`），AP3000M 2.4G
误用 802.11n（`HT40`）。本次统一为「频宽取值相同、htmode 前缀按设备世代区分」——
AP3000M 2.4G / 5G 均用 `HE`（AX），H5000M 2.4G / 5G 均用 `EHT`（BE），同机两个频段
世代对齐。

### 变更

- `Config/OWRT-DEFAULT.txt`：顶部 htmode 前缀说明改为「WiFi6（AX）2.4G / 5G 均用 HE、
  WiFi7（BE）2.4G / 5G 均用 EHT」；WiFi6 2.4G 频宽注释由 `htmode=HT40` 改为 `htmode=HE40`
  （AX），WiFi7 2.4G 频宽注释由 `htmode=HE40` 改为 `htmode=EHT40`（BE）；`WIFI_2G_WIDTH`
  与 `WIFI_2G_WIDTH_WIFI7` 数值保持 `40`、5G 保持 `160` 不变，仅世代前缀区分；
- `Scripts/Settings.sh`：设备世代分支的 htmode 映射修正——
  - WiFi6（非 H5000M）分支：2.4G 由 `HT${WIFI_2G_WIDTH}` 改为 `HE${WIFI_2G_WIDTH}`（AX），
    5G 保持 `HE${WIFI_5G_WIDTH}`；
  - WiFi7（H5000M）分支：2.4G 由 `HE${WIFI_2G_WIDTH}` 改为 `EHT${WIFI_2G_WIDTH}`（BE），
    5G 保持 `EHT${WIFI_5G_WIDTH}`；
  - 对应注释同步更新。

### 变更文件

- `Config/OWRT-DEFAULT.txt`
- `Scripts/Settings.sh`
- `README.md`

## [2026-10-01] 修复 Config/OWRT-DEFAULT.txt 无线默认配置未区分 WiFi6 / WiFi7

### 背景

`Config/OWRT-DEFAULT.txt` 是全系固件「后台地址 / 后台密码 / 主机名 / Wi-Fi 及频宽国家码」
等默认配置的唯一来源。此前无线部分只有一套默认值，未区分设备 WiFi 世代：AP3000M 为
WiFi6（802.11ax，MT7981B），H5000M 为 WiFi7（802.11be，MT7986 + MT5700M），两者虽同为
双频设备（5G 频段上限均为 160MHz），但世代能力不同，htmode 前缀与默认配置应分开管理，
便于按世代调整加密 / 频宽等策略。

### 变更

- `Config/OWRT-DEFAULT.txt`：无线部分拆分为两节——
  - WiFi6 默认（无后缀，AP3000M 等 802.11ax）：SSID `OWRT` / 密钥 `12345678`、
    加密 `psk-mixed`（mixed WPA/WPA2 PSK (CCMP)）、2.4G `40MHz`（HT40）、
    5G `160MHz`（HE160，AP3000M 硬件上限 80MHz 时构建期自动降级）、国家 `CN`；
  - WiFi7 默认（`_WIFI7` 后缀，H5000M 等 802.11be）：SSID `OWRT` / 密钥 `12345678`、
    加密 `psk-mixed`、2.4G `40MHz`（HE40）、5G `160MHz`（EHT160，双频设备
    5G 上限同为 160MHz，320MHz 仅限 6GHz 频段不启用）、国家 `CN`；
- `Scripts/Settings.sh`：新增设备 WiFi 世代选择逻辑，`WRT_CONFIG` 含 `H5000M` 时
  启用 `_WIFI7` 后缀默认值（未填写回退 WiFi6 默认）；htmode 前缀按世代区分——
  WiFi6 2.4G 用 `HT`、5G 用 `HE`，WiFi7 2.4G 用 `HE`、5G 用 `EHT`；
  保留 AP3000M（MT7981）5G 频宽 80MHz 自动降级；
- `.github/workflows/WRT-CORE.yml`：Load Default Settings 步骤导出新增的
  `WRT_SSID_WIFI7` / `WRT_WORD_WIFI7` / `WIFI_ENCRYPTION_WIFI7` /
  `WIFI_2G_WIDTH_WIFI7` / `WIFI_5G_WIDTH_WIFI7` / `WIFI_COUNTRY_WIFI7` 默认值；
- `Scripts/Settings.sh`：修复 `files/etc/uci-defaults/10-wifi-defaults` 生成脚本
  误用未定义的 `WIFI_SSID` / `WIFI_WORD` 变量（导致 SSID / 密钥注入恒为兜底默认值），
  改为与配置文件一致的 `WRT_SSID` / `WRT_WORD`；
- `README.md`：默认参数表按 WiFi6（AP3000M）/ WiFi7（H5000M）分行展示频宽，
  加密策略描述修正为 `mixed WPA/WPA2 PSK (CCMP)`。

## [2026-09-30]

### 新增

- **显式默认配置文件 `Config/OWRT-DEFAULT.txt`**：后台管理地址（`192.168.10.1`）、后台密码提示（无）、Wi-Fi 名称/密钥（`OWRT` / `12345678`）、加密策略（`psk-mixed`，WPA/WPA2 混合）、2.4G 频宽（`40MHz`）、5G 频宽（`160MHz`，AP3000M 硬件上限 80MHz 时构建期自动降级）、国家/地区码（`CN`）、主机名（`OWRT`）、Web 主题（`aurora`）、时区（`CST-8` / `Asia/Shanghai`）等局域网、无线与系统出厂参数统一由该文件管理，修改默认参数只需编辑它，无需改动脚本或工作流
- **配置文件易用性优化**：`Config/OWRT-DEFAULT.txt` 按「后台管理 / 系统标识 / Wi-Fi 无线 / 国家与时区」分区组织，每个配置项均附作用说明、取值格式、可选项与注意事项，顶部给出自定义方法（直接改文件即可；工作流 `inputs` 显式传入的值优先）与文件规范（UTF-8、LF 行尾、键名规则），用户可直接照注释修改

### 变更

- `Config/OWRT-DEFAULT.txt` — 新增上述显式默认配置（`WRT_IP` / `WRT_PW` / `WRT_SSID` / `WRT_WORD` / `WIFI_ENCRYPTION` / `WIFI_2G_WIDTH` / `WIFI_5G_WIDTH` / `WIFI_COUNTRY` / `WRT_NAME` / `WRT_THEME` / `WRT_TIMEZONE` / `WRT_ZONENAME`）
- `.github/workflows/WRT-CORE.yml` — 新增「Load Default Settings」步骤，从 `Config/OWRT-DEFAULT.txt` 加载全部 12 项默认参数并写入 `GITHUB_ENV`，工作流 `inputs` 显式传入的值优先；`WRT_THEME` / `WRT_NAME` 等 `inputs` 改为可选（未传入时读取配置文件默认值）；修复 `inputs` 中 `WRT_SSID` / `WRT_WORD` 重复定义及误删的 `WRT_REPO` / `WRT_BRANCH` 声明；修复 TEST 分支死代码（`Custom Settings` 中 `WRT_CONFIG` 字符串匹配改为 `WRT_TEST == "true"`）
- `Scripts/Settings.sh` — 默认时区由配置文件的 `WRT_TIMEZONE` / `WRT_ZONENAME` 驱动（带兜底默认值 `CST-8` / `Asia/Shanghai`）
- `.github/workflows/MTK-AUTO.yml`、`.github/workflows/OWRT-ALL.yml`、`.github/workflows/WRT-BUILD.yml` — 移除硬编码的 `WRT_SSID` / `WRT_WORD` / `WRT_IP` / `WRT_PW`，改由核心工作流从默认配置文件读取
- `Scripts/Settings.sh` — 加密策略由配置驱动（`psk-mixed`，MTK 闭源栈自动追加 `+ccmp`）；新增首次启动脚本 `files/etc/uci-defaults/10-wifi-defaults` 生成，强制覆盖国家码、2.4G/5G 频宽（HT40 / HE160，AP3000M 降级 HE80）、SSID、加密与密钥
- `Scripts/Handles.sh` — HomeProxy 目录查找深度由 `maxdepth 1` 修正为 `2`（viking feed 克隆为 `./packages/luci-app-homeproxy`）；AP3000M EEPROM 注入增加机型门控，仅 `WRT_CONFIG` 含 `AP3000M` 时执行，并按 `WIFI_5G_WIDTH` 驱动 5G 频宽降级；argon 主题与 mini-diskmanager 路径由硬编码改为 `find` 定位
- `Config/X86-qmodem-next.txt`、`Config/X86-qmodem.txt` — LF 归一化（移除 CRLF）
- `.gitattributes` — 追加 `*.py` / `*.uc` 的 LF 强制规则

### 修复

- 调用方工作流传参未声明 input（`WRT_REPO` / `WRT_BRANCH`）与重复 input（`WRT_SSID` / `WRT_WORD`）导致的潜在校验失败
- HomeProxy 数据预置因查找深度不足而整体跳过（viking feed 结构下实际位于两级子目录）
- x86 / H5000M 构建误带 AP3000M EEPROM 校准资产

## [2026-09-29]

### 修复

- **`luci-app-h5000m-netmode` 打包失败导致 MTK-AUTO #100 与 OWRT-ALL #76 共 6 个 job 全灭**（`672ae73`）：今日（09-29）两个定时构建的 6 个 job（H5000M / AP3000M / X86 × qmodem / qmodem-next）全部在 `Compile Firmware` 步骤失败，报 `make[3]: *** [feeds/luci/luci.mk:408: bin/packages/<arch>/base/luci-app-h5000m-netmode-1.8.5-r7.apk] Error 2` 与 `Process completed with exit code 2`。与内核、工具链、feeds 拉包无关，根因在插件仓库：`luci-app-h5000m-netmode` 后端重写为 Rust crate 后保留 `src/`（Rust 源码）且**没有 `src/Makefile`**，而 `feeds/luci/luci.mk` 两个分支判定条件不一致——`Build/Compile` 依据 `$(wildcard ${CURDIR}/src/Makefile)`（要求有 Makefile），`Package/.../install` 依据 `$(wildcard ${CURDIR}/src)`（只要目录存在）。于是 Compile 被跳过、`ipkg-install` 目录永不生成，install 阶段却仍执行 `Build/Install/Default`，对顶层没有 Makefile 的构建目录执行 `make ... install`，报 `*** No rule to make target 'install'.  Stop.` 并以 exit code 2 退出（本地复现一致），进而 `package/Makefile:255` → `toplevel.mk:268` 中断整个 `world` 编译。`src/` 由插件 `c68ac211`（2026-09-28）引入，9-27 的 #99 / #75 尚且成功，9-29 是首个带 `src/` 的构建。已在克隆该插件后新增 `FIX_H5000M_NETMODE_SRC` 删除 `src/`：真正被打进包的是 `root/`（预编译 ELF 本就在 `root/usr/sbin/` 下）、`htdocs/` 与 `po/`，产物不受影响；且 buildroot 内没有 Rust 工具链，本来就不该在构建机编译它。

### 变更文件

- `Scripts/Packages.sh` — 新增 `FIX_H5000M_NETMODE_SRC`（克隆 `luci-app-h5000m-netmode` 后移除无 Makefile 的 `src/` 目录）
- 上游根治：插件仓库 `LianXia233/luci-app-h5000m-netmode` 已补 `src/Makefile`（`94eb1a5`），空 `compile` / `clean` + `install` 拷贝已发布 ELF，两处修复互不冲突，下游 workaround 可保留或移除

## [2026-09-25]

### 修复

- **sing-box 过时补丁导致构建失败**：今日（09-24）OWRT-ALL 与 MTK-AUTO 两个定时构建同时 `failure`，首个失败步骤均为「编译固件」。根因为 `Scripts/Packages.sh` 克隆的 viking feed（`VIKINGYFY/packages`）中 sing-box 自带 `patches/100-fix-dns-tcp-close.patch` 与 `1.15.0_alpha8` 源码上下文不匹配（补丁引入的上游从未合入的 `HandleStreamDNSConnection`，而源码仍是 `HandleStreamDNSRequest`），`Build/Prepare` 阶段应用补丁报 `Patch failed!` 并 `Error 1`，整个固件编译中断。上游 `immortalwrt/packages` 的 sing-box 根本不携带该补丁也能正常构建，故判定为可安全移除的过时补丁。已在克隆 viking feed 后新增 `FIX_SINGBOX_STALE_PATCH`：仅当补丁内容含旧版标记 `HandleStreamDNSConnection` 时移除，若 VIKINGYFY 后续刷新补丁则自动跳过、不误删。

### 变更文件

- `Scripts/Packages.sh` — 新增 `FIX_SINGBOX_STALE_PATCH`（克隆 viking feed 后清理过时 sing-box 补丁）

## [2026-09-10]

### 修复

- **QModem 包版本号非法导致构建失败**（`9d7b145`）：今日（09-10）OWRT-ALL 与 MTK-AUTO 共 6 个 job（3 目标 × qmodem / qmodem-next 两变体）全部在 `Compile Firmware` 步骤失败，报 `ERROR: package/QModem/application/{libqmodem-sms, sms-tool_q} failed to build`。根因与编译、工具链、内核补丁无关：`Scripts/Packages.sh` 克隆的 QModem feed（`FUjr/QModem`）共享 `version.mk` 声明 `QMODEM_VERSION:=3.4.0-rc.3`，OpenWrt 新版 apk 打包器不接受 `-rc.N`——版本串 `3.4.0-rc.3-r1` 被 `apk mkpkg` 判为非法（Error 99），两个启用包（libqmodem-sms / sms-tool_q）打包失败即终止整个固件构建，两变体全灭。已在克隆 feed 后新增 `FIX_QMODEM_VERSION`：将 `X.Y.Z-rc.N` 改写为 apk 合法的 `X.Y.Z_rcN`（`3.4.0-rc.3` → `3.4.0_rc3`）；QModem 各包源码均内嵌 feed 仓库 `src/`，无版本化下载依赖，仅影响版本元数据；上游若已改合法则自动跳过。

### 变更文件

- `Scripts/Packages.sh` — 新增 `FIX_QMODEM_VERSION`（克隆 QModem 后改写共享版本号）

## [2026-08-31]

### 修复

- **AP3000M 编译失败：预编译相对路径 + 失败回退判定失效**（`39960f0`）：`MTK-AUTO` 中 `AP3000M-qmodem` 与 `AP3000M-qmodem-next` 自 8 月 29 日起稳定在 `Compile Firmware` 步骤失败，报 `ERROR: package/luci-app-airpi-fancontrol failed to build`；同 run 中同为 filogic 平台的 H5000M 两个配置均构建成功。与依赖缺失、语法错误、ImmortalWrt 上游源码无关，是三处脚本缺陷叠加：
  - **交叉链接器使用了相对路径**：`Prebuild AirPi Rust Binary` 步骤以 `find ./staging_dir` 取得 `./staging_dir/toolchain-.../aarch64-openwrt-linux-musl-gcc`，随后脚本 `cd` 进 crate 目录执行 `cargo build`；cargo 按调用时的 CWD 解析 `CARGO_TARGET_<TRIPLE>_LINKER`，实际去找 `<crate>/./staging_dir/...`，必然 `linker ... not found`，预编译以 exit 101 失败。已改为 `find "$(pwd)/staging_dir"` 并追加 `readlink -f` 归一化，同时优先精确匹配 `aarch64-openwrt-linux-musl-gcc`，避免 `head -1` 命中带版本号后缀的变体。
  - **失败回退判定失效（致命放大器）**：该步骤用 `if ( set -e ... ); then` 承载整段逻辑，但 bash 在 `if` 条件求值上下文中会忽略 `errexit`——`cargo` 失败后脚本继续往下执行，`if` 最终取**最后一条命令**（`inject_airpi_prebuilt.py`，exit 0）的退出码，于是错误地注入 `AIRPI_PREBUILT:=1` 并打印「预编译完成」，步骤结论为 `success`。包 Makefile 的预编译分支随后 `INSTALL_BIN` 一个并不存在的二进制，直接失败。已改为 `set +e; ( ... ); RC=$?; set -e`，让 `errexit` 真正生效、退出码可被正确捕获。实测 `if ( set -e ... )`、函数 + `if f`、`( ... ) || RC=$?` 三种写法均会让 `errexit` 失效，只有先 `set +e` 再取 `$?` 有效。
  - **编译重试与诊断分支从不执行**：`Compile Firmware` 的 `set -o pipefail` 叠加 GitHub Actions `run` 默认的 `bash -e`，首次 `make` 失败即让整个步骤就地终止，既不会以 `V=s` 并行重试，也不会输出出错包注解，日志里只剩 `Process completed with exit code 2`，显著抬高定位成本。已改为 `set +e -o pipefail`。
- 另新增两道防御：`cargo` 退出 0 但产物缺失时同样判定为失败；包 Makefile 已被标记预编译而二进制不存在时，自动撤销注入并回退 `rust/host` 源码构建。

### 变更文件

- `.github/workflows/WRT-CORE.yml` — 链接器绝对路径化与 `readlink -f` 归一化、失败回退改为 `set +e` + `$?` 捕获、产物自检、预编译标记一致性兜底、编译步骤改 `set +e -o pipefail`

## [2026-08-29] 源码切换：H5000M / AP3000M 改用 ImmortalWrt 主线
### Changed
- MTK-AUTO 工作流中 H5000M / AP3000M 的 `SOURCE` 由 `VIKINGYFY/immortalwrt` 切换为 `immortalwrt/immortalwrt`，`BRANCH` 由 `owrt` 调整为 `master`；X86（OWRT-ALL）保持 `immortalwrt/immortalwrt` + `master` 不变。
- WRT-BUILD 手动编译默认源码/分支同步调整为 `immortalwrt/immortalwrt` + `master`。
- README.md / index.html：删除 H5000M、AP3000M 使用 VIKINGYFY `owrt` 分支的说明，统一描述为基于 ImmortalWrt 主线 `master` 分支；Release 标签示例由 `VIKINGYFY-owrt` 改为 `immortalwrt-master`；固件底包说明同步更新。
- 鸣谢保留 VIKINGYFY（OpenWRT-CI 编译框架），仅移除对其 immortalwrt 源码分支的依赖说明。



## [2026-08-29]

### 优化

- **编译缓存失效修复**（`2382aacb`）：工具链缓存键原先绑定源码 commit hash，上游一有提交即整体失效，加上 `ccache` 从未真正启用，导致每次都从零构建工具链。已将缓存键改为「目标平台 + 源码 + 分支」并补 `restore-keys` 前缀回退，新增独立的 `dl/` 下载缓存，启用 `CONFIG_CCACHE` 并将 `CCACHE_DIR` 指向被缓存目录（限 5G、开启压缩），同时移除 cache miss 时清空历史缓存的逻辑。实测 H5000M 命中缓存后编译由 **3h13m 降至 31m**。
- **编译超时保护**（`024aa52c`）：作业被平台 6 小时硬上限杀掉时，缓存的 post 保存步骤整段跳过，形成「超时 → 无缓存 → 下次继续冷编译 → 再超时」的死循环。已新增 `timeout-minutes: 345`（低于硬上限）、为两个缓存步骤开启 `save-always: true`，并把编译失败重试由 `make -j1 V=s` 改为 `make -j$(nproc) V=s`，避免单线程回退把几小时的编译拖过上限。
- **AirPi Rust 预编译，跳过 rust/host 构建（仅 AP3000M）**（`413bbf4d`）：`luci-app-airpi-fancontrol` 的守护进程由 Rust 编写，默认会走 OpenWrt 的 `rust/host` 从源码构建完整 Rust + LLVM 工具链，这是 AP3000M 比同为 filogic 的 H5000M 恒定慢约 2 小时、并多次撞破 6 小时上限的原因。已照搬上游 [luci-app-airpi3000m-fancontrol](https://github.com/LianXia233/luci-app-airpi3000m-fancontrol) 的 CI 做法：用 runner 自带的 rustup 配合源码树里已构建好的 aarch64 musl 交叉链接器直接 `cargo build --target aarch64-unknown-linux-musl`，再通过 `AIRPI_PREBUILT=1` / `AIRPI_PREBUILT_BIN` 交给包 Makefile，完全跳过 `rust/host` 构建；预编译失败会自动回退到源码构建并给出警告，不影响固件产出。
- **预编译注入失败安全回退**（`d1425db4`）：`AIRPI_PREBUILT` 的注入调用原先落在受保护子 shell 之外，一旦注入失败（例如上游 Makefile 版式变化导致锚点 `include $(TOPDIR)/rules.mk` 缺失）会让整个步骤失败、中断固件编译，与设计意图相反。已将注入调用移入受保护子 shell，失败时由外层 `if` 接管进入回退分支；同时把 `PKG_DIR` / `PREBUILT_DIR` 改为绝对路径，修正子 shell 内 `cd` 导致的相对路径失效。
- **AP3000M 专用插件按机型条件引入**（`413bbf4d`）：`luci-app-airpi-fancontrol` 与 `kmod-airpi-gpio-fan` 改为仅 `WRT_CONFIG` 含 `AP3000M` 时才克隆引入。该插件按 AP3000M 的 GPIO / PWM sysfs 路径 / 温度传感器探测顺序适配，H5000M 与 X86 用不到也不具备对应硬件依赖，无需再拉取扫描。

### 变更

- **源码切换：H5000M / AP3000M 改为 VIKINGYFY/immortalwrt `owrt` 分支**（`87ef5b49`）：`MTK-AUTO` 工作流对应配置（H5000M / AP3000M）由原源码切换至 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) 的 `owrt` 分支；`X86` 配置保持 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) 主线 `master` 分支不变。

### 文档同步

- `README.md` — 支持配置表新增「编译源码」列并补 X86 行；快速开始、固件底包、源码上游鸣谢补充双源码分支说明；在线升级标签示例更新为 `H5000M-qmodem-next-VIKINGYFY-owrt-...` / `X86-qmodem-next-immortalwrt-master-...`；文档更新日期改为 2026-08-29
- `index.html` — 「技术规格」卡片改为「双源码构建」，注明 H5000M / AP3000M 基于 VIKINGYFY owrt 分支、x86 基于主线 master
- `CHANGELOG.md` — 重构当日条目，按提交分条记录本轮编译耗时优化

### 变更文件

- `.github/workflows/WRT-CORE.yml` — 缓存键与 `restore-keys` 改造、新增 `dl` 缓存、启用 ccache、`timeout-minutes`、缓存 `save-always`、并行重试、新增 AirPi Rust 预编译步骤、注入调用移入受保护子 shell
- `.github/workflows/Cache-Clean.yml` — 取消每周定时全量清缓存（改为手动触发），避免每周一次强制冷启动
- `Scripts/Packages.sh` — AirPi 插件按机型条件引入
- `Scripts/inject_airpi_prebuilt.py` — 新增，向 `luci-app-airpi-fancontrol` 的 Makefile 注入 `AIRPI_PREBUILT` 标记
- `Config/AP3000M-qmodem.txt`、`Config/AP3000M-qmodem-next.txt` — 移除无人使用的 `luci-compat` / `luci-lua-runtime`（插件 v4.0 起为纯 JS 实现，仅依赖 `luci-base`）

## [2026-08-25]

### 新增

- **TTYD Web 终端**：全机型默认集成 [ttyd](https://github.com/tsl0922/ttyd) 网页命令行终端，LuCI「系统 → TTYD 终端」页面可在浏览器直接操作设备 Shell。`Config/GENERAL.txt` 新增并默认启用 `ttyd`、`luci-app-ttyd`、`luci-i18n-ttyd-zh-cn` 三个软件包。

### 变更文件

- `Config/GENERAL.txt` — 新增 TTYD Web 终端配置段（`ttyd` / `luci-app-ttyd` / `luci-i18n-ttyd-zh-cn`，均默认启用）

## [2026-08-18]

### 修复
- **ovpn-dco 编译失败（过时补丁与上游冲突）**：最新 Actions 运行（`MTK-AUTO` / `OWRT-ALL`）全部在 `Compile Firmware` 阶段因 `ovpn-dco` 包构建失败。`Scripts/Handles.sh` 此前会向 feeds 的 `ovpn-dco` 包注入自研补丁 `0002-fix-recvmsg-addr-len-6.18.40.patch`（修复 Linux 6.18.40+ recvmsg 兼容性），但上游 `ovpn-backports` 在 7.1.0.2026080300 版本已内置完全相同的修复（`linux-compat.h` 的 `OVPN_PROTO_RECVMSG_HAS_ADDR_LEN` 宏 + `tcp.c` 的 `#elif OVPN_PROTO_RECVMSG_HAS_ADDR_LEN`），继续注入旧补丁导致 `patch` hunk 失败（`1 out of 1 hunk FAILED`），`ERROR: package/feeds/packages/ovpn-dco failed to build`。已移除该过时补丁注入块，由上游自带修复接管。

### 变更文件
- `Scripts/Handles.sh` — 移除 ovpn-dco 0002 过时补丁注入块

## [2026-08-15]

### 修复
- **CI 编译失败修复（apt 源哈希不一致 + dockerd feeds 回归）**：最新 Actions 运行（`MTK-AUTO` / `OWRT-ALL`）中 `H5000M-qmodem-next` 与 `X86-qmodem*` 编译失败。
  - **H5000M-qmodem-next**：`WRT-CORE.yml` 的 `Initialization Environment` 执行 `apt update` 时，GitHub runner 预置的 `google-chrome` apt 源镜像偶发哈希不一致（`File has unexpected size (1411 != 1412)`），`apt update` 退出 100 中断整个初始化步骤。已在 `apt update` 前移除 `google-chrome*.list` 并增加一次重试，使非必需源的临时故障不再阻断构建。
  - **X86-qmodem / X86-qmodem-next**：`Config/X86-qmodem*.txt` 中 `CONFIG_PACKAGE_luci-app-dockerman=y` 拉入 `feeds/packages` 的 `dockerd`（29.6.1），该包在 immortalwrt/packages master 于 2026-08-14 引入回归——`hack/make.sh binary` 在复制嵌套可执行文件时路径为空导致 `cp: cannot stat ''`，进而 `make[3]: *** [Makefile:166 ...] Error 1` 使 `world` 编译失败（08-13 同配置仍成功，属 feeds 漂移）。已将 `luci-app-dockerman` 置为 `=n` 移除损坏依赖；该改动不影响 qmodem 主体功能，feeds/packages 修复 dockerd 后改回 `=y` 即可恢复 Docker 支持。

### 变更文件
- `.github/workflows/WRT-CORE.yml` — `apt update` 容错：移除 google-chrome 源 + 重试一次
- `Config/X86-qmodem-next.txt`、`Config/X86-qmodem.txt` — `luci-app-dockerman` 由 `=y` 改为 `=n`

## [2026-08-12]

### 修复

- **HomeProxy ucode 兼容性修复**：ImmortalWrt master 已移除 `luci.sys.init_action` 且 ucode 不含 `math` 模块，导致订阅更新与客户端配置生成失败（sing-box 无法启动，页面报 "URLTest: 无效节点"）。在 `Scripts/Handles.sh` 中加入自动覆盖修复，CI 构建时替换上游的两个脚本：
  - `update_subscriptions.uc`：移除 `import { init_action } from 'luci.sys'`，将 `init_action('homeproxy', 'restart')` 替换为 `system('/etc/init.d/homeproxy restart >/dev/null 2>&1')`。
  - `generate_client.uc`：移除 `import { isnan } from 'math'`，将 `isnan(int(i))` 替换为 `type(int(i)) === 'double'`。
  - 修复脚本存放于 `Scripts/homeproxy/`，不包含节点信息。

## [2026-08-10]

### 新增
- **在线升级插件 `luci-app-online-upgrade`**：所有机型默认启用，支持从本仓库 GitHub Releases 在线升级固件。
- **按机型自动匹配固件**：构建时将设备身份（机型 + QModem 前端类型 + 构建标签）烙入 `/etc/online-upgrade-device`，插件据此动态解析本机对应配置的最新 Release 并匹配正确的固件包，避免下错型号/前端。

### 变更文件
- `Scripts/Packages.sh` — 新增 `gooyjq/luci-app-online-upgrade` 仓库克隆
- `Config/GENERAL.txt` — 新增 `CONFIG_PACKAGE_luci-app-online-upgrade=y`（全机型启用）
- `Scripts/online-upgrade/online-upgrade.sh` — 定制脚本：设备身份读取 + 自动匹配 Release + 构建标签判新
- `Scripts/online-upgrade/99-online-upgrade` — 定制默认 UCI 配置（仓库、代理、自动匹配）
- `Scripts/Handles.sh` — 烙入设备身份文件 + 覆盖上游插件脚本/默认值
- `README.md` — 补充在线升级说明

### 修复
- **在线升级 Release 识别**：`online-upgrade.sh` 中 `grep "tag_name":"` 缺少空格，与 GitHub API 实际返回的 `"tag_name": "` 不匹配，导致自动匹配模式无法找到标签。已修正正则并替换有 bug 的 `jsonfilter`（处理大 JSON 卡死）为 `grep`/`sed` 方案。
- **固件文件匹配通配**：`FIRMWARE_PATTERN` 默认值 `squashfs-sysupgrade\.bin$` 太严格，无法匹配文件名中间含分支/日期等额外字段的实际固件（如 `squashfs-sysupgrade-immortalwrt-master-wifi-yes-26.08.10.bin`）。已改为 `squashfs-sysupgrade.*\.bin$`，同时覆盖 `Handles.sh` 构建时设备身份文件和 `99-online-upgrade` 默认 UCI。
- **前端页面显示实际配置**：LuCI 在线升级页面此前硬编码了默认仓库地址而非从 UCI 读取，导致页面始终显示 `gooyjq/ImmortalWrt-Builder` 等默认值。现新增 `fix-frontend.py` 构建脚本，自动修复前端 JS：页面加载时从 UCI 读取 `repo`/`tag`/`firmware_pattern`/`proxy` 并填充表单，`saveCfg` 同时保存全部四项配置。

### 变更文件
- `Scripts/online-upgrade/online-upgrade.sh` — 修复 tag 匹配 + jsonfilter→grep + ASSET_BLOCK 范围
- `Scripts/online-upgrade/99-online-upgrade` — FIRMWARE_PATTERN 通配
- `Scripts/online-upgrade/fix-frontend.py` — 新增：构建时修复前端 JS 从 UCI 读配置
- `Scripts/Handles.sh` — FIRMWARE_PATTERN 通配 + 调用 fix-frontend.py

## [2026-08-09]

### 修复
- **WiFi 加密**：修复 AP3000M 开源 mt76 驱动下 WiFi 密码不生效的问题。`mac80211.uc` 默认生成 `encryption='none'`，Settings.sh 仅修改了 `ssid` 和 `key` 而未设置加密方式，导致密码被忽略。现已追加 `encryption='psk2'` 设置。
- **默认时区**：修复固件默认时区为 UTC 的问题。`config_generate` 默认写入 `timezone='GMT0'` / `zonename='UTC'`，现已改为 `CST-8` / `Asia/Shanghai`（北京时间）。
- **AP3000M 风扇插件缺失**：修复 AP3000M 编译时 `luci-app-airpi-fancontrol` 和 `kmod-airpi-gpio-fan` 未被编入的问题。`Packages.sh` 中仅有 H5000M 风扇插件，现已追加 AP3000M 对应的 `luci-app-airpi3000m-fancontrol` 仓库克隆语句。

### 变更文件
- `Scripts/Settings.sh` — WiFi 加密修复 + 默认时区修复
- `Scripts/Packages.sh` — 新增 `luci-app-airpi-fancontrol` 仓库克隆
