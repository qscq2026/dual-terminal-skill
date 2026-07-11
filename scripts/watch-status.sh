#!/bin/bash
# ============================================================================
# 状态监控脚本（结构化仪表盘）
#
# 用法: bash scripts/watch-status.sh
#
# v3.3 重写背景:
#   旧版只监控 status.txt 这一个粗粒度状态，status.txt 不变的时候完全看不出
#   两端各自在干嘛。真实长会话（68/71 轮）复盘发现，Worker/Verifier 自己的
#   轮询纪律在长会话里会衰减（多次需要用户提醒"你倒是看看反馈报告"）——这
#   件事光靠改 SKILL 文件里的文字指令解决不了，比较现实的办法是让人在第三
#   个终端主动盯着一份信息足够完整、足够及时、足够结构化的仪表盘，而不是
#   完全指望两端自己一直记得轮询。这个脚本就是照这个方向重写的。
#
# 展示内容: 状态机 / Worker 阶段 / Verifier 阶段 / 任务摘要 / 最近事件 /
#   需要关注的告警，状态为终态时附审查报告摘要。
#
# 刷新策略: 每秒检查一次相关文件是否有变化（用内容校验和判断，不是只看
#   status.txt），有变化才重绘，没变化不刷屏。
# ============================================================================

DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"

if [ ! -d "$DUAL_DIR" ]; then
    echo "ERROR: .dual-claude/ 目录不存在，请先运行 start-dual-terminal.sh"
    exit 1
fi

# ---- 工具函数 ----

read_file() {
    # 用法: read_file <path> [默认值]
    cat "$1" 2>/dev/null || echo "${2:-}"
}

seconds_ago() {
    # 用法: seconds_ago <epoch秒>，输出"Ns前"，输入非法时输出"未知"
    case "${1:-}" in ''|*[!0-9]*) echo "未知"; return ;; esac
    local now=$(date +%s)
    echo "$((now - $1))s前"
}

hr() { printf '%.0s-' $(seq 1 44); echo; }

count_entries() {
    # 统计 violation-log.txt / verifier-violation-log.txt 里的记录条数
    # （条目格式固定以"[第"开头，占位符文本不会被计入）
    grep -c '^\[第' "$1" 2>/dev/null || echo 0
}

fingerprint() {
    # 拼接所有会影响展示内容的文件算校验和，用来判断"要不要重绘"，避免刷屏
    cat \
        "$DUAL_DIR/status.txt" \
        "$DUAL_DIR/iteration.txt" \
        "$DUAL_DIR/limit.txt" \
        "$DUAL_DIR/no-blocker-streak.txt" \
        "$DUAL_DIR/worker-phase.txt" \
        "$DUAL_DIR/verifier-phase.txt" \
        "$DUAL_DIR/.wait-elapsed-worker" \
        "$DUAL_DIR/.wait-elapsed-verifier" \
        "$DUAL_DIR/violation-log.txt" \
        "$DUAL_DIR/verifier-violation-log.txt" \
        "$DUAL_DIR/event-log.txt" \
        2>/dev/null | cksum
}

# 跨轮次记住上次看到的违规/漏判条数，用来判断"是不是刚新增的"
PREV_V_COUNT=$(count_entries "$DUAL_DIR/violation-log.txt")
PREV_M_COUNT=$(count_entries "$DUAL_DIR/verifier-violation-log.txt")

# ---- 主渲染函数 ----

