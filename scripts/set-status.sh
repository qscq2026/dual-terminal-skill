#!/bin/bash
# ============================================================================
# 状态原子写入脚本
#
# 用法: bash scripts/set-status.sh <STATUS>
#   STATUS 必须是: IDLE | WORKER_DONE | NEEDS_FIX | APPROVED | REJECTED
#
# 为什么不能直接 `echo STATUS > .dual-claude/status.txt`:
#   status.txt 是 Worker / Verifier 两个独立进程之间唯一的协调点，任何一方
#   都可能在另一方正在读取它的同时发起写入。直接重定向写文件在极少数时机
#   下可能被读者读到"截断到一半"的内容（尤其是文件系统层面不保证单条
#   echo 的写入在多进程读写下是原子可见的）。本脚本改为"写临时文件 -> mv
#   覆盖"，mv 在同一文件系统内是原子操作，读者要么读到旧内容，要么读到
#   完整新内容，不会读到半截。
#   同时做了取值校验，避免拼错状态名（比如敲成 "APPROVE" 而不是
#   "APPROVED"）导致状态机卡死却没有任何报错。
#
#   顺带把每次状态转移追加进 event-log.txt——watch-status.sh 靠这份历史
#   展示"这一路是怎么走过来的"，而不只是"现在是什么状态"。角色（Worker/
#   Verifier/System）根据要设置的状态值推断，不需要额外传参、不用改调用
#   方式：WORKER_DONE 只有 Worker 会设置，NEEDS_FIX/APPROVED/REJECTED 只
#   有 Verifier 会设置，IDLE 只有 reset.sh 会设置。
#
#   写 APPROVED 之前，会检查迭代数有没有达到 min-iter.txt 里记的下限，没
#   达到直接拒绝，不写入、不留任何余地。这是这套系统里少数几处不靠"写清
#   楚规则、指望模型照做"、而是靠代码直接拒绝执行的地方——因为"迭代数够
#   不够用户要求的下限"是一个纯粹可数的事实，不需要判断力，也就不应该
#   交给判断力去决定。真实项目里出过用户说"至少15轮"、Verifier 第4轮就
#   自己判了通过的事故，这个检查就是为了让同样的事故在代码层面不可能
#   重演，而不是在文档里再多写一条"不要这样做"。
# ============================================================================

set -eu

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
STATUS="${1:-}"

if [ -z "$STATUS" ]; then
    echo "ERROR: 用法: bash scripts/set-status.sh <STATUS>" >&2
    exit 1
fi

case "$STATUS" in
    IDLE|WORKER_DONE|NEEDS_FIX|APPROVED|REJECTED) ;;
    *)
        echo "ERROR: 未知状态 '$STATUS'。允许值: IDLE / WORKER_DONE / NEEDS_FIX / APPROVED / REJECTED" >&2
        exit 1
        ;;
esac

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: $DUAL_DIR 不存在，请先运行 start-dual-terminal.sh" >&2
    exit 1
fi

if [ "$STATUS" = "APPROVED" ]; then
    MIN_ITER="$(cat "$DUAL_DIR/min-iter.txt" 2>/dev/null || echo '')"
    CUR_ITER="$(cat "$DUAL_DIR/iteration.txt" 2>/dev/null || echo '0')"
    case "$MIN_ITER" in
        ''|*[!0-9]*) : ;;  # 没设下限或内容非法，跳过这项检查
        *)
            case "$CUR_ITER" in
                ''|*[!0-9]*) CUR_ITER=0 ;;
            esac
            if [ "$CUR_ITER" -lt "$MIN_ITER" ]; then
                echo "ERROR: 拒绝写入 APPROVED——当前迭代数（${CUR_ITER}）未达到用户要求的下限（${MIN_ITER}）。" >&2
                echo "这不是可以商量的判断，是硬约束：用户明确要求至少 ${MIN_ITER} 轮，现在还不够。" >&2
                echo "继续判 NEEDS_FIX，把这一轮的审查结果正常写进报告。" >&2
                exit 1
            fi
            ;;
    esac
fi

OLD_STATUS="$(cat "$DUAL_DIR/status.txt" 2>/dev/null || echo '?')"

tmp="$(mktemp "$DUAL_DIR/.tmp.XXXXXX")"
echo "$STATUS" > "$tmp"
mv "$tmp" "$DUAL_DIR/status.txt"

case "$STATUS" in
    WORKER_DONE) ACTOR="Worker" ;;
    NEEDS_FIX|APPROVED|REJECTED) ACTOR="Verifier" ;;
    IDLE) ACTOR="System" ;;
    *) ACTOR="?" ;;
esac
ITER="$(cat "$DUAL_DIR/iteration.txt" 2>/dev/null || echo '?')"
echo "$(date '+%H:%M:%S') [${ACTOR}] ${OLD_STATUS} -> ${STATUS} (iter=${ITER})" >> "$DUAL_DIR/event-log.txt"

echo "状态已设置为: $STATUS"
