# 更新日志

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
