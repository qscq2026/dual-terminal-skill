#!/bin/bash
# ============================================================================
# 迭代计数原子递增脚本（仅 Verifier 使用）
#
# 用法: bash scripts/bump-iteration.sh
# 行为: 读取 .dual-claude/iteration.txt 当前值，+1，原子写回，并把新值打印
#       到 stdout，供调用方（Verifier）判断是否已达到本轮设定的 LIMIT。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
ITER_FILE="$DUAL_DIR/iteration.txt"

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

CURRENT=$(cat "$ITER_FILE" 2>/dev/null || echo 0)
case "$CURRENT" in ''|*[!0-9]*) CURRENT=0 ;; esac

NEW=$((CURRENT + 1))

tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"
echo "$NEW" > "$tmp"
mv "$tmp" "$ITER_FILE"

echo "$NEW"
