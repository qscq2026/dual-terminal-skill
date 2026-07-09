#!/bin/bash
# ============================================================================
# 开始新一轮需求（同一个项目，不推倒重来）
#
# 用法:
#   bash scripts/next-round.sh "新一轮目标: 修复 BGM 音量控制"
#   或者用 heredoc 传多行:
#   bash scripts/next-round.sh <<'EOF'
#   新一轮目标:
#   1. ...
#   EOF
#
# 背景:
#   set-task.sh 和 reset.sh 各管各的一摊，单独用哪个都不对：
#     - 只用 set-task.sh：task.txt 换了，但 iteration.txt 还停在上一轮结束
#       时的值。如果正好等于 LIMIT，Verifier 的 while 循环条件直接为假，
#       循环体一次都不会执行——新一轮审查等于没跑。
#     - 只用 reset.sh：iteration/status 都归零了，但 task.txt 没变，新需求
#       根本没写进去，而且 reset.sh 会把两份信誉记录（violation-log.txt /
#       verifier-violation-log.txt）也清空——换一批需求不等于这个 Worker/
#       Verifier 之前的表现历史就该清零。
#
#   这个脚本 = set-task.sh（换任务，旧内容归档）+ reset.sh --keep-violation-logs
#   （归零本轮状态，但保留两份信誉记录和 checkpoint 计数）。
#
#   注意顺序：先调用 set-task.sh 再调用 reset.sh，这样任务归档时写进
#   task-history.md 的"第 N 轮结束"标记，用的是上一轮真实结束时的迭代数，
#   而不是归零之后的 0。
# ============================================================================

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

if [ "$#" -ge 1 ]; then
    bash "$SCRIPT_DIR/set-task.sh" "$@"
else
    cat | bash "$SCRIPT_DIR/set-task.sh"
fi

echo ""
bash "$SCRIPT_DIR/reset.sh" --keep-violation-logs

echo ""
echo "已进入新一轮：status=IDLE, iteration=0, no-blocker-streak=0"
echo "保留未动：violation-log.txt / verifier-violation-log.txt / checkpoint-count.txt / task-history.md"
