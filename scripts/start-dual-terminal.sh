#!/bin/bash
# ============================================================================
# 双终端协作模式启动脚本
# 
# 用法: bash start-dual-terminal.sh [任务描述文件]
# 
# 功能:
#   1. 初始化 .dual-claude/ 共享目录
#   2. 设置状态机文件
#   3. 输出使用说明
# ============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DUAL_DIR="$PROJECT_DIR/.dual-claude"

echo "=========================================="
echo "  双终端协作模式 - 初始化"
echo "=========================================="
echo ""

# 创建共享目录
mkdir -p "$DUAL_DIR"

# 自动初始化 git（checkpoint.sh 的回滚能力依赖它；git init 只创建 .git，
# 不碰任何已有文件，是纯增量、易撤销的操作，不需要每次都问人）。
# 已经是 git 仓库（包括嵌套在上级目录的仓库）就跳过；实在不想要，设置环境
# 变量 DUAL_CLAUDE_NO_GIT_INIT=1 即可跳过这一步，继续用较弱的文件快照兜底。
cd "$PROJECT_DIR"
if [ -z "${DUAL_CLAUDE_NO_GIT_INIT:-}" ] && ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    if command -v git > /dev/null 2>&1; then
        git init -q
        if [ -z "$(git config user.email 2>/dev/null)" ]; then
            git config user.email "dual-terminal-skill@local"
        fi
        if [ -z "$(git config user.name 2>/dev/null)" ]; then
            git config user.name "dual-terminal-skill"
        fi
        echo "✅ 检测到项目不是 git 仓库，已自动执行 git init（checkpoint.sh 需要）"
    else
        echo "⚠️  未检测到 git 命令，checkpoint.sh 将只能使用较弱的文件快照兜底"
    fi
fi

# 不管 git 是刚被自动初始化的，还是项目本来就有，都确保 .dual-claude/ 被
# gitignore——否则 checkpoint.sh 的 `git add -A` 会把状态协调文件（status.txt、
# 等待计数器……）和真正的代码改动混进同一个 commit，污染每一次 checkpoint。
if git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    GITIGNORE_FILE="$PROJECT_DIR/.gitignore"
    if [ ! -f "$GITIGNORE_FILE" ] || ! grep -qxF '.dual-claude/' "$GITIGNORE_FILE" 2>/dev/null; then
        {
            [ -s "$GITIGNORE_FILE" ] && echo ""
            echo "# dual-terminal-skill 的运行时状态目录，不需要进版本控制"
            echo ".dual-claude/"
        } >> "$GITIGNORE_FILE"
        echo "✅ 已将 .dual-claude/ 加入项目的 .gitignore（避免和代码改动混在一起提交）"
    fi
fi

# 初始化状态文件
echo "IDLE" > "$DUAL_DIR/status.txt"
echo "0" > "$DUAL_DIR/iteration.txt"
echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$DUAL_DIR/created_at.txt"

# 处理任务描述
if [ -n "$1" ] && [ -f "$1" ]; then
    cp "$1" "$DUAL_DIR/task.txt"
    echo "✅ 已加载任务文件: $1"
elif [ -n "$1" ]; then
    echo "$1" > "$DUAL_DIR/task.txt"
    echo "✅ 已创建任务描述"
else
    if [ ! -f "$DUAL_DIR/task.txt" ]; then
        cat > "$DUAL_DIR/task.txt" << 'EOF'
# 任务描述
# 请编辑此文件，填入具体任务后启动两个终端

EOF
        echo "📝 请编辑 $DUAL_DIR/task.txt 填入任务描述"
    fi
fi

# 创建空的输出文件
touch "$DUAL_DIR/worker-output.txt"
touch "$DUAL_DIR/verifier-report.txt"

# 初始化违规记录（跨轮次持久化，Worker 每轮循环开始时必须先读取）
if [ ! -f "$DUAL_DIR/violation-log.txt" ]; then
    echo "（暂无历史违规记录）" > "$DUAL_DIR/violation-log.txt"
fi

# 初始化 Verifier 漏判记录（对称机制：Verifier 每轮循环开始时必须先读取）
if [ ! -f "$DUAL_DIR/verifier-violation-log.txt" ]; then
    echo "（暂无历史漏判记录）" > "$DUAL_DIR/verifier-violation-log.txt"
fi

# 初始化累计等待秒数计数器（供 wait-for-status.sh 判断是否达到硬性超时上限）
echo "0" > "$DUAL_DIR/.wait-elapsed-worker"
echo "0" > "$DUAL_DIR/.wait-elapsed-verifier"

# 初始化任务历史归档（set-task.sh 更新 task.txt 时会把旧内容追加到这里）
if [ ! -f "$DUAL_DIR/task-history.md" ]; then
    echo "# 任务历史归档" > "$DUAL_DIR/task-history.md"
    echo "" >> "$DUAL_DIR/task-history.md"
    echo "> 每次 set-task.sh 更新 task.txt，旧内容会被追加到这里，按时间倒序往下翻。" >> "$DUAL_DIR/task-history.md"
fi

# 初始化 checkpoint 计数器（checkpoint.sh 使用）
echo "0" > "$DUAL_DIR/checkpoint-count.txt"

# 初始化"连续无新增[阻塞]问题"计数器（track-blocker-streak.sh 使用，
# 用来判断循环是否该收敛，而不是无限找细节问题）
echo "0" > "$DUAL_DIR/no-blocker-streak.txt"

echo ""
echo "=========================================="
echo "  环境初始化完成"
echo "=========================================="
echo ""
echo "共享目录: $DUAL_DIR"
echo "当前状态: $(cat $DUAL_DIR/status.txt)"
echo "迭代次数: $(cat $DUAL_DIR/iteration.txt)"
echo ""
echo "------------------------------------------"
echo "  终端 A (Worker)"
echo "------------------------------------------"
echo "  1. 打开新终端窗口/标签页"
echo "  2. cd $PROJECT_DIR"
echo "  3. 启动 Claude Code: claude"
echo "  4. 加载 Skill: 开始工作"
echo "  5. 按 Skill 指引执行"
echo ""
echo "------------------------------------------"
echo "  终端 B (Verifier)"
echo "------------------------------------------"
echo "  1. 打开新终端窗口/标签页"
echo "  2. cd $PROJECT_DIR"
echo "  3. 启动 Claude Code: claude"
echo "  4. 加载 Skill: 开始审查"
echo "  5. 按 Skill 指引执行"
echo ""
echo "------------------------------------------"
echo "  状态文件说明"
echo "------------------------------------------"
echo "  .dual-claude/status.txt"
echo "    IDLE          - 等待开始"
echo "    WORKER_DONE   - Worker 已提交，等待审查"
echo "    NEEDS_FIX     - 需要 Worker 修正"
echo "    APPROVED      - 审查通过，任务完成"
echo "    REJECTED      - 任务被驳回"
echo ""
echo "  .dual-claude/iteration.txt"
echo "    当前迭代次数（由 Verifier 递增）"
echo ""
echo "  .dual-claude/violation-log.txt        - Worker 历史违规记录（Worker 每轮强制读取）"
echo "  .dual-claude/verifier-violation-log.txt - Verifier 历史漏判记录（Verifier 每轮强制读取）"
echo "  .dual-claude/task-history.md          - task.txt 的历史版本归档（set-task.sh 维护）"
echo "  .dual-claude/checkpoint-count.txt     - 回滚点计数（checkpoint.sh 维护）"
echo "  .dual-claude/no-blocker-streak.txt    - 连续无新增[阻塞]问题轮数（track-blocker-streak.sh 维护）"
echo ""
echo "=========================================="
