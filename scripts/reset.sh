#!/bin/bash
# ============================================================================
# 重置脚本
# 
# 用法: bash reset.sh
# 
# 功能: 重置双终端协作状态，保留任务描述
# ============================================================================

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"

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
cp "$DUAL_DIR"/verifier-report-round-*.txt "$BACKUP_DIR/" 2>/dev/null || true

# 重置状态（原子写：先写临时文件再 mv，避免另一终端在写入过程中读到半截内容）
tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"; echo "IDLE" > "$tmp"; mv "$tmp" "$DUAL_DIR/status.txt"
tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"; echo "0" > "$tmp"; mv "$tmp" "$DUAL_DIR/iteration.txt"
> "$DUAL_DIR/worker-output.txt"
> "$DUAL_DIR/verifier-report.txt"
echo "（暂无历史违规记录）" > "$DUAL_DIR/violation-log.txt"
echo "（暂无历史漏判记录）" > "$DUAL_DIR/verifier-violation-log.txt"
rm -f "$DUAL_DIR"/verifier-report-round-*.txt

# 重置累计等待计数器，避免上一轮遗留的等待时长被误判为本轮已超硬上限
echo "0" > "$DUAL_DIR/.wait-elapsed-worker"
echo "0" > "$DUAL_DIR/.wait-elapsed-verifier"

echo "✅ 状态已重置"
echo "备份目录: $BACKUP_DIR"
echo "当前状态: $(cat $DUAL_DIR/status.txt)"
echo "迭代次数: $(cat $DUAL_DIR/iteration.txt)"
