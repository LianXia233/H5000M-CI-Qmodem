#!/usr/bin/env python3
"""把上游 init_build_environment.sh 适配到 Ubuntu 26.04 (resolute)。

背景：上游 check_system() 用 case "$VERSION_CODENAME" 做白名单，只识别到
noble(24.04)；26.04 的 resolute 会命中 *) 并打印
"[ERROR] Unsupported OS, use Ubuntu 20.04 instead." 后 exit 1，
导致所有编译作业停在初始化阶段。

为什么不是简单地把 resolute 加进白名单：update_apt_source() 会用
$VERSION_CODENAME 拼出 apt.llvm.org/<codename>/ 等第三方源，而这些 PPA
目前只提供 noble 分支；直接放行 resolute 会让随后的 apt update 失败。
因此把脚本内的代号映射为 noble，完整复用上游已验证的
GCC 13 / LLVM 23 / noble PPA 参数集。主 apt 源仍由 runner 的 26.04
原生配置提供（脚本只在 CHN_NET 非空即境内网络时才重写 sources.list）。

补丁幂等；上游原生支持 26.04 后自动跳过。上游改写法导致无法定位时
直接失败，避免静默跑出一个未打补丁的脚本。
"""

import pathlib
import re
import subprocess
import sys

PATH = pathlib.Path("/tmp/init_build_environment.sh")
MARKER = "[CI] Ubuntu 26.04 compatibility"
ASSIGN = 'VERSION_CODENAME="$(source /etc/os-release; echo "$VERSION_CODENAME")"'

if not PATH.is_file():
    print("::error::init_build_environment.sh not found", file=sys.stderr)
    sys.exit(1)

text = PATH.read_text(encoding="utf-8")

if MARKER in text:
    print("patch-init-env: already applied")
    sys.exit(0)

# 上游已原生支持 26.04 时让位，避免长期遮蔽上游的新分支。
if re.search(r'^\s*"resolute"\s*\)', text, re.M):
    print("patch-init-env: upstream already supports resolute, skip")
    sys.exit(0)

pattern = re.compile(
    r'^[ \t]*VERSION_CODENAME="\$\(source /etc/os-release; echo "\$VERSION_CODENAME"\)"[ \t]*$',
    re.M,
)
match = pattern.search(text)
if not match:
    print(
        "::error::cannot locate VERSION_CODENAME assignment; upstream script changed",
        file=sys.stderr,
    )
    sys.exit(1)

indent = re.match(r"^[ \t]*", match.group(0)).group(0)
lines = [
    ASSIGN,
    "# " + MARKER,
    "# 上游 check_system() 的代号白名单只到 noble；26.04 (resolute) 会命中 *) 并 exit 1。",
    "# apt.llvm.org / Launchpad PPA 目前也只有 noble 分支，直接放行 resolute 会写出",
    "# 不存在的第三方源并让 apt update 失败，故把脚本内代号映射为 noble。",
    "# 主 apt 源仍由 runner 的 26.04 原生配置提供（脚本只在境内网络下重写 sources）。",
    'case "$VERSION_CODENAME" in',
    '  resolute|resolute-updates)',
    '    VERSION_CODENAME="noble"',
    "    ;;",
    "esac",
]
inject = "\n".join(indent + line for line in lines) + "\n"
PATH.write_text(text[: match.start()] + inject + text[match.end() :], encoding="utf-8")

# 语法自检：补丁写坏时在这里就失败，而不是等到 apt 阶段才暴露。
result = subprocess.run(["bash", "-n", str(PATH)], capture_output=True, text=True)
if result.returncode != 0:
    print("::error::patched script fails bash -n: " + result.stderr.strip(), file=sys.stderr)
    sys.exit(1)

print("patch-init-env: mapped Ubuntu 26.04 (resolute) -> noble toolchain profile")
