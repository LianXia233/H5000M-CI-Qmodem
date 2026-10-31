<div align="center">

# 🚀 H5000M & AP3000M & X86_64 · ImmortalWrt 定制固件

**基于 ImmortalWrt 主线源码 · 专为 5G CPE、Wi-Fi 路由器与软路由量身打造的自动化云编译生态**

[![ImmortalWrt Master](https://img.shields.io/badge/ImmortalWrt-master%20(Mainline)-brightgreen?logo=openwrt&logoColor=white&style=flat-square)](https://github.com/immortalwrt/immortalwrt)
[![MediaTek Filogic](https://img.shields.io/badge/Platform-MediaTek%20Filogic-FF6B35?style=flat-square)](#-一-硬件支持与固件矩阵)
[![x86_64](https://img.shields.io/badge/Platform-x86__64-informational?style=flat-square)](#-一-硬件支持与固件矩阵)
[![Cellular QModem](https://img.shields.io/badge/Modem-QModem%20%7C%20Modem%20Pro-8b5cf6?style=flat-square)](#-二-模组方案对比与选型)
[![CI Build](https://img.shields.io/github/actions/workflow/status/LianXia233/H5000M-CI-Qmodem/WRT-BUILD.yml?branch=main&label=CI%20Build&style=flat-square&logo=githubactions&logoColor=white)](https://github.com/LianXia233/H5000M-CI-Qmodem/actions)
[![License](https://img.shields.io/badge/License-GPL--3.0-blue?style=flat-square&logo=gnu&logoColor=white)](LICENSE)

<p align="center">
  <b>全面支持 Hiveton H5000M（MT7987A + MT7996E + MT5700M）、AirPi AP3000M（MT7981B）与通用 X86_64 设备</b><br>
  集成 QModem Next 现代化前端、经典 QModem 与 Modem Pro 统一模组方案，提供一键在线无损 OTA 升级
</p>

</div>

---

## 🌟 核心特性亮点

- ⚡ **纯正官方主线与定制分支融合**：QModem 全系配置直接对接 [immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt) 官方 `master` 主线分支；Modem Pro 方案则基于成熟稳定的 [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt) `owrt` 分支构建。
- 📶 **QModem 双前端架构**：
  - **`*-qmodem-next`（现代版）**：采用全响应式 JavaScript 现代前端，集成 `sms-forwarder-next` 短信转发中心，交互丝滑。
  - **`*-qmodem`（传统版）**：经典 LuCI 架构与深度汉化界面，配合 `sms-tool` 原生命令行工具，稳定高效。
- 🛰️ **Modem Pro 统一模组方案（H5000M / AP3000M 专享）**：提供 `H5000M-modem-pro` 与 `AP3000M-modem-pro` 独立配置，引入 [modem-pro-unified](https://github.com/LianXia233/modem-pro-unified) 栈——由 Rust 守护进程 `modemd` 原生接管 QMI/MBIM 拨号，搭配 ucode 世代 LuCI 界面，彻底剥离 QModem 冗余组件。
- 🔄 **硬件级在线 OTA 升级 (`luci-app-online-upgrade`)**：固件内置设备特征唯一锚点，自动识别并匹配对应 Release，支持保留配置无缝一键直升，内置国内加速镜像。
- 🛠️ **AP3000M 射频自动注入**：采用开源 `mt76` 驱动栈，首次启动自动灌装 EEPROM 校准数据并绑定物理 MAC，彻底根治出厂 factory 分区丢失导致无 Wi-Fi 的难题。
- ❄️ **CPE 专属硬件控制套件**：集成 CPU + 基带双温区风扇 PWM 阶梯调速、网络模式秒级切换与双链路故障倒换。

---

## 🎯 一、 硬件支持与固件矩阵

| 目标机型 | 平台架构 / 核心 SoC | 硬件形态与特性 | Wi-Fi 驱动栈 | 源码基线与分支 |
| :--- | :--- | :--- | :---: | :--- |
| **`H5000M`** | MediaTek Filogic (MT7987A + MT7996E) | Hiveton H5000M 5G CPE（鼎桥 MT5700M） | ✅ Wi-Fi 7 (BE) | QModem: `immortalwrt` (`master`)<br>Modem Pro: `VIKINGYFY` (`owrt`) |
| **`AP3000M`** | MediaTek Filogic (MT7981B + MT7976C) | AirPi AP3000M Wi-Fi 6 路由器 | ✅ Wi-Fi 6 (AX · mt76) | QModem: `immortalwrt` (`master`)<br>Modem Pro: `VIKINGYFY` (`owrt`) |
| **`X86`** | x86_64 通用架构 | 工控机 / 软路由 / 物理 PC / 虚拟机 | — | `immortalwrt/immortalwrt` (`master`) |

---

## ⚙️ 默认出厂网络配置

系统出厂参数由 [`Config/OWRT-DEFAULT.txt`](./Config/OWRT-DEFAULT.txt) 声明管理，可在编译时直接读取注入：

| 配置项 | 默认出厂值 | 说明 |
| :--- | :--- | :--- |
| **后台管理地址** | `192.168.10.1` | Web 管理页面 IPv4 入口 |
| **管理登录账号/密码** | `root` / **空（无密码）** | 首次进入后建议设置强密码 |
| **系统主机名** | `OWRT` | 本地局域网主机标识符 |
| **默认 Wi-Fi SSID** | `OWRT` | 2.4G 与 5G 双频合一名称 |
| **默认 Wi-Fi 密钥** | `12345678` | WPA/WPA2 混合加密 |
| **频宽规格（WiFi 6 · AP3000M）** | 2.4G `40MHz` · 5G `160MHz` | 802.11ax（HE），双频并发无线高吞吐 |
| **频宽规格（WiFi 7 · H5000M）** | 2.4G `40MHz` · 5G `160MHz` | 802.11be（EHT），双频设备 5G 上限 160MHz |
| **时区与国家代码** | `CST-8` (`Asia/Shanghai`) / `CN` | 保证时钟对齐与合规无线信道 |

---

## 🧩 二、 模组方案对比与选型

针对不同用户的操作习惯与架构偏好，项目提供三套并列互斥的固件变体：

### 1. QModem 方案对比 (`*-qmodem-next` vs `*-qmodem`)

| 评估维度 | `*-qmodem-next`（现代版） | `*-qmodem`（传统版） |
| :--- | :--- | :--- |
| **前端架构** | 响应式现代化 JavaScript 组件，UI 流畅无重载刷新 | 经典 LuCI CBI / JS 表单页面 |
| **短消息生态** | 深度整合 `sms-forwarder-next` 现代转发中心 | 配合 `sms-tool` 与 `sms-tool_q` 基础管理 |
| **本地化方案** | 现代化模块原生国际化设计 | 完整匹配 `luci-i18n-qmodem-zh-cn` 语言包 |
| **共用核心** | 统一搭载 `qmodem` 核心引擎、`ubus-at-daemon` 与通用 QMI 驱动栈 | 同左 |
| **隔离策略** | 锁定 `kmod-usb-net-qmi-wwan`，两套前端在固件中绝不交叉混编 | 同左 |

### 2. Modem Pro 统一模组方案 (`*-modem-pro`，MTK 机型专享)

`H5000M-modem-pro` 与 `AP3000M-modem-pro` 是独立演进的第三套方案，完全剥离 QModem：

| 评估维度 | `*-modem-pro` 方案特征 |
| :--- | :--- |
| **支持机型** | `H5000M-modem-pro`（MT7987A）与 `AP3000M-modem-pro`（MT7981B） |
| **源码分支** | 基于 `VIKINGYFY/immortalwrt` 的 `owrt` 稳定分支构建 |
| **拨号与管控栈** | [modem-pro-unified](https://github.com/LianXia233/modem-pro-unified) 统一栈，单一顶层包 `modem-pro` |
| **后端引擎** | **Rust 守护进程 `modemd`**，原生处理 QMI / MBIM 协议拨号，经 netifd 协议纳管 |
| **前端交互** | ucode / JS 现代 LuCI 前端（菜单：**移动网络 → 5G 终端**），由 `modemd` 提供高性能 ubus 接口 |
| **与 QModem 关系** | **彻底剔除 QModem**：Next 前端、传统前端、通用界面与 `qmodem` 底层全数移除，零代码冗余 |
| **编译机制** | 宿主 rustup 直编（`MODEM_PRO_HOST_RUST=1`），跳过 feeds 源码编译 rust/host，秒级构建 |

> [!WARNING]
> **AP3000M 固件互刷注意（网口映射相反）**：
> `AP3000M-qmodem-next` / `AP3000M-qmodem`（基于官方 `master`）与 `AP3000M-modem-pro`（基于 `VIKINGYFY/owrt`）两套源码对 AP3000M 的 **LAN / WAN 网口映射是相反的**！在两类固件之间互刷后，若发现无法上网或无法打开后台，只需将原 LAN 口的网线换插到 WAN 口（或反之）即可，系统内部配置无需修改。

---

## 🛠️ 三、 核心专属套件详解

### 1. 固件在线 OTA 升级 (`luci-app-online-upgrade`)
进入 LuCI 菜单：**系统 → 在线升级**：
- **设备指纹精准防呆**：构建期在固件烙印 `{机型}-{前端方案}` 唯一特征（`/etc/online-upgrade-device`），精准定位对应 Release，杜绝错刷；
- **配置无损还原**：默认开启 `keep_config`，刷写前自动备份系统关键配置并在重启后全量恢复；
- **极速下载通道**：内置反向代理下载加速镜像，解决国内 GitHub 下载缓慢问题。

### 2. 硬件风扇温控与多网切换
- **双温区联动风扇控制 (`luci-app-h5000m-fancontrol`)**：定时轮询 CPU 与模组硬件传感器，通过阶梯 PWM 曲线实现静音与强效散热平衡；
- **多网络智能切换 (`luci-app-h5000m-netmode`)**：支持“纯 5G”、“纯 WAN 有线”及“主备热备 / 负载均衡”三档模式，配合 `mwan3` 探针实现毫秒级容灾切流；
- **AP3000M EEPROM 自动化射频恢复**：开机自启服务 `99-ap3000m-eeprom` 自动提取物理 MAC 并写入 factory 分区，激活 Wi-Fi 6 射频。

---

## 🚀 四、 自动化云编译指南

依托 GitHub Actions 提供全套自动化矩阵编排，无需本地交叉编译环境：

### 工作流矩阵一览

| 工作流文件 | 调度策略 | 核心职责 |
| :--- | :--- | :--- |
| **`WRT-BUILD.yml`** | 手动 `workflow_dispatch` | 自定义按需编译：自选机型与方案（`-qmodem-next` / `-qmodem` / `-modem-pro`），支持 `TEST=true` 快速语法校验 |
| **`MTK-AUTO.yml`** | 每日定时 / 联动触发 | 自动构建并并行发布 MTK 机型（H5000M / AP3000M）的全部三版本固件 |
| **`OWRT-ALL.yml`** | 每日定时 / 联动触发 | 自动构建并并行发布 X86 平台的双版本固件 |
| **`Auto-Clean.yml`** | 每日定时 05:00 (CST) | 轮换保留最新一份 Release，自动清理过期 Tag 与 30 天以前的 Actions 日志 |
| **`Cache-Clean.yml`** | 每周定时 / 手动 | 回收 Actions 编译缓存，避免依赖冲突 |

### 手动构建步骤指引

1. 登录 GitHub，进入仓库 **Actions** 页面；
2. 在左侧工作流列表选择 **`WRT-BUILD`**，点击右侧 **`Run workflow`**；
3. 选择目标机型配置（例如 `H5000M-qmodem-next`、`H5000M-qmodem` 或 `H5000M-modem-pro`）；
4. 源码仓库由流水线自动识别绑定，无需手动输入；
5. 如需输出正式固件，将 **`TEST`** 参数改为 **`false`** 即可。

---

## 📂 仓库项目结构

```text
H5000M-CI-Qmodem/
├── .github/workflows/          # GitHub Actions 云编译流水线
│   ├── WRT-CORE.yml            # 核心编译执行引擎
│   ├── WRT-BUILD.yml           # 手动触发定制编译
│   ├── MTK-AUTO.yml            # MTK 架构定时自动发版
│   ├── OWRT-ALL.yml            # X86 架构定时自动发版
│   ├── Auto-Clean.yml          # 历史制品与日志轮换清理
│   └── Cache-Clean.yml         # 构建缓存回收
├── AP3000M-EEPROM/             # AP3000M 射频恢复专属资产与脚本
├── Config/                     # 模块化 Kconfig 配置文件片段
│   ├── OWRT-DEFAULT.txt        # 集中化出厂默认网络与无线参数
│   ├── GENERAL.txt             # 通用内核优化与基础插件
│   ├── QMODEM-NEXT.txt         # QModem Next 现代化前端依赖
│   ├── QMODEM.txt              # 传统 QModem 前端依赖
│   ├── MODEM-PRO.txt           # Modem Pro 统一方案依赖（禁用 QModem）
│   ├── H5000M-*.txt            # H5000M 各方案目标配置
│   ├── AP3000M-*.txt           # AP3000M 各方案目标配置
│   └── X86-*.txt               # X86 各方案目标配置
├── Scripts/                    # 流水线生命周期钩子脚本
│   ├── Packages.sh             # 第三方 Feed 扩展源同步与锁定
│   ├── Handles.sh              # 补丁修补、静态资源预置与依赖注入
│   ├── Settings.sh             # 出厂默认 IP、Wi-Fi 与参数配置
│   └── online-upgrade/         # 在线升级专属支持脚本
├── index.html                  # 现代化固件发布聚合展示落地页
└── README.md                   # 固件说明文档
```

---

## 💖 致敬与鸣谢

* 🐧 **底包源码**：[immortalwrt/immortalwrt](https://github.com/immortalwrt/immortalwrt)（主线路由基石）· [VIKINGYFY/immortalwrt](https://github.com/VIKINGYFY/immortalwrt)（板级专属适配源码）
* 👤 **编译框架**：[VIKINGYFY/OpenWRT-CI](https://github.com/VIKINGYFY/OpenWRT-CI)（优秀的开源自动化云编译框架）
* 👤 **蜂窝模组与 CPE 套件**：
  - [FUjr/QModem](https://github.com/FUjr/QModem)（强大的蜂窝模组管理套件与 Next 前端生态）
  - [FAN789](https://github.com/FAN789)（H5000M 硬件风扇温控与网络模式切换套件原作者）
  - [LianXia233](https://github.com/LianXia233)（[modem-pro-unified](https://github.com/LianXia233/modem-pro-unified) 统一模组管理方案、通用解耦管理界面与在线 OTA 升级套件）

---

> 📜 **许可协议**：本项目基于 [GNU General Public License v3.0 (GPL-3.0)](LICENSE) 协议发布。
