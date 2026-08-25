<div align="center">

# 🚀 H5000M & AP3000M & x86 · ImmortalWrt 定制固件说明书

*基于 ImmortalWrt 主线源码，覆盖 Hiveton H5000M、AirPi AP3000M 与 x86 平台的定制化编译配置与模组解析*

</div>

<br>

## 🚀 快速开始

本仓库通过 GitHub Actions 自动编译 H5000M、AP3000M 与 x86 平台的 ImmortalWrt 固件，无需本地搭建编译环境。

| 入口工作流 | 触发方式 | 用途 |
| :--- | :--- | :--- |
| **WRT-BUILD** | 手动 `workflow_dispatch` | 手动编译设备固件，可临时追加插件或仅导出配置文件（`TEST=true`） |
| **MTK-AUTO** | 每天随 `Auto-Clean` 完成后自动触发，亦可手动 | 自动编译已配置的 MTK 设备的 QModem Next 与传统 QModem 版本并发布 Release |
| **OWRT-ALL** | 每天随 `Auto-Clean` 完成后自动触发，亦可手动 | 自动编译 X86 的 QModem Next 与传统 QModem 版本并发布 Release |
| **Auto-Clean** | 每日 05:00 (CST) 定时，亦可手动 | 清理旧 Release（保留最近 1 个）与 30 天前的运行记录 |
| **Cache-Clean** | 每周定时，亦可手动 | 清空 GitHub Actions 缓存 |

**手动触发步骤**：进入仓库 `Actions` → 选择 `WRT-BUILD` → `Run workflow`，选择带 `-qmodem-next` 或 `-qmodem` 后缀的配置。编译完成后，固件会出现在以配置名开头的独立 Release 中。

每个硬件型号均提供两套配置：`*-qmodem-next` 使用现代 JavaScript 前端并启用 `sms-forwarder-next`，`*-qmodem` 使用传统 LuCI 前端及其中文翻译。两套配置共用 `qmodem` 核心、通用 QMI 驱动和连接管理器，不会在同一固件中同时启用两个前端。Release 标签和固件文件名均包含配置后缀，便于区分和选择。

> 💡 仓库根目录的 [`index.html`](./index.html) 是一份精美的固件发布落地页，可直接用 GitHub Pages 托管，或本地打开预览发布信息。

<br>

## 📂 项目结构

```
OpenWRT-CI-H5000M/
├── .github/workflows/
│   ├── WRT-CORE.yml     # 云编译公用核心（被下面两个调用）
│   ├── WRT-BUILD.yml    # 手动编译入口
│   ├── MTK-AUTO.yml     # 定时自动编译 MTK 设备
│   ├── Auto-Clean.yml   # 每日清理旧 Release / 运行记录
│   └── Cache-Clean.yml  # 清理 Actions 缓存
├── AP3000M-EEPROM/         # AirPi AP3000M EEPROM 自动初始化（模板 + uci-defaults）
├── Config/
│   ├── GENERAL.txt            # 通用插件与内核模块配置
│   ├── QMODEM-NEXT.txt        # QModem Next 前端及依赖
│   ├── QMODEM.txt             # 传统 QModem 前端及依赖
│   ├── H5000M-*.txt           # Hiveton H5000M 的两种 QModem 配置
│   ├── AP3000M-*.txt          # AirPi AP3000M（开源 mt76）的两种配置
├── Scripts/
│   ├── Packages.sh   # 下载 / 更新第三方插件与主题
│   ├── Handles.sh    # EEPROM 自动注入、HomeProxy 资源预置与各类插件兼容修复
│   └── Settings.sh   # 默认值、WIFI、主机名等个性化设置
├── index.html        # 固件发布落地页
├── CHANGELOG.md      # 更新日志
├── LICENSE
└── README.md
```

<br>

## 🎯 支持的编译配置

本仓库提供以下设备编译配置：

| 配置 | 平台 | 设备 | Wi-Fi |
| :--- | :--- | :--- | :--- |
| `H5000M` | MediaTek Filogic | Hiveton H5000M（鼎桥 MT5700M 5G CPE） | ✅ 开启 |
| `AP3000M` | MediaTek Filogic / MT7981 | AirPi AP3000M | ✅ 开启（开源 mt76） |

`AP3000M` 基于 ImmortalWrt 主线源码编译，使用开源 `mt76` Wi-Fi 驱动栈，无需额外闭源驱动。EEPROM 通过 `Handles.sh` 在构建时自动注入，首次启动时由 `AP3000M-EEPROM/99-ap3000m-eeprom` 写入 `factory` 分区，修正 radio1 为 5G 模式。手动运行 `WRT-BUILD` 时直接选择 ImmortalWrt 主线源码即可。

<br>

## 💖 鸣谢与致敬

本固件的高效自动化编译、底层系统的稳定性以及对特定 5G 模组的完美适配，离不开开源社区开发者的无私奉献。在此特别感谢以下作者及其开源项目：

