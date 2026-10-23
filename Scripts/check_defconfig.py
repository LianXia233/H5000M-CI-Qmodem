#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY
"""defconfig 硬断言：阻止 QModem / 前端 / 驱动 / 设备配置被静默丢弃。

用法（CI 与本地均可）：
    python3 Scripts/check_defconfig.py \
        --config wrt/.config \
        --requested wrt/.config.requested \
        --variant qmodem-next \
        --name H5000M-qmodem-next

检查内容：
1. 合并后、defconfig 前的每个 CONFIG_*=y 必须在 defconfig 后仍为 y；
2. QModem 变体：核心、通用 QMI 驱动、SEAL、短信栈、通用界面必须存在，
   且不得混入厂商 QMI 驱动；
3. 传统 / Next 前端互斥，Next 的 qmodem-smsd / sms-forwarder-next 必须存在；
4. Modem Pro：modem-pro 必须存在，且不得出现任何 QModem 组件；
5. 按机型校验设备符号与专有插件。
"""

import argparse
import re
import sys

SYMBOL_RE = re.compile(r"^(CONFIG_\S+?)=(.*)$")
UNSET_RE = re.compile(r"^# (CONFIG_\S+) is not set$")


def parse_config(path):
    values = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            match = SYMBOL_RE.match(line)
            if match:
                values[match.group(1)] = match.group(2)
                continue
            match = UNSET_RE.match(line)
            if match:
                values[match.group(1)] = "n"
    return values


