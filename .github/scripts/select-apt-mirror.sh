#!/usr/bin/env bash
# 选择 apt 镜像：以「可持续吞吐」为准，而不是 8 MB Range 的瞬时峰值。
#
# 背景：2026-11-10 的 OWRT-ALL 运行（job 129601853332）里，azure.archive
# 的 Range 探测报出 383 MB/s，原逻辑据此「保持默认」，但真实 bulk .deb
# 只有几十~一百 kB/s，texlive-lang-greek(79.2MB)、mupdf-tools(49.3MB)
# 两个包各卡了 8 分钟以上，Initialization Environment 两次 20 分钟超时。
#
# 为什么单点 speed_download 不可信：Range 请求若命中 CDN 边缘缓存，
# 8 MB 在几十毫秒内返回，算出的「吞吐」是缓存带宽，而不是回源带宽。
# 这里用三重约束把它挡掉：
#   1. 同一文件取两个不相邻分片（0-4 MB、4-8 MB），取较小值；
#      只有两段都持续高速，才认为该镜像真的快。
#   2. 叠加 --speed-limit：持续速率跌破 300 kB/s 并维持 8 秒即中止，
#      退化链路不会靠首包突发蒙混过关。
#   3. 结果超过 30 MB/s 一律判为缓存假象，按 0 计（runner 到 Ubuntu
#      官方源的真实 bulk 吞吐不会到这个量级）。
set -uo pipefail

CODENAME="$(
  . /etc/os-release 2>/dev/null || true
  printf '%s' "${VERSION_CODENAME:-resolute}"
)"
IDX="dists/${CODENAME}/universe/binary-amd64/Packages.xz"

# runner 位于海外机房，官方源优先，另补中立镜像兜底。
CANDIDATES=(
  "https://archive.ubuntu.com/ubuntu/"
  "http://azure.archive.ubuntu.com/ubuntu/"
  "https://security.ubuntu.com/ubuntu/"
  "https://mirrors.edge.kernel.org/ubuntu/"
)

# 单个 Range 分片的吞吐（字节/秒）。失败、非 2xx 或非数字一律 0。
# curl 默认不把 4xx/5xx 当失败，404/503 的错误页同样能被"飞速"传完，
# 若只看 speed_download，一个掉队或出错的镜像会被排成最快，
# 然后写进全部 apt 源，紧接着的 apt update 直接失败。
fetch_speed() {
  local url="$1" range="$2" out code sp
  out=$(curl -sSL -r "$range" -o /dev/null \
        --connect-timeout 8 --max-time 15 \
        --speed-limit 300000 --speed-time 8 \
        -w '%{http_code} %{speed_download}' "${url}${IDX}" 2>/dev/null) || true
  code="${out%% *}"
  sp="${out##* }"
  sp="${sp%%.*}"
  case "$code" in
    200|206) ;;
    *) sp=0 ;;
  esac
  case "$sp" in ''|*[!0-9]*) sp=0 ;; esac
  printf '%s' "$sp"
}

# 取两段中的较小值：缓存命中通常只覆盖被请求的那一段，
# 换一段再测就能暴露真实回源速度。
probe() {
  local url="$1" a b
  a=$(fetch_speed "$url" "0-4194303")
  b=$(fetch_speed "$url" "4194304-8388607")
  if [ "$a" -lt "$b" ]; then printf '%s' "$a"; else printf '%s' "$b"; fi
}

CACHE_ARTIFACT=$((30 * 1024 * 1024))
BEST_URL=""
BEST_SPEED=0
for u in "${CANDIDATES[@]}"; do
  s=$(probe "$u")
  if [ "$s" -gt "$CACHE_ARTIFACT" ]; then
    echo "apt throughput ${u} => ${s} B/s (suspicious, treated as cache artifact)"
    s=0
  else
    echo "apt throughput ${u} => ${s} B/s"
  fi
  if [ "$s" -gt "$BEST_SPEED" ]; then
    BEST_SPEED="$s"
    BEST_URL="$u"
  fi
done

# 下限取 512 kB/s：661 MB 依赖在该速率下约需 21 分钟，仍可完成。
# 全部候选都不达标时退回「官方 archive 优先、azure 兜底」的固定顺序，
# 而不是维持上一轮选中的那条（很可能就是刚超时的那条）。
FLOOR=524288
if [ -z "$BEST_URL" ] || [ "$BEST_SPEED" -lt "$FLOOR" ]; then
  echo "no mirror above ${FLOOR} B/s; falling back to archive.ubuntu.com with azure as backup"
  BEST_URL="https://archive.ubuntu.com/ubuntu/"
  BEST_SPEED=0
fi

echo "selected apt mirror: ${BEST_URL} (${BEST_SPEED} B/s)"

{
  printf '%s\t%s\n' "$BEST_URL" 'priority:1'
  for u in "${CANDIDATES[@]}"; do
    [ "$u" = "$BEST_URL" ] && continue
    printf '%s\t%s\n' "$u" 'priority:9'
  done
} | sudo tee /etc/apt/apt-mirrors.txt >/dev/null

# apt-mirrors.txt 只覆盖走 mirrorlist 的条目，sources 里硬编码的 URI 一并替换。
BASE="${BEST_URL%/}"
for f in /etc/apt/sources.list \
         /etc/apt/sources.list.d/*.sources \
         /etc/apt/sources.list.d/*.list; do
  [ -f "$f" ] || continue
  sudo sed -i -E \
    "s#https?://(azure\.)?archive\.ubuntu\.com/ubuntu/?#${BASE}#g; s#https?://security\.ubuntu\.com/ubuntu/?#${BASE}#g" \
    "$f" || true
done