> **🐧 源码上游：[ImmortalWrt](https://github.com/immortalwrt/immortalwrt/)**
> 
> 感谢 ImmortalWrt 团队提供的最新主线源码。其卓越的路由性能和丰富的本地化特性，为固件的开发提供了无比坚实的底层源码基础。
> * 🔗 **项目链接**：[immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt/)

> **👤 基础底包、插件优化与编译框架：[VIKINGYFY](https://github.com/VIKINGYFY)**
> 
> 感谢作者提供的 OpenWRT-CI 项目。作者不仅打造了高效的云端自动化编译框架，更为本项目提供了稳定可靠的**基础底包固件配置**、**深度的插件细节优化**，以及**大量优质实用的额外插件支持**，极大降低了固件定制门槛并全面提升了路由器的整体体验和可玩性。
> * 🔗 **项目链接**：[OpenWRT-CI](https://github.com/VIKINGYFY/OpenWRT-CI)

> **👤 CPE 核心插件支持：[FAN789](https://github.com/FAN789)**
> 
> 感谢作者为 Hiveton H5000M 及 MT5700M 模组开发的系列核心控制插件，赋予了该设备真正的 5G CPE 灵魂。
> * 🔗 **主页链接**：[https://github.com/FAN789](https://github.com/FAN789)
> * ❄️ **智能风扇温控**：[luci-app-h5000m-fancontrol](https://github.com/FAN789/luci-app-h5000m-fancontrol)
> * 🔀 **网络模式切换**：[luci-app-h5000m-netmode](https://github.com/LianXia233/luci-app-h5000m-netmode)

> **👤 通用模组界面：[LianXia233](https://github.com/LianXia233)**
>
> 感谢作者将原 MT5700M 专用界面重构为基于 QModem 的通用 LuCI Web UI，不再绑定具体模组型号。
> * 📦 **通用模组管理**：[luci-app-qmodem-generic](https://github.com/LianXia233/luci-app-qmodem-generic)

> **👤 模组管理套件：[FUjr](https://github.com/FUjr)**
> 
> 感谢作者开发的 QModem 蜂窝模组综合管理系统。本固件集成 **luci-app-qmodem-next** 现代界面，提供模组监控、拨号管理与 AT 调试能力。
> * 🔗 **项目链接**：[FUjr/QModem](https://github.com/FUjr/QModem)
> * 📖 **用户手册**：[user-guide.zh-cn.md](https://github.com/FUjr/QModem/blob/main/docs/user-guide.zh-cn.md)

---

## 📡 一、 硬件平台与固件底层概述

**Hiveton H5000M** 是一款高性能的 5G CPE（Customer Premises Equipment）路由器，致力于将高速的 5G 移动网络转化为稳定可靠的局域网 Wi-Fi 或有线网络。

| 核心特征 | 详情描述 |
| :--- | :--- |
| 🏗️ **固件底包** | **基于 ImmortalWrt 主线最新源码构建**。内核层面已开启硬件加解密优化（`kmod-cryptodev`, `kmod-tls`），为科学分流和安全组网提供底层加速。 |
| 🖥️ **基础架构** | 采用 **联发科 (MediaTek) Filogic** 平台 (如 MT7986 系列)，具备强大的网络数据转发能力与 Wi-Fi 7 性能。 |
| 📶 **核心模组** | 深度集成 **MT5700M 5G 模组**，支持直接插卡上网，实现 5G 高速蜂窝接入。 |
| ❄️ **散热设计** | 针对 5G 模组高负载下的发热特性，设备配备了**主动散热风扇**，专为高负载网络转化设计，确保极限性能下不降频。 |

---

## 🧩 二、 核心专属插件详解

固件深度整合了 FAN789 提供的定制插件、LianXia233 的通用 QModem 界面与 FUjr 的 QModem 模组管理套件，完美释放 Hiveton H5000M 的 5G 硬件潜力。以下是核心插件的功能剖析：

### 1. 通用 QModem 模组管理 (`luci-app-qmodem-generic`)
该插件通过 QModem 的 `qmodem` ubus 接口提供通用 LuCI 管理界面，不绑定具体模组型号，适用于 H5000M 的 MT5700M 模组。

* **📊 状态监控**：实时展示模组型号、信号质量、网络注册状态、运营商及 IMEI/IMSI 等信息。
* **🔌 移动数据管理**：支持 APN、拨号、IP 详情与连接会话管理。
* **📡 射频与小区**：提供频段、邻区、锁频锁小区及诊断功能。
* **⚙️ AT 与维护**：通过 QModem 的 ubus 接口执行 AT 指令，并提供模组与 SIM 维护操作。

### 2. 硬件级风扇温控 (`luci-app-h5000m-fancontrol`)
5G 高速传输伴随显著发热，该插件确保了设备在满负荷运作下的温控稳定。

* **🌡️ 智能监测**：实时读取 CPU 和 MT5700M 模组的双路温度传感器数据。
* **🌀 多档调速**：根据设定的温度阈值（如阈值 A、B、C），自动调节风扇的 PWM 转速百分比，兼顾低负载静音与高负载散热。
* **🛠️ 自定义配置**：用户可自由调整启动温度、目标温度，打造个性化的散热策略。

### 3. 网络模式无缝切换 (`luci-app-h5000m-netmode`)
应对复杂的网络接入环境（5G 蜂窝与传统有线宽带双接入），提供极简的管理体验。

* **🔄 一键切换**：支持在“仅 5G 模式”、“仅有线宽带模式”及“负载均衡/故障转移模式”间快速切换，告别复杂的接口配置。
* **⚡ 链路检测**：搭配 mwan3，实时监测链路连通状态，主链路故障时实现毫秒级无缝切换，确保网络永不掉线。

### 4. QModem 模组管理（双配置）

固件提供两种互斥配置：`*-qmodem-next` 使用现代 JavaScript LuCI 前端 `luci-app-qmodem-next`，`*-qmodem` 使用传统 LuCI 前端 `luci-app-qmodem`。两者都与 `qmodem` 核心脚本配套使用，可在 LuCI 的“网络”菜单中显示；单个固件不会同时启用两个前端。

* **📊 模组全景监控**：制造商 / 型号 / 固件 / IMEI、信号质量（RSSI / RSRP / RSRQ / SINR）与网络注册状态实时呈现。
* **📞 拨号与高级调试**：重新设计的拨号日志与状态显示；支持锁频段、锁小区及自定义 AT 指令。
* **✉️ 短信管理**：可配合已启用的 `sms-tool` 与 `sms-tool_q` 管理模组短信。
* **🧬 依赖策略**：Next 配置依赖 `qmodem` 核心脚本及 `sms-forwarder-next`；传统配置使用 `luci-i18n-qmodem-zh-cn`。核心脚本会带入 `ubus-at-daemon`、`tom_modem`、`modem_scan` 与 `sms-tool_q` 等依赖。两种配置均显式保留 `quectel-CM-5G-M` 与 ImmortalWrt 的通用 `kmod-usb-net-qmi-wwan`，并选择通用 QMI 驱动，避免厂商或 NSS 驱动冲突。
* **⚠️ 使用提示**：本固件还提供 `luci-app-qmodem-generic` 通用界面；它与所选 QModem 前端都通过 QModem 管理模组，建议不要同时执行拨号或 AT 操作。QModem Next 不包含 MWAN、TTL 等旧版可选扩展。

### 5. 固件在线升级（`luci-app-online-upgrade`）

基于 [gooyjq/luci-app-online-upgrade](https://github.com/gooyjq/luci-app-online-upgrade) 定制，**所有机型默认启用**，入口在 LuCI **系统 → 在线升级**。

- **🔍 按机型自动匹配**：固件在构建时会把本机身份（机型 + QModem 前端类型 + 构建标签）烙入 `/etc/online-upgrade-device`。插件运行时据此动态解析本仓库对应配置的最新 Release，自动挑选出匹配当前设备的固件包，**不会下错型号/前端**。
- **🏷️ 精准区分**：Release 标签格式为 `{配置名}-{源码owner}-{分支}-{日期}`（如 `H5000M-qmodem-next-immortalwrt-master-26.08.10-...`）。传统 `H5000M-qmodem` 与 `H5000M-qmodem-next` 通过 `-{源码owner}-` 锚点严格区分，互不错配。
- **✅ 已是最新判断**：以本机固件对应的构建标签与最新 Release 标签比对，一致即提示已是最新；有新构建才提示升级。
- **💾 保留配置升级**：一键升级默认保留系统配置（`keep_config`），升级前自动备份、升级后自动恢复；并内置 GitHub 下载加速代理（`gh.acg2.mom`）。

> 默认仓库指向本仓库 `LianXia233/H5000M-CI-Qmodem`。如需改用其它仓库/代理，可在 LuCI 页面或 UCI（`/etc/config/online-upgrade`）中修改 `repo` / `proxy` / `tag`（`tag` 留空即走自动匹配）。

---

## 🛠️ 三、 固件底层组件与扩展支持

得益于 ImmortalWrt 优秀的底包基础，Hiveton H5000M 不仅具备卓越的基础路由性能，还将扩展性推向极致：

* **内核级加解密加速**：开启 `kmod-cryptodev` 与 `kmod-tls`，大幅提升代理工具（如 HomeProxy、OpenClash）和加密隧道的吞吐量，降低 CPU 占用。
* **USB 驱动栈扩展**：包含 `kmod-usb-core`, `kmod-usb3` 及 `kmod-usb-net-qmi-wwan` 等丰富驱动，确保系统准确识别各类移动通信模组。
* **轻量级 NAS 存储**：支持 NVMe 固态硬盘（`kmod-nvme`）挂载，结合 BTRFS 文件系统与 Samba4 共享，轻松打造家庭数据中心。
* **安全异地组网**：内置 EasyTier、Tailscale 等主流 SD-WAN 工具，轻松实现内网设备的远程安全访问。

<br>

> 📅 *文档更新日期：2026年8月9日*
> 💡 *本说明文档由项目编译配置与社区开源信息整合生成。*