class Checker:
    def __init__(self, name, variant, actual, requested):
        self.name = name
        self.variant = variant
        self.actual = actual
        self.requested = requested
        self.errors = []

    def require(self, symbol, reason):
        value = self.actual.get(symbol)
        if value != "y":
            self.errors.append(
                f"{symbol} 应为 y，实际为 {value or '<缺失>'}（{reason}）"
            )

    def forbid(self, symbol, reason):
        value = self.actual.get(symbol)
        if value == "y":
            self.errors.append(f"{symbol} 不应编入固件，实际为 y（{reason}）")

    def check_requested(self):
        dropped = []
        for symbol, value in self.requested.items():
            if value != "y":
                continue
            if self.actual.get(symbol) != "y":
                dropped.append(
                    f"{symbol}: 请求 y -> 实际 {self.actual.get(symbol, '<缺失>')}"
                )
        for line in sorted(dropped):
            self.errors.append(f"配置被 defconfig 静默丢弃：{line}")

    def check_variant(self):
        if self.variant == "modem-pro":
            self.require("CONFIG_PACKAGE_modem-pro", "Modem Pro 唯一模组管理包")
            self.require("CONFIG_MODEM_PRO_HOST_RUST", "宿主 rustup 直编开关")
            self.require("CONFIG_PACKAGE_input-support", "USB 串口 / HID 特性门控")
            self.require("CONFIG_PACKAGE_audio-support", "音频设备特性门控")
            self.require("CONFIG_PACKAGE_kmod-usb-net-qmi-wwan", "Modem Pro QMI 拨号")

            qmodem_symbols = [
                "CONFIG_PACKAGE_qmodem",
                "CONFIG_PACKAGE_luci-app-qmodem",
                "CONFIG_PACKAGE_luci-app-qmodem-next",
                "CONFIG_PACKAGE_luci-app-qmodem-generic",
                "CONFIG_PACKAGE_luci-i18n-qmodem-zh-cn",
                "CONFIG_PACKAGE_sms-forwarder-next",
                "CONFIG_PACKAGE_qmodem-smsd",
                "CONFIG_PACKAGE_qmodem-sipd",
                "CONFIG_PACKAGE_ubus-at-daemon",
                "CONFIG_PACKAGE_sms-tool",
                "CONFIG_PACKAGE_sms-tool_q",
                "CONFIG_PACKAGE_quectel-CM-5G-M",
            ]
            for symbol in qmodem_symbols:
                self.forbid(symbol, "Modem Pro 必须与 QModem 生态隔离")
            return

        common = [
            ("CONFIG_PACKAGE_qmodem", "QModem 核心包"),
            ("CONFIG_PACKAGE_qmodem_INCLUDE_generic-qmi-wwan", "必须选择通用 QMI 驱动"),
            ("CONFIG_PACKAGE_qmodem_INCLUDE_SEAL", "上游默认启用 SEAL，显式固定"),
            ("CONFIG_PACKAGE_qmodem_USE_TOM_CUSTOMIZED_QUECTEL_CM", "拨号 CM 选择"),
            ("CONFIG_PACKAGE_kmod-usb-net-qmi-wwan", "通用 QMI WWAN 驱动"),
            ("CONFIG_PACKAGE_kmod-usb-acm", "QModem 硬依赖"),
            ("CONFIG_PACKAGE_kmod-usb-serial-qualcomm", "QModem 硬依赖"),
            ("CONFIG_PACKAGE_kmod-usb-serial-option", "模组 AT 串口"),
            ("CONFIG_PACKAGE_input-support", "input/HID 特性门控"),
            ("CONFIG_PACKAGE_audio-support", "音频类特性门控（kmod-sound-core/usb-audio 依赖）"),
            ("CONFIG_PACKAGE_ubus-at-daemon", "QModem AT ubus 守护进程"),
            ("CONFIG_PACKAGE_sms-tool", "短信工具"),
            ("CONFIG_PACKAGE_sms-tool_q", "QModem 短信工具"),
            ("CONFIG_PACKAGE_quectel-CM-5G-M", "Tom 定制 Quectel CM"),
            ("CONFIG_PACKAGE_luci-app-qmodem-generic", "通用 QModem 管理界面"),
        ]
        for symbol, reason in common:
            self.require(symbol, reason)

        # 厂商 QMI 驱动与通用驱动提供同名 qmi_wwan.ko，不能同时进固件
        for symbol in (
            "CONFIG_PACKAGE_kmod-qmi_wwan_q",
            "CONFIG_PACKAGE_kmod-qmi_wwan_f",
            "CONFIG_PACKAGE_kmod-qmi_wwan_s",
        ):
            self.forbid(symbol, "已选择通用 QMI，厂商驱动会造成同名模块冲突")

        if self.variant == "qmodem":
            self.require("CONFIG_PACKAGE_luci-app-qmodem", "传统 LuCI 前端")
            self.require("CONFIG_PACKAGE_luci-i18n-qmodem-zh-cn", "传统前端中文翻译")
            self.forbid("CONFIG_PACKAGE_luci-app-qmodem-next", "传统 / Next 前端互斥")
            self.forbid("CONFIG_PACKAGE_sms-forwarder-next", "仅 Next 变体使用")
            self.forbid("CONFIG_PACKAGE_qmodem-smsd", "仅 Next 变体使用")
            self.forbid("CONFIG_PACKAGE_qmodem-sipd", "Next 的 VoIP 组件，未启用")
        else:
            self.require("CONFIG_PACKAGE_luci-app-qmodem-next", "Next LuCI 前端")
            self.require("CONFIG_PACKAGE_qmodem-smsd", "Next 短信守护进程")
            self.require("CONFIG_PACKAGE_sms-forwarder-next", "Next 短信转发")
            self.forbid("CONFIG_PACKAGE_luci-app-qmodem", "传统 / Next 前端互斥")
            self.forbid("CONFIG_PACKAGE_luci-i18n-qmodem-zh-cn", "传统前端翻译不应编入 Next")
            self.forbid("CONFIG_PACKAGE_qmodem-sipd", "qmodem-sipd 仅为 RECOMMENDS")

    def check_device(self):
        self.require("CONFIG_TARGET_MULTI_PROFILE", "按设备选择 profile 所必需")

        if self.name.startswith("H5000M-"):
            self.require(
                "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_hiveton_h5000m",
                "H5000M 设备 profile",
            )
            self.require("CONFIG_PACKAGE_kmod-cryptodev", "H5000M 内核调整")
            self.require("CONFIG_PACKAGE_kmod-tls", "H5000M 内核调整")
            self.require("CONFIG_PACKAGE_luci-app-h5000m-fancontrol", "H5000M 风扇控制")
            self.require("CONFIG_PACKAGE_luci-app-h5000m-netmode", "H5000M 网络模式")
        elif self.name.startswith("AP3000M-"):
            self.require(
                "CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_airpi_ap3000m",
                "AP3000M 设备 profile",
            )
            self.require("CONFIG_PACKAGE_kmod-cryptodev", "AP3000M 内核调整")
            self.require("CONFIG_PACKAGE_kmod-tls", "AP3000M 内核调整")
            self.require("CONFIG_PACKAGE_kmod-mt7915e", "AP3000M WiFi 驱动")
            self.require("CONFIG_PACKAGE_kmod-mt7981-firmware", "AP3000M WiFi 固件")
            self.require("CONFIG_PACKAGE_luci-app-airpi-fancontrol", "AP3000M 风扇控制")
            self.require("CONFIG_PACKAGE_kmod-airpi-gpio-fan", "AP3000M 风扇内核模块")
            self.require("CONFIG_PACKAGE_kmod-hwmon-pwmfan", "AP3000M PWM 风扇")
        elif self.name.startswith("X86-"):
            self.require("CONFIG_TARGET_DEVICE_x86_64_DEVICE_generic", "x86_64 generic profile")
            self.require("CONFIG_GRUB_EFI_IMAGES", "x86 EFI 引导镜像")
            self.require("CONFIG_ISO_IMAGES", "x86 ISO 镜像")
            self.require("CONFIG_PACKAGE_kmod-mt76x2", "MT76 PCIe 无线驱动")
            self.require("CONFIG_PACKAGE_kmod-rtw88-8821ce", "RTL8821CE PCIe 无线驱动")
            self.require("CONFIG_PACKAGE_kmod-rtw88-8822ce", "RTL8822CE PCIe 无线驱动")
            self.require("CONFIG_PACKAGE_kmod-usb-xhci-hcd", "x86 USB3 xHCI 主机控制器")

    def run(self):
        self.check_requested()
        self.check_variant()
        self.check_device()
        return self.errors


def main():
    parser = argparse.ArgumentParser(description="Validate defconfig result for this repository")
    parser.add_argument("--config", required=True, help="defconfig 之后的 .config")
    parser.add_argument("--requested", required=True, help="defconfig 之前合并出的 .config")
    parser.add_argument("--variant", required=True, choices=["qmodem", "qmodem-next", "modem-pro"])
    parser.add_argument("--name", required=True, help="配置名，如 H5000M-qmodem-next")
    args = parser.parse_args()

    actual = parse_config(args.config)
    requested = parse_config(args.requested)

    print(
        f"config={args.name} variant={args.variant} "
        f"requested={sum(1 for v in requested.values() if v == 'y')} y-symbols, "
        f"actual={sum(1 for v in actual.values() if v == 'y')} y-symbols"
    )

    errors = Checker(args.name, args.variant, actual, requested).run()
    if errors:
        for message in errors:
            print(f"::error title=Config assertion failed::{args.name}: {message}")
        print(f"FAILED: {len(errors)} assertion(s) for {args.name}")
        return 1

    print(f"OK: all config assertions passed for {args.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
