#!/bin/bash
# ============================================================================
# 阶段上报（供 watch-status.sh 展示"两端现在具体在干什么"）
#
# 用法: bash scripts/heartbeat.sh <worker|verifier> "<阶段描述>"
#   例: bash scripts/heartbeat.sh worker "生成/修改代码中"
#       bash scripts/heartbeat.sh verifier "审查中 - 核实测试断言语义"
#
# 背景:
#   旧版 watch-status.sh 只能看到 status.txt 这一个粗粒度状态（IDLE/
#   WORKER_DONE/NEEDS_FIX/APPROVED/REJECTED），status.txt 不变的时候完全
#   看不出两端各自在干嘛——是在正常工作，还是卡住了、还是模型自己忘了继续。
#   这个脚本让 Worker/Verifier 在关键步骤顺手上报一句"现在在做什么"，
#   watch-status.sh 才有内容可以展示"两端的进行状态"，而不只是等 status.txt
#   变化才吱一声。
#
# 行为: 原子写入 .dual-claude/<role>-phase.txt，第一行是时间戳（供计算
#   "多少秒前"），第二行是阶段描述文本。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
ROLE="${1:-}"
PHASE="${2:-}"

if [ "$ROLE" != "worker" ] && [ "$ROLE" != "verifier" ]; then
    echo "ERROR: 第一个参数必须是 worker 或 verifier，实际收到: '$ROLE'" >&2
    exit 1
fi

if [ -z "$PHASE" ]; then
    echo "ERROR: 用法: bash scripts/heartbeat.sh <worker|verifier> \"<阶段描述>\"" >&2
    exit 1
fi

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

PHASE_FILE="$DUAL_DIR/${ROLE}-phase.txt"
tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"
{
    date +%s
    echo "$PHASE"
} > "$tmp"
mv "$tmp" "$PHASE_FILE"
