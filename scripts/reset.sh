#!/bin/bash
# ============================================================================
# 重置脚本
#
# 用法: bash reset.sh [--keep-violation-logs]
#
# 功能: 重置双终端协作状态，保留任务描述
#
# --keep-violation-logs: 跳过清空 violation-log.txt / verifier-violation-log.txt
#   这两份信誉记录。默认不加这个参数时行为不变（连信誉记录一起清，彻底重来）。
#   这个开关主要给 next-round.sh 复用——同一个项目开始新一轮需求时，历史违规
#   /漏判记录还有参考价值，不该因为换了一批需求就清零。
# ============================================================================

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"

KEEP_LOGS=0
if [ "${1:-}" = "--keep-violation-logs" ]; then
    KEEP_LOGS=1
fi

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: .dual-claude/ 目录不存在"
    exit 1
fi

echo "🔄 重置双终端协作状态..."

# 备份当前状态
BACKUP_DIR="$DUAL_DIR/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp "$DUAL_DIR/status.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/worker-output.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/verifier-report.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/iteration.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/violation-log.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/verifier-violation-log.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/no-blocker-streak.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/event-log.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/worker-phase.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/verifier-phase.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/limit.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR/min-iter.txt" "$BACKUP_DIR/" 2>/dev/null || true
cp "$DUAL_DIR"/verifier-report-round-*.txt "$BACKUP_DIR/" 2>/dev/null || true

# 重置状态（原子写：先写临时文件再 mv，避免另一终端在写入过程中读到半截内容）
tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"; echo "IDLE" > "$tmp"; mv "$tmp" "$DUAL_DIR/status.txt"
tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"; echo "0" > "$tmp"; mv "$tmp" "$DUAL_DIR/iteration.txt"
> "$DUAL_DIR/worker-output.txt"
> "$DUAL_DIR/verifier-report.txt"
if [ "$KEEP_LOGS" -eq 0 ]; then
    echo "（暂无历史违规记录）" > "$DUAL_DIR/violation-log.txt"
    echo "（暂无历史漏判记录）" > "$DUAL_DIR/verifier-violation-log.txt"
fi
rm -f "$DUAL_DIR"/verifier-report-round-*.txt

# 重置累计等待计数器，避免上一轮遗留的等待时长被误判为本轮已超硬上限
echo "0" > "$DUAL_DIR/.wait-elapsed-worker"
echo "0" > "$DUAL_DIR/.wait-elapsed-verifier"

# 重置"连续无新增阻塞问题"计数器（每个任务重新开始计）
echo "0" > "$DUAL_DIR/no-blocker-streak.txt"

# 重置事件日志和阶段上报（新一轮从空白仪表盘开始，不带上一轮的历史事件）
: > "$DUAL_DIR/event-log.txt"
{ date +%s; echo "(尚未开始)"; } > "$DUAL_DIR/worker-phase.txt"
{ date +%s; echo "(尚未开始)"; } > "$DUAL_DIR/verifier-phase.txt"

# limit.txt / min-iter.txt 都由 Verifier 在下一轮启动时按用户口头指定的值
# 重新写入，这里直接移除，避免仪表盘展示上一轮遗留的旧范围、也避免
# set-status.sh 拿上一轮的下限去卡这一轮的 APPROVED
rm -f "$DUAL_DIR/limit.txt"
rm -f "$DUAL_DIR/min-iter.txt"

# 注意：checkpoint-count.txt 和 task-history.md 不在这里重置——前者用来保证
# git checkpoint 标签不因重置而重号覆盖历史回滚点，后者是跨任务的永久归档，
# 两者都应该是整个项目生命周期内持续累积的，不是单次任务的状态。

echo "✅ 状态已重置"
echo "备份目录: $BACKUP_DIR"
echo "当前状态: $(cat $DUAL_DIR/status.txt)"
echo "迭代次数: $(cat $DUAL_DIR/iteration.txt)"
if [ "$KEEP_LOGS" -eq 1 ]; then
    echo "（--keep-violation-logs：两份信誉记录未清空）"
fi
