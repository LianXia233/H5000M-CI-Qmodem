<div align="center">

# 🚀 H5000M & AP3000M & x86 · ImmortalWrt 定制固件说明书

**基于 ImmortalWrt 主线源码 · 专为 5G CPE、Wi-Fi 路由器与软路由量身打造的自动化云编译生态**

[![ImmortalWrt Master](https://img.shields.io/badge/ImmortalWrt-master%20(Mainline)-brightgreen?logo=openwrt&logoColor=white)](#)
[![MediaTek Filogic](https://img.shields.io/badge/Platform-MediaTek%20Filogic-orange)](#)
[![x86_64](https://img.shields.io/badge/Platform-x86__64-informational)](#)
[![QModem Next](https://img.shields.io/badge/Cellular-QModem%20Next%20%2F%20Classic-blueviolet)](#)
[![CI Build](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-blue?logo=githubactions&logoColor=white)](#)

*全面支持 Hiveton H5000M (MT7986 + MT5700M)、AirPi AP3000M (MT7981B) 与通用 x86_64 平台*

---

</div>

## 📌 核心特性亮点

- ⚡ **纯正主线构建**：全系固件（H5000M / AP3000M / x86）均直接基于 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) 官方主线 `master` 分支编译，拥抱最新内核与特性。
- 📶 **QModem 双前端架构**：提供现代响应式 JavaScript（`*-qmodem-next`）与经典汉化 LuCI（`*-qmodem`）双版本，底层共享通用 QMI 驱动栈，互斥编译绝不冲突。
- 🔄 **硬件级在线 OTA 升级**：深度定制 `luci-app-online-upgrade`，固件内置设备身份唯一特征锚点，自动匹配对应 Release，保留配置安全无缝直升。
- 🛠️ **AP3000M 射频免驱修复**：采用开源 `mt76` 驱动栈，启动期自动写入 EEPROM 模板并绑定真实 MAC，彻底解决出厂 factory 分区丢失导致无 Wi-Fi 的痛点。
- ❄️ **CPE 专属硬件控制**：集成双路温感风扇 PWM 阶梯调速、5G/有线链路状态监测与网络模式秒级切换。

---

## 🎯 硬件支持与固件矩阵

| 目标机型 | 平台架构 / SoC | 硬件形态与特性 | Wi-Fi 驱动栈 | 源码上游 / 分支 |
| :--- | :--- | :--- | :---: | :--- |
| **`H5000M`** | MediaTek Filogic (MT7986) | Hiveton H5000M 5G CPE（鼎桥 MT5700M） | ✅ 开启 | `immortalwrt/immortalwrt` (`master`) |
| **`AP3000M`** | MediaTek Filogic (MT7981B) | AirPi AP3000M Wi-Fi 6 路由器 | ✅ 开启（开源 mt76） | `immortalwrt/immortalwrt` (`master`) |
| **`X86`** | x86_64 通用架构 | 工控机 / 软路由 / 物理 PC / 虚拟机 | — | `immortalwrt/immortalwrt` (`master`) |

> [!NOTE]
> **落地页预览**：仓库根目录内置现代化设计风格的 [`index.html`](./index.html)，可直接开启 GitHub Pages 作为固件展示主页，亦可在本地直接双击打开预览发布详情。

---

## 🧩 核心功能与模组生态

### 1. QModem 蜂窝模组双方案对比

每个硬件机型均编译发布两套互相独立的配置，用户可按交互习惯自由选择：

| 对比维度 | `*-qmodem-next`（现代版） | `*-qmodem`（传统版） |
| :--- | :--- | :--- |
| **前端架构** | 现代响应式 JavaScript 视图，交互流畅无闪烁 | 经典 LuCI CBI / JS 页面架构 |
| **短信生态** | 深度整合 `sms-forwarder-next` 转发应用 | 配合 `sms-tool` 与 `sms-tool_q` 原生管理 |
| **本地化** | 现代组件原生国际化设计 | 完整匹配 `luci-i18n-qmodem-zh-cn` 语言包 |
| **共用核心** | `qmodem` 核心引擎、`ubus-at-daemon`、`tom_modem`、`modem_scan` 与标准 QMI 通用驱动 | 同左 |
| **互斥策略** | 显式锁定通用 `kmod-usb-net-qmi-wwan`，剔除冗余冲突驱动，两个前端绝不并存编入 | 同左 |

> [!TIP]
> **使用建议**：若同时保留了 `luci-app-qmodem-generic` 通用管理界面，建议避免在两个界面中并发触发拨号或写入频段锁定的 AT 指令。

---

### 2. 固件在线升级机制 (`luci-app-online-upgrade`)

系统入口位于 LuCI 菜单：**系统 → 在线升级**。

- **动态设备指纹匹配**：构建时固件会将 `{机型}-{前端类型}-{构建标签}` 烙印至设备 `/etc/online-upgrade-device`。运行时精准命中对应 Release，杜绝型号错刷。
- **Release 语义隔离**：Release 标签使用结构化前缀命名（如 `H5000M-qmodem-next-...` 与 `H5000M-qmodem-...`），精准区分前端，避免覆盖。
- **配置无损保护**：默认启用配置保留升级（`keep_config`），写入前自动快照系统数据，并在重启后完整还原；内置 `gh.acg2.mom` 镜像源提供国内高速下载通道。

---

### 3. CPE 专属套件与射频初始化

#### 5G 模组通用交互 (`luci-app-qmodem-generic`)
基于 QModem 的 ubus 接口构建，不绑定专有模组型号：
- **运行全景**：实时监控模组固件版本、频段、信号质量（RSRP / RSRQ / SINR）、运营商、小区信息及 IMEI/IMSI。
- **数据与调试**：支持 APN 快速设置、流量会话管理、一键频段/小区锁定与在线 AT 指令调试台。

#### 硬件级智能风扇温控 (`luci-app-h5000m-fancontrol`)
- **双路温感轮询**：实时采集 CPU 核心与 5G 通信模组的工作温度。
- **阶梯 PWM 变速**：根据设定的温控曲线阶梯式调节风扇转速，在低负载静音与极端高吞吐散热之间取得平衡。

#### 网络模式无感切换 (`luci-app-h5000m-netmode`)
- **智能场景调度**：在“纯 5G 蜂窝”、“纯 WAN 有线”与“双线负载均衡 / 主备热备”之间平滑切换。
- **毫秒容灾切换**：深度联动 `mwan3` 探针实时探测连通性，主链路异常时无缝转移流量。

> [!IMPORTANT]
> **AP3000M EEPROM 自动化射频恢复流程**：
> AP3000M (MT7981B) 依赖开源 `mt76` Wi-Fi 驱动栈。由于设备出厂时 eMMC 的 `mmcblk0p2` factory 分区为空，会导致驱动因读取不到校准数据而初始化失败。
> 本仓库已在 `Config/` 与 `Scripts/Handles.sh` 中集成原厂备份的校准模板；系统首次引导时，`99-ap3000m-eeprom` 会自动从 `eth0` 获取设备物理 MAC 地址写入 factory 分区，并将 radio1 修正为 5GHz 频段，实现开箱即用。

---

## ⚙️ 默认出厂配置

首次刷入固件后的默认网络与无线参数如下（可通过工作流环境变量预设，编译时由 `Scripts/Settings.sh` 写入）：

| 配置项 | 默认参数值 | 说明 |
| :--- | :--- | :--- |
| **后台管理地址** | `192.168.10.1` | Web 管理界面 IPv4 入口 |
| **系统主机名** | `OWRT` | 本地局域网主机标识符 |
| **Wi-Fi SSID** | `OWRT` | 2.4G 与 5G 统一默认无线名称 |
| **Wi-Fi 密钥** | `12345678` | 初始无线接入密码 |
| **无线加密策略** | `WPA-PSK / WPA2-PSK Mixed Mode` | 兼顾新老终端设备接入兼容性 |
| **频宽规格** | **2.4G**: `40MHz` \| **5G**: `160MHz` | 释放 Wi-Fi 满血吞吐能力 |
| **时区与国家码** | `CST-8` (`Asia/Shanghai`) / `CN` | 保证 NTP 时钟校准与合规频段 |

---

## 🚀 自动化云编译指引

仓库全量利用 GitHub Actions 编排交付，无需本地搭建复杂的交叉编译环境。

### 工作流一览

| 编译工作流 | 触发模式 | 核心功能与职责 |
| :--- | :--- | :--- |
| **`WRT-BUILD`** | 手动 `workflow_dispatch` | 自定义按需编译。可自由选择机型、版本后缀（`-qmodem-next` 或 `-qmodem`）；支持 `TEST=true` 快速校验生成配置 |
| **`MTK-AUTO`** | 每日定时 (随 Auto-Clean) / 手动 | 自动构建并并行发布 MTK 架构设备（H5000M / AP3000M）的双版本固件 |
| **`OWRT-ALL`** | 每日定时 (随 Auto-Clean) / 手动 | 自动构建并并行发布 x86 平台的双版本固件 |
| **`Auto-Clean`** | 每日 05:00 (CST) 定时 / 手动 | 定期清理历史制品（保留最新 1 份 Release）与 30 天以上的 Runs 日志 |
| **`Cache-Clean`** | 每周定时 / 手动 | 回收 Actions 编译构建缓存，避免缓存陈旧 |

### 手动构建步骤

1. 进入 GitHub 仓库主页，点击 **`Actions`** 选项卡。
2. 在左侧列表定位到 **`WRT-BUILD`** 工作流，点击右侧 **`Run workflow`**。
3. 选择对应的配置模板（如 `H5000M-qmodem-next` 或 `H5000M-qmodem`）。
4. **测试开关说明**：
   - `TEST=true`（默认）：仅执行配置合并并导出 `.config` 检查语法，不执行实质编译。
   - `TEST=false`：执行全量编译并打包上传，自动在 Release 页面生成固件产物。

---

## 🛠️ 底层系统能力与扩展

得益于 ImmortalWrt 成熟的软件架构，固件在路由核心性能之外拥有出色的服务承载力：

- **硬件加解密引擎加速**：底层开启 `kmod-cryptodev` 与 `kmod-tls`，大幅卸载代理分流（HomeProxy / OpenClash）与安全加密隧道的 CPU 运算负荷。
- **轻量私有 NAS 存储**：集成 NVMe 协议支持（`kmod-nvme`）、BTRFS 现代文件系统与 Samba4，轻松发挥高速固态硬盘存储性能。
- **跨地域安全组网**：内置 Tailscale、EasyTier 等 SD-WAN 组网工具，零公网 IP 实现远程穿透与内网互联。

---

## 📂 仓库目录全景

<details>
<summary><b>📁 点击展开查看项目目录结构与脚本分工</b></summary>

```text
OpenWRT-CI-H5000M/
├── .github/workflows/          # CI/CD 云端构建流水线
│   ├── WRT-CORE.yml            # 核心编译执行流水线（被上层工作流调用）
│   ├── WRT-BUILD.yml           # 手动触发入口（支持设备与前端选型）
│   ├── MTK-AUTO.yml            # MTK 架构自动化编译发版流水线
│   ├── Auto-Clean.yml          # 历史 Release 与日志清理
│   └── Cache-Clean.yml         # Actions 构建缓存回收
├── AP3000M-EEPROM/             # AP3000M 射频恢复专属资产
│   ├── mt7981_eeprom_*.bin     # 预置校准 EEPROM 二进制模板
│   └── 99-ap3000m-eeprom       # 首次启动写入 factory 分区的初始化脚本
├── Config/                     # 模块化 Kconfig 片段
│   ├── GENERAL.txt             # 全设备通用内核与基础功能包
│   ├── QMODEM-NEXT.txt         # QModem Next 前端及依赖链
│   ├── QMODEM.txt              # 传统 QModem 前端及依赖链
│   ├── H5000M-*.txt            # H5000M 机型配置定义
│   └── AP3000M-*.txt           # AP3000M 机型配置定义
├── Scripts/                    # 流水线生命周期钩子
│   ├── Packages.sh             # 第三方 Feed 扩展拉取与锁定
│   ├── Handles.sh              # EEPROM 注入、静态资源预置与依赖修复
│   ├── Settings.sh             # 默认出厂 IP、Wi-Fi 与参数注入
│   └── inject_airpi_prebuilt.py# 向风扇温控包注入预编译标记
├── index.html                  # 现代化固件发布聚合落地页
├── CHANGELOG.md                # 版本演进记录
├── LICENSE
└── README.md

```

---

## 💖 致敬与鸣谢

本固件的高效自动化编译、底层系统的稳定性以及对特定 5G 模组的良好支持，离不开开源社区开发者们的无私奉献：

* 🐧 **底包源码上游**：
* [ImmortalWrt](https://github.com/immortalwrt/immortalwrt/?utm_source=gemini)（稳定强大的主线路由源码基石）


* 👤 **编译框架与基础优化**：
* [VIKINGYFY / OpenWRT-CI](https://github.com/VIKINGYFY/OpenWRT-CI?utm_source=gemini)（稳定可靠的基础底包配置与高可扩展自动化编译框架）


* 👤 **5G CPE 核心套件**：
* [FAN789](https://github.com/FAN789?utm_source=gemini)（H5000M 核心控制插件开发者）
* [luci-app-h5000m-fancontrol](https://github.com/FAN789/luci-app-h5000m-fancontrol?utm_source=gemini)（硬件级智能风扇温控）
* [luci-app-h5000m-netmode](https://github.com/LianXia233/luci-app-h5000m-netmode?utm_source=gemini)（智能网络模式调度）


* 👤 **通用模组 Web 界面**：
* [LianXia233 / luci-app-qmodem-generic](https://github.com/LianXia233/luci-app-qmodem-generic?utm_source=gemini)（基于 QModem 的通用解耦管理界面）


* 👤 **蜂窝模组管理套件**：
* [FUjr / QModem](https://github.com/FUjr/QModem?utm_source=gemini)（功能强大的蜂窝模组管理套件与 Next 现代界面生态）