render() {
    clear
    echo "双终端协作监控        刷新: $(date '+%H:%M:%S')   (Ctrl+C 退出)"
    echo ""

    local status iteration limit streak
    status=$(read_file "$DUAL_DIR/status.txt" "UNKNOWN")
    iteration=$(read_file "$DUAL_DIR/iteration.txt" "0")
    limit=$(read_file "$DUAL_DIR/limit.txt" "?")
    streak=$(read_file "$DUAL_DIR/no-blocker-streak.txt" "0")

    hr
    echo "状态机"
    hr
    printf "  当前状态: %-14s  迭代: %s / %s\n" "$status" "$iteration" "$limit"
    echo "  连续无新增[阻塞]轮数: $streak"
    echo ""

    # ---- Worker ----
    local w_phase_ts w_phase_text w_wait ckpt_count v_count
    w_phase_ts=$(sed -n '1p' "$DUAL_DIR/worker-phase.txt" 2>/dev/null)
    w_phase_text=$(sed -n '2p' "$DUAL_DIR/worker-phase.txt" 2>/dev/null)
    [ -z "$w_phase_text" ] && w_phase_text="(尚未开始)"
    w_wait=$(read_file "$DUAL_DIR/.wait-elapsed-worker" "0")
    ckpt_count=$(read_file "$DUAL_DIR/checkpoint-count.txt" "0")
    v_count=$(count_entries "$DUAL_DIR/violation-log.txt")

    hr
    echo "Worker（终端 A）"
    hr
    echo "  当前阶段: $w_phase_text"
    [ -n "$w_phase_ts" ] && echo "  阶段更新于: $(seconds_ago "$w_phase_ts")"
    echo "  累计等待: ${w_wait}s"
    echo "  已创建回滚点: ${ckpt_count} 个"
    if [ "$v_count" -gt 0 ] 2>/dev/null; then
        echo "  历史违规记录: ${v_count} 条 [!]"
    else
        echo "  历史违规记录: 0 条"
    fi
    echo ""

    # ---- Verifier ----
    local ve_phase_ts ve_phase_text ve_wait m_count
    ve_phase_ts=$(sed -n '1p' "$DUAL_DIR/verifier-phase.txt" 2>/dev/null)
    ve_phase_text=$(sed -n '2p' "$DUAL_DIR/verifier-phase.txt" 2>/dev/null)
    [ -z "$ve_phase_text" ] && ve_phase_text="(尚未开始)"
    ve_wait=$(read_file "$DUAL_DIR/.wait-elapsed-verifier" "0")
    m_count=$(count_entries "$DUAL_DIR/verifier-violation-log.txt")

    hr
    echo "Verifier（终端 B）"
    hr
    echo "  当前阶段: $ve_phase_text"
    [ -n "$ve_phase_ts" ] && echo "  阶段更新于: $(seconds_ago "$ve_phase_ts")"
    echo "  累计等待: ${ve_wait}s"
    if [ "$m_count" -gt 0 ] 2>/dev/null; then
        echo "  历史漏判记录: ${m_count} 条 [!]"
    else
        echo "  历史漏判记录: 0 条"
    fi
    echo ""

    # ---- 任务摘要 ----
    hr
    echo "任务"
    hr
    head -c 200 "$DUAL_DIR/task.txt" 2>/dev/null | sed 's/^/  /'
    echo ""
    echo ""

    # ---- 最近事件 ----
    hr
    echo "最近事件（最多 10 条）"
    hr
    if [ -s "$DUAL_DIR/event-log.txt" ]; then
        tail -10 "$DUAL_DIR/event-log.txt" | sed 's/^/  /'
    else
        echo "  （暂无）"
    fi
    echo ""

    # ---- 需要关注 ----
    hr
    echo "需要关注"
    hr
    local flagged=0
    local escalate="${WAIT_ESCALATE_SECONDS:-300}"
    if [ "$w_wait" -ge "$escalate" ] 2>/dev/null; then
        echo "  [!] Worker 已等待 ${w_wait}s，超过升级阈值（${escalate}s），检查 Verifier 终端是否卡住"
        flagged=1
    fi
    if [ "$ve_wait" -ge "$escalate" ] 2>/dev/null; then
        echo "  [!] Verifier 已等待 ${ve_wait}s，超过升级阈值（${escalate}s），检查 Worker 终端是否卡住"
        flagged=1
    fi
    case "$limit" in
        ''|*[!0-9]*) : ;;  # limit.txt 还不存在（Verifier 尚未启动）或内容非法，跳过这项检查
        *)
            case "$iteration" in
                ''|*[!0-9]*) : ;;
                *)
                    if [ "$iteration" -ge "$((limit - 1))" ] && [ "$status" != "APPROVED" ] && [ "$status" != "REJECTED" ]; then
                        echo "  [!] 迭代已接近上限（${iteration}/${limit}），下一轮可能是强制终局判断"
                        flagged=1
                    fi
                    ;;
            esac
            ;;
    esac
    if [ "$v_count" -gt "$PREV_V_COUNT" ] 2>/dev/null; then
        echo "  [!] Worker 违规记录新增了 $((v_count - PREV_V_COUNT)) 条，见上方 violation-log.txt"
        flagged=1
    fi
    if [ "$m_count" -gt "$PREV_M_COUNT" ] 2>/dev/null; then
        echo "  [!] Verifier 漏判记录新增了 $((m_count - PREV_M_COUNT)) 条，见上方 verifier-violation-log.txt"
        flagged=1
    fi
    if [ "$flagged" -eq 0 ]; then
        echo "  （暂无）"
    fi
    PREV_V_COUNT=$v_count
    PREV_M_COUNT=$m_count

    # ---- 终态详情：状态为 NEEDS_FIX/REJECTED/APPROVED 时附报告摘要 ----
    case "$status" in
        NEEDS_FIX|REJECTED|APPROVED)
            echo ""
            hr
            case "$status" in
                NEEDS_FIX) echo "最新审查报告摘要（需要修正）" ;;
                REJECTED)  echo "最新审查报告摘要（已驳回）" ;;
                APPROVED)  echo "最新审查报告摘要（已通过）" ;;
            esac
            hr
            tail -c 800 "$DUAL_DIR/verifier-report.txt" 2>/dev/null | sed 's/^/  /'
            if [ "$status" = "APPROVED" ] && [ "$m_count" -gt 0 ] 2>/dev/null; then
                echo ""
                echo "  [!] 这次 Verifier 有历史漏判记录，APPROVED 之后不会再有下一轮复查，"
                echo "      建议人工抽查一遍再彻底放心"
            fi
            ;;
    esac
    echo ""
}

# ---- 主循环 ----

LAST_FP=""
while true; do
    FP=$(fingerprint)
    if [ "$FP" != "$LAST_FP" ]; then
        render
        LAST_FP="$FP"
    fi
    sleep 1
done
