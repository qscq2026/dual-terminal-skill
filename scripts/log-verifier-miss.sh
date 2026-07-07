#!/bin/bash
# ============================================================================
# 记录 Verifier 漏判脚本
#
# 用法: bash scripts/log-verifier-miss.sh "<具体描述>"
#
# 背景:
#   Worker 偷懒会直接体现为交出残缺的代码，容易被发现；Verifier 偷懒体现为
#   一份写着 PASS/APPROVED 的报告，和"认真审查后确实没问题"在结果上长得
#   一模一样，天然更难被抓到，后果也更重——一旦判 APPROVED，循环就结束了，
#   没有下一轮给 Verifier 自我纠正的机会。这个脚本把这个原本会沉没的后果
#   重新接回 Verifier 身上，对称于 Worker 那边的 violation-log.txt 机制。
#
# 谁会调用这个脚本:
#   1. Verifier 自己：每轮审查时，如果发现这一轮的问题其实在上一轮的
#      verifier-report-round-N.txt 里被标记过 PASS，这是一次可核实的漏判，
#      必须如实记录，不能因为"记录自己的失误"而回避。
#   2. 人类：如果事后（比如代码上线后出 bug、或者另开一轮任务时）发现某次
#      APPROVED 其实是错的，可以手动调用这个脚本记一笔。
#   3. Worker：如果某一轮里发现 Verifier 明显没检查自己已经在 WORKER_REPORT
#      里坦白过的某个风险点，也可以调用记录。
#
# 记录会在下一次 Verifier 启动新一轮审查时被强制读取（见 SKILL-verifier.md），
# 用来提醒它"你有过漏判历史，这一轮不能再图省事"。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
LOG_FILE="$DUAL_DIR/verifier-violation-log.txt"
DESC="${1:-}"

if [ -z "$DESC" ]; then
    echo "ERROR: 用法: bash scripts/log-verifier-miss.sh \"<具体描述>\"" >&2
    exit 1
fi

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

ITER=$(cat "$DUAL_DIR/iteration.txt" 2>/dev/null || echo "?")
TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

{
    echo ""
    echo "[第 ${ITER} 轮 / ${TS}] ${DESC}"
} >> "$LOG_FILE"

echo "已记录到 verifier-violation-log.txt"
