#!/bin/bash
# ============================================================================
# 本轮简报（context refresh，不是又一个可以被跳过的独立步骤）
#
# 用法: bash scripts/round-brief.sh <worker|verifier>
#
# 背景（这是这个脚本存在的唯一理由，务必保留这段说明）:
#   真实复盘（169 轮长会话）发现：SKILL.md 里写的规则、上一轮的结论、还
#   没解决的问题——这些信息哪怕都写在文件里、哪怕指令写得再"强制"（步骤
#   2.5 曾经从建议改写成主循环里字面意义的 cat 命令，依然"基本没执行
#   过"），只要模型要靠翻几十上百轮之前的对话历史去回忆，就几乎必然被
#   跳过、被稀释。这是长上下文模型的正常表现（信息离当前决策点越远，
#   召回权重越低），不是模型不认真——之前几轮一直往"指令写得够不够强硬"
#   上使劲，方向就错了。
#
#   真正的解法不是"提醒得更用力"，是让这份信息在每一轮决策前一刻被重新
#   组装、重新摆出来，不需要模型去记得或回忆，只需要读眼前这一份——这就
#   是"context 而不是 control"。
#
#   这个脚本本身不是被模型"记得调用"的——它被焊在 wait-for-status.sh
#   匹配成功、把控制权交还给模型的那一刻自动触发，是整套系统里唯一一处
#   结构上不可能被跳过的位置（不看这个输出，模型不知道该干什么，循环
#   走不下去）。所以简报也就跟着变成了不可能被跳过的东西。
#
#   本脚本从 .dual-claude/ 下的现有文件纯文本提取，不做语义理解，提取
#   失败就留空跳过，不影响 wait-for-status.sh 的退出码。
#
#   设计上刻意不放"铁律/红线，每轮都适用"这种固定文案清单——固定文案不管
#   写得多重要，念叨多了会被模式识别成背景噪音，跳过的概率不会因为"强调
#   了"而降低，这跟这个脚本本来要解决的问题是同一个坑。下面每一条能做成
#   "只在检测到具体异常迹象时才出现"的，都改成了这样：没有异常就不出现，
#   出现本身就是信号，而不是自证式的重复提醒。
#
#   例外：Verifier"永远不碰代码"这条没有找到能做成证据化检测的办法（要
#   可靠判断"这次改动是不是 Verifier 自己碰的"，需要比 diff 更深的溯源，
#   这里没做），所以没有放进本脚本的常规输出——它只在 SKILL-verifier.md
#   最显眼的位置完整出现一次，不在这里重复稀释。这是没解决、不是忘了。
# ============================================================================

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
ROLE="${1:-}"

echo ""
echo "----------------------------------------"
echo "本轮简报（自动生成，以此为准，不要凭记忆判断）"
echo "----------------------------------------"

TASK=$(head -c 260 "$DUAL_DIR/task.txt" 2>/dev/null)
echo "任务: ${TASK:-（未知）}"

MILESTONE=$(grep -m1 '^- \[ \] M[0-9]' "$DUAL_DIR/plan.md" 2>/dev/null | sed 's/^- \[ \] //')
if [ -n "$MILESTONE" ]; then
    echo "当前里程碑: $MILESTONE"
else
    echo "当前里程碑: （plan.md 尚未规划，或所有里程碑已勾选完成）"
fi

ITER=$(cat "$DUAL_DIR/iteration.txt" 2>/dev/null)
ITER=${ITER:-0}
LIMIT=$(cat "$DUAL_DIR/limit.txt" 2>/dev/null)
LIMIT=${LIMIT:-?}
MIN_ITER=$(cat "$DUAL_DIR/min-iter.txt" 2>/dev/null)
if [ -n "$MIN_ITER" ] && [ "$MIN_ITER" != "$LIMIT" ]; then
    echo "迭代: 第 ${ITER} / ${LIMIT} 轮（用户要求至少 ${MIN_ITER} 轮，硬约束，见 set-status.sh）"
else
    echo "迭代: 第 ${ITER} / ${LIMIT} 轮"
fi

if [ "$ROLE" = "worker" ]; then

    VERDICT=$(grep -A4 '^### 总体结论' "$DUAL_DIR/verifier-report.txt" 2>/dev/null)
    if [ -n "$VERDICT" ]; then
        echo "--- 上一轮 Verifier 结论 ---"
        echo "$VERDICT"
    fi

    BLOCKERS=$(grep '^- \[阻塞\]' "$DUAL_DIR/verifier-report.txt" 2>/dev/null)
    if [ -n "$BLOCKERS" ]; then
        echo "--- 上一轮指出的[阻塞]问题（逐条处理，不要遗漏） ---"
        echo "$BLOCKERS"
    fi

    V_COUNT=$(grep -c '^\[第' "$DUAL_DIR/violation-log.txt" 2>/dev/null)
    V_COUNT=${V_COUNT:-0}
    if [ "$V_COUNT" -gt 0 ] 2>/dev/null; then
        echo "你的历史违规记录: ${V_COUNT} 条 [!]（见 violation-log.txt）"
    fi

    # 下面几条不是每轮固定念一遍的规则清单——固定文案念叨久了会被当背景
    # 噪音跳过，这本身是之前静态"铁律"清单的问题所在。改成只有真的检测到
    # 具体异常迹象时才出现的证据，没异常就不出现，出现本身就是信号。
    CKPT_COUNT=$(cat "$DUAL_DIR/checkpoint-count.txt" 2>/dev/null)
    CKPT_COUNT=${CKPT_COUNT:-0}
    if [ "$CKPT_COUNT" -lt "$ITER" ] 2>/dev/null; then
        echo "[!] checkpoint 记录数（${CKPT_COUNT}）少于已完成迭代数（${ITER}）——可能有某一轮跳过了 checkpoint.sh"
    fi

    if grep -qE '全流程正确执行|已按要求完成|功能(已经)?正常|全部完成' "$DUAL_DIR/worker-output.txt" 2>/dev/null; then
        echo "[!] 你上一轮的提交里出现了类似'全流程正确执行'的笼统表述——这类话没法核实，这次请写清楚具体验证了什么、怎么验证的"
    fi

