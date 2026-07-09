#!/bin/bash
# ============================================================================
# 更新本轮任务目标（自动归档旧版本，避免 task.txt 变成 v1/v2/v3 混杂的沙包）
#
# 用法:
#   bash scripts/set-task.sh "本轮目标: 修复 BGM 音量控制不生效的问题"
#   或者用 heredoc 传多行内容:
#   bash scripts/set-task.sh <<'EOF'
#   本轮目标:
#   1. 修复 BGM 音量控制
#   2. ...
#   EOF
#
# 行为: task.txt 永远只保留"当前这一轮"的目标；旧内容在被覆盖前追加进
#   task-history.md（带时间戳和归档时的迭代轮次），需要查旧需求去那边翻。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
TASK_FILE="$DUAL_DIR/task.txt"
HISTORY_FILE="$DUAL_DIR/task-history.md"

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

if [ "$#" -ge 1 ]; then
    NEW_CONTENT="$*"
else
    NEW_CONTENT="$(cat)"
fi

if [ -z "$NEW_CONTENT" ]; then
    echo "ERROR: 新任务内容为空" >&2
    exit 1
fi

TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
ROUND="$(cat "$DUAL_DIR/iteration.txt" 2>/dev/null || echo 0)"

if [ -s "$TASK_FILE" ]; then
    {
        echo ""
        echo "---"
        echo ""
        echo "## [归档于第 ${ROUND} 轮结束 / ${TS}]"
        echo ""
        cat "$TASK_FILE"
    } >> "$HISTORY_FILE"
fi

tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"
printf '%s\n' "$NEW_CONTENT" > "$tmp"
mv "$tmp" "$TASK_FILE"

echo "task.txt 已更新，旧内容已归档到 task-history.md"
