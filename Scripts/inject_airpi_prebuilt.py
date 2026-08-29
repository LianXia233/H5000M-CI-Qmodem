#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""给 luci-app-airpi-fancontrol 的 Makefile 注入 AIRPI_PREBUILT 标记。

注入后包 Makefile 会走预编译分支，直接用现成的 airpi-fanctl 二进制，
不再触发 rust/host（rustc + cargo + LLVM）的源码构建。

上游参考：LianXia233/luci-app-airpi3000m-fancontrol 的 .github/workflows/build.yml
"""

import sys

MARKER = 'AIRPI_PREBUILT:=1'
ANCHOR = 'include $(TOPDIR)/rules.mk'
INJECT = ANCHOR + '\n' + MARKER + '\n' + 'AIRPI_PREBUILT_BIN:=$(TOPDIR)/airpi-prebuilt/airpi-fanctl'


def main():
    path = sys.argv[1]
    with open(path, 'r', encoding='utf-8') as fh:
        src = fh.read()

    if MARKER in src:
        print('AIRPI_PREBUILT 已注入，跳过')
        return 0

    if ANCHOR not in src:
        print('错误：未找到锚点 %r' % ANCHOR, file=sys.stderr)
        return 1

    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(src.replace(ANCHOR, INJECT, 1))

    print('已注入 AIRPI_PREBUILT -> %s' % path)
    return 0


if __name__ == '__main__':
    sys.exit(main())