elif [ "$ROLE" = "verifier" ]; then

    if [ "$ITER" -gt 0 ] 2>/dev/null; then
        PREV_VERDICT=$(grep -A4 '^### 总体结论' "$DUAL_DIR/verifier-report-round-${ITER}.txt" 2>/dev/null)
        if [ -n "$PREV_VERDICT" ]; then
            echo "--- 你上一轮（round ${ITER}）自己的结论 ---"
            echo "$PREV_VERDICT"
        fi
    fi

    M_COUNT=$(grep -c '^\[第' "$DUAL_DIR/verifier-violation-log.txt" 2>/dev/null)
    M_COUNT=${M_COUNT:-0}
    if [ "$M_COUNT" -gt 0 ] 2>/dev/null; then
        echo "你的历史漏判记录: ${M_COUNT} 条 [!]（见 verifier-violation-log.txt）"
    fi

    STREAK=$(cat "$DUAL_DIR/no-blocker-streak.txt" 2>/dev/null)
    STREAK=${STREAK:-0}
    echo "连续无新增[阻塞]轮数: ${STREAK}"

    # 不是提醒"不要轻易判通过"，是把你自己最近几轮实际写下的判断原样列
    # 出来——一个模型能为任何结论编出听起来具体、像那么回事的理由，包括
    # 给"提前收工"编理由；能拦住这件事的不是让你再多写一段自我说服，是
    # 把你自己刚刚写过的记录摆在你面前，让新的判断没法绕开跟它矛不矛盾
    HIST=""
    if [ "$ITER" -gt 0 ] 2>/dev/null; then
        START=$((ITER - 4))
        [ "$START" -lt 1 ] && START=1
        i="$START"
        while [ "$i" -le "$ITER" ]; do
            S=$(grep -m1 -- '- \*\*状态\*\*:' "$DUAL_DIR/verifier-report-round-${i}.txt" 2>/dev/null | sed 's/^- \*\*状态\*\*: *//')
            [ -n "$S" ] && HIST="${HIST}round ${i}: ${S}
"
            i=$((i + 1))
        done
    fi
    if [ -n "$HIST" ]; then
        echo "--- 你最近几轮实际写下的判断（不是提醒，是你自己的记录） ---"
        printf '%s' "$HIST"
    fi

    # 步骤2.5的交叉核对材料直接摆出来，不是提醒你"要记得做"，是把要对比
    # 的东西现放在这——最近两轮的[阻塞]清单，同一个问题有没有跨轮次重复
    # 出现，一眼对比就知道，不用去翻档案、也不用被动等提醒
    PREV=$((ITER - 1))
    B_CUR=""
    B_PREV=""
    if [ "$ITER" -gt 0 ] 2>/dev/null; then
        B_CUR=$(grep '^- \[阻塞\]' "$DUAL_DIR/verifier-report-round-${ITER}.txt" 2>/dev/null)
    fi
    if [ "$PREV" -gt 0 ] 2>/dev/null; then
        B_PREV=$(grep '^- \[阻塞\]' "$DUAL_DIR/verifier-report-round-${PREV}.txt" 2>/dev/null)
    fi
    if [ -n "$B_CUR" ] || [ -n "$B_PREV" ]; then
        echo "--- 交叉核对材料（round ${PREV} vs round ${ITER}，同一问题连续3轮→强制REJECTED）---"
        [ -n "$B_PREV" ] && { echo "round ${PREV}:"; echo "$B_PREV"; }
        [ -n "$B_CUR" ] && { echo "round ${ITER}:"; echo "$B_CUR"; }
    fi

    # 客观的改动证据，不是"请核实Worker报告是否属实"这句提醒，是把能核实
    # 的原始材料直接算出来摆在这——git diff 为空但 Worker 报告说改了，
    # 矛盾自己就摆在眼前，不需要 Verifier 主动去想起来查
    #
    # 注意：这条证据可靠的前提是 checkpoint.sh 严格按 SKILL-worker.md 规定
    # 的时机调用（改代码之前一次，改完不再二次调用）。如果 Worker 在改完
    # 代码后又调用了一次 checkpoint.sh，这次改动会被吸收进那次提交里，
    # diff 对比 HEAD 会显示为空——不代表没改，代表 checkpoint 时机不对。
    # 这条不是万无一失的证据，是"通常情况下能用、但依赖上游动作时机正确"
    # 的信号，跟其他证据一起看，不要单独当结论。
    PROJECT_DIR="$(dirname "$DUAL_DIR")"
    if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
        DIFF_STAT=$(git -C "$PROJECT_DIR" diff --stat HEAD 2>/dev/null)
        if [ -n "$DIFF_STAT" ]; then
            echo "--- 自上次 checkpoint 以来的实际改动（git diff --stat）---"
            echo "$DIFF_STAT"
        else
            echo "[!] 自上次 checkpoint 以来 git diff 为空——如果 Worker 报告里声称有代码修改，这里是矛盾的"
        fi
    fi

fi

echo "----------------------------------------"
