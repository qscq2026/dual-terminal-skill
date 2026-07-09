#!/bin/bash
# ============================================================================
# 创建回滚点（Worker 在每轮开始修改代码之前调用）
#
# 用法: bash scripts/checkpoint.sh
#
# 背景:
#   复盘发现整个项目从头到尾没有任何回滚机制——改完代码直接覆盖原文件，
#   Verifier 发现严重问题也无法快速恢复到上一轮。这个脚本只做一件事：在
#   Worker 动手改代码之前，先把当前状态存一份，让"改坏了"这件事变得可逆。
#
#   只负责"存"，不负责"退"。回滚本身是有损操作（会丢弃之后的修改），
#   不应该由脚本自动执行——真出问题时，应该由人自己决定要不要回滚、回滚到
#   哪一个点。回滚指引见 scripts/rollback-help.sh（只打印操作步骤，不执行）。
#
# 行为:
#   - 如果项目是 git 仓库：git add -A + commit（本轮无改动则允许空提交），
#     再打一个 dual-claude-checkpoint-N 标签，方便按轮次定位。
#   - 如果不是 git 仓库：把项目文件（排除 .dual-claude/node_modules/.git）
#     复制一份快照到 .dual-claude/checkpoints/round-N-<时间戳>/。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
PROJECT_DIR="$(dirname "$DUAL_DIR")"
COUNT_FILE="$DUAL_DIR/checkpoint-count.txt"

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

N=$(cat "$COUNT_FILE" 2>/dev/null || echo 0)
case "$N" in ''|*[!0-9]*) N=0 ;; esac
NEW=$((N + 1))
TS="$(date -u +"%Y%m%dT%H%M%SZ")"

cd "$PROJECT_DIR"

if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    # 自愈检查：确保 .dual-claude/ 已被 gitignore（正常情况下
    # start-dual-terminal.sh 已经处理过，这里是防御性兜底，比如项目是从旧版本
    # 升级上来的，或者 .gitignore 后来被手动删了），避免状态协调文件混进提交
    GITIGNORE_FILE="$PROJECT_DIR/.gitignore"
    if [ ! -f "$GITIGNORE_FILE" ] || ! grep -qxF '.dual-claude/' "$GITIGNORE_FILE" 2>/dev/null; then
        {
            [ -s "$GITIGNORE_FILE" ] && echo ""
            echo "# dual-terminal-skill 的运行时状态目录，不需要进版本控制"
            echo ".dual-claude/"
        } >> "$GITIGNORE_FILE"
    fi

    git add -A
    if git diff --cached --quiet; then
        git commit -q --allow-empty -m "checkpoint(dual-terminal): round ${NEW} — 本轮开始前，无未提交改动"
    else
        git commit -q -m "checkpoint(dual-terminal): round ${NEW} — Worker 修改代码前的状态"
    fi
    git tag -f "dual-claude-checkpoint-${NEW}" > /dev/null 2>&1
    HASH="$(git rev-parse --short HEAD)"
    echo "已创建 git 回滚点: dual-claude-checkpoint-${NEW} (${HASH})"
else
    CKPT_DIR="$DUAL_DIR/checkpoints/round-${NEW}-${TS}"
    mkdir -p "$CKPT_DIR"
    shopt -s dotglob nullglob
    for item in "$PROJECT_DIR"/*; do
        base="$(basename "$item")"
        case "$base" in
            .dual-claude|node_modules|.git) continue ;;
        esac
        cp -r "$item" "$CKPT_DIR/" 2>/dev/null || true
    done
    echo "已创建文件快照: $CKPT_DIR"
    echo "提示：当前项目不是 git 仓库，文件快照只能整体覆盖回去，没有 diff、"
    echo "没有精确到单个文件的局部回滚。如果需要更强的回滚能力，可以自己运行"
    echo "'git init' 把项目变成 git 仓库（这个决定由你来做，本脚本不会替你执行），"
    echo "下次 checkpoint.sh 会自动检测到并切换成 git commit + tag 的方式。"
fi

tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"
echo "$NEW" > "$tmp"
mv "$tmp" "$COUNT_FILE"
