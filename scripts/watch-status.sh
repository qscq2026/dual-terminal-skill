#!/bin/bash
# ============================================================================
# 状态监控脚本
# 
# 用法: bash watch-status.sh
# 
# 功能: 实时监控双终端协作的状态变化
# ============================================================================

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: .dual-claude/ 目录不存在，请先运行 start-dual-terminal.sh"
    exit 1
fi

echo "🔍 监控双终端协作状态 (按 Ctrl+C 退出)"
echo "=========================================="

LAST_STATUS=""
while true; do
    STATUS=$(cat "$DUAL_DIR/status.txt" 2>/dev/null || echo "UNKNOWN")
    ITERATION=$(cat "$DUAL_DIR/iteration.txt" 2>/dev/null || echo "0")

    if [ "$STATUS" != "$LAST_STATUS" ]; then
        echo ""
        echo "[$(date '+%H:%M:%S')] 状态变更: $STATUS | 迭代: $ITERATION"

        case "$STATUS" in
            "IDLE")
                echo "  → 等待 Worker 开始工作"
                ;;
            "WORKER_DONE")
                echo "  → Worker 已提交，Verifier 可以开始审查"
                ;;
            "VERIFIER_DONE")
                echo "  → Verifier 已完成，Worker 可以读取报告"
                ;;
            "APPROVED")
                echo "  → ✅ 审查通过，任务完成！"
                echo ""
                echo "最终输出:"
                cat "$DUAL_DIR/worker-output.txt" 2>/dev/null | head -20
                echo ""
                echo "审查报告:"
                cat "$DUAL_DIR/verifier-report.txt" 2>/dev/null | head -20
                ;;
        esac

        LAST_STATUS="$STATUS"
    fi

    sleep 2
done
