#!/bin/bash
# ============================================================================
# 回滚指引（只打印操作步骤，不自动执行任何破坏性操作）
#
# 用法: bash scripts/rollback-help.sh
#
# 为什么不做成一键回滚:
#   回滚是有损操作，会丢弃回滚点之后的所有修改。这个决定应该由人来做，
#   脚本负责的是"让人知道有哪些回滚点、怎么回滚"，不负责替人按下那个键。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
PROJECT_DIR="$(dirname "$DUAL_DIR")"

cd "$PROJECT_DIR"

echo "=== 可用回滚点 ==="
echo ""

if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    TAGS="$(git tag -l 'dual-claude-checkpoint-*' --sort=-creatordate 2>/dev/null || true)"
    if [ -z "$TAGS" ]; then
        echo "（暂无 checkpoint，Worker 还没有调用过 checkpoint.sh）"
    else
        echo "$TAGS" | while read -r t; do
            [ -z "$t" ] && continue
            h="$(git rev-list -n1 "$t" 2>/dev/null || echo '?')"
            msg="$(git log -1 --format=%s "$t" 2>/dev/null || echo '')"
            echo "  $t  ($h)  $msg"
        done
    fi
    echo ""
    echo "回滚方法（谨慎操作，会丢弃回滚点之后的改动）："
    echo "  git reset --hard <tag名或commit hash>"
    echo "  例如: git reset --hard dual-claude-checkpoint-3"
    echo ""
    echo "如果只想看某个回滚点和现在的差异，不想真的回滚："
    echo "  git diff dual-claude-checkpoint-3 HEAD"
else
    CKPTS="$(ls -1dt "$DUAL_DIR"/checkpoints/round-*/ 2>/dev/null || true)"
    if [ -z "$CKPTS" ]; then
        echo "（暂无快照，Worker 还没有调用过 checkpoint.sh）"
    else
        echo "$CKPTS"
    fi
    echo ""
    echo "回滚方法（谨慎操作，建议先手动备份当前状态再覆盖）："
    echo "  把对应快照目录下的文件复制回项目根目录，例如："
    echo "  cp -r <快照目录>/* ."
    echo ""
    echo "提示：文件快照没有 diff、没有精确到单个文件的局部回滚。想要更强的"
    echo "回滚能力，可以自己运行 'git init'，下次 checkpoint.sh 会自动切换成"
    echo "git commit + tag 的方式。"
fi
