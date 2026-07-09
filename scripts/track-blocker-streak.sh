#!/bin/bash
# ============================================================================
# 追踪"连续无新增 [阻塞] 问题"轮数
#
# 用法: bash scripts/track-blocker-streak.sh <yes|no>
#   yes = 本轮发现了新的 [阻塞] 级问题 -> 计数清零
#   no  = 本轮没有发现新的 [阻塞] 级问题 -> 计数 +1
#
# 输出: 新的计数值（stdout）
#
# 背景: "循环不要停止直至满意"没有客观标准时，审查标准会逐轮膨胀——
#   产品早就完成了，还在为 0.05 个格子的坐标偏移继续打回。这个计数器给
#   Verifier 一个具体数字去参照："连续两轮没有新阻塞问题了，该收敛了"，
#   而不是单凭当下的感觉判断"要不要再挑一轮"。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
FILE="$DUAL_DIR/no-blocker-streak.txt"
ARG="${1:-}"

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

case "$ARG" in
    yes)
        NEW=0
        ;;
    no)
        CUR=$(cat "$FILE" 2>/dev/null || echo 0)
        case "$CUR" in ''|*[!0-9]*) CUR=0 ;; esac
        NEW=$((CUR + 1))
        ;;
    *)
        echo "ERROR: 用法: bash scripts/track-blocker-streak.sh <yes|no>（本轮是否发现了新的[阻塞]问题）" >&2
        exit 1
        ;;
esac

tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"
echo "$NEW" > "$tmp"
mv "$tmp" "$FILE"

echo "$NEW"
