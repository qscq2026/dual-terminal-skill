#!/bin/bash
# ============================================================================
# 有界轮询等待脚本
#
# 用法: bash wait-for-status.sh <worker|verifier> <目标状态1> [目标状态2] ...
#   例: bash scripts/wait-for-status.sh worker NEEDS_FIX APPROVED REJECTED
#       bash scripts/wait-for-status.sh verifier WORKER_DONE
#
# 设计动机:
#   旧版 SKILL 文件里直接写 `while [ status != X ]; do sleep 10; done`，
#   期望模型把这一整段当作单次 Bash 工具调用执行。但等待对象通常是"人类去
#   开另一个终端、启动 Claude Code、输入指令"，这个耗时从几分钟到几十分钟
#   不等，很容易撞上 Claude Code Bash 工具的执行时间上限（文档标称默认 2
#   分钟、显式 timeout 最高 10 分钟，实测中部分环境这个上限更短），导致
#   整段轮询被系统直接杀死，而不是优雅重试。
#
#   本脚本把"无界阻塞"改成"有界轮询 + 由调用方（模型）在工具调用层面反复
#   重新发起"：单次调用最多阻塞 WAIT_WINDOW_SECONDS 秒（默认 90 秒，明显
#   低于已知的超时上限），到点就返回，把"还没等到"如实报告给调用方，由
#   调用方（在其 agent loop 里）决定要不要再调一次。这样即使单次调用的
#   安全上限比预期更保守，也不会在一次调用内部被腰斩。
#
#   同时引入跨调用持久化的"累计已等待时间"，超过硬性上限（默认 30 分钟）
#   就不再建议继续傻等，而是明确返回信号，让 Worker / Verifier 停下来向
#   人类求助，避免陷入"模型自己也不知道已经等了多久"的静默死循环。
#
# 退出码:
#   0 = 已等到目标状态之一（stdout 输出 MATCHED:<状态>）
#   1 = 本轮窗口内未等到，未超硬上限，调用方应再次调用本脚本继续等待
#   2 = 累计等待已超过硬上限，调用方应停止轮询，提示人工介入
#   3 = 参数错误或环境未初始化
# ============================================================================

set -u

ROLE="${1:-}"
shift || true
TARGETS=("$@")

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
STATUS_FILE="$DUAL_DIR/status.txt"

if [ "$ROLE" != "worker" ] && [ "$ROLE" != "verifier" ]; then
    echo "ERROR: 第一个参数必须是 worker 或 verifier，实际收到: '$ROLE'" >&2
    exit 3
fi

if [ ${#TARGETS[@]} -eq 0 ]; then
    echo "ERROR: 至少需要指定一个目标状态" >&2
    exit 3
fi

if [ ! -f "$STATUS_FILE" ]; then
    echo "ERROR: $STATUS_FILE 不存在，环境未初始化，请先运行 start-dual-terminal.sh" >&2
    exit 3
fi

WAIT_STATE_FILE="$DUAL_DIR/.wait-elapsed-$ROLE"
WINDOW=${WAIT_WINDOW_SECONDS:-90}
INTERVAL=${WAIT_INTERVAL_SECONDS:-5}
HARD_CAP=${WAIT_HARD_CAP_SECONDS:-1800}

ELAPSED=$(cat "$WAIT_STATE_FILE" 2>/dev/null || echo 0)
case "$ELAPSED" in ''|*[!0-9]*) ELAPSED=0 ;; esac

CURRENT=""
t=0
while [ "$t" -lt "$WINDOW" ]; do
    CURRENT=$(cat "$STATUS_FILE" 2>/dev/null || echo "")
    for target in "${TARGETS[@]}"; do
        if [ "$CURRENT" = "$target" ]; then
            # 匹配成功，清零本角色的累计等待计数，供下一次等待重新计时
            echo "0" > "$WAIT_STATE_FILE"
            echo "MATCHED:$CURRENT"
            exit 0
        fi
    done
    sleep "$INTERVAL"
    t=$((t + INTERVAL))
    ELAPSED=$((ELAPSED + INTERVAL))
done

echo "$ELAPSED" > "$WAIT_STATE_FILE"

if [ "$ELAPSED" -ge "$HARD_CAP" ]; then
    echo "TIMEOUT_HARD_CAP:累计等待已达 ${ELAPSED}s（上限 ${HARD_CAP}s），当前状态仍为 '$CURRENT'，请勿继续轮询，改为提示用户检查另一终端是否卡住/已关闭"
    exit 2
fi

echo "TIMEOUT_WINDOW:本轮 ${WINDOW}s 内未等到目标状态（当前 '$CURRENT'，目标之一: ${TARGETS[*]}），累计已等待 ${ELAPSED}s / ${HARD_CAP}s，请再次调用本脚本继续等待"
exit 1
