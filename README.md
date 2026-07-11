# Dual Terminal Skill - 双终端协作模式

> **进程级隔离的双模型架构** — Worker 和 Verifier 运行在两个完全独立的终端中，通过文件系统状态机协调，把"审查是否走过场"的风险从技术上的自我偏袒，转移成协议纪律问题。具体哪些是技术保证、哪些只是协议约定，见下方"防作弊原理"一节的诚实说明。

---

## 目录

- [架构概述](#架构概述)
- [核心优势](#核心优势)
- [文件结构](#文件结构)
- [安装步骤](#安装步骤)
- [使用流程](#使用流程)
- [状态机说明](#状态机说明)
- [等待机制说明](#等待机制说明)
- [防作弊原理](#防作弊原理)
- [Verifier 问责机制](#verifier-问责机制)
- [v3：真实项目复盘带来的修复](#v3真实项目复盘带来的修复)
- [故障排查](#故障排查)
- [自定义配置](#自定义配置)
- [架构原理（深入）](#架构原理深入)
- [附录：这套框架里人最好在哪些地方介入](#附录这套框架里人最好在哪些地方介入)

---

## 架构概述

```
  +-- .dual-claude/ (shared files) ------------------------+
  |  status.txt  task.txt  plan.md  worker-output.txt      |
  |  verifier-report.txt  iteration.txt  limit.txt         |
  |  violation-log.txt  event-log.txt  no-blocker-streak   |
  +---------------------------+---------------------------+
                              |
              +---------------+---------------+
              |               |               |
              v               |               v
  +---------------------------+---------------------------+
  |  Worker (Terminal A)      |  Verifier (Terminal B)    |
  |                           |                           |
  |  while true loop          |  while ITER < LIMIT       |
  |                           |                           |
  |  1.read task+violations   |  1.wait for Worker        |
  |  2.plan milestones        |  2.read output+verify     |
  |  3.checkpoint             |  3.cross-check+review     |
  |  4.code by milestone      |  4.update blocker count   |
  |  5.verify changes landed  |  5.write report+check     |
  |  6.submit+wait review     |  6.bump iteration+done    |
  |  7.read report+decide     |                           |
  +---------------------------+---------------------------+
                              |
              +---------------+---------------+
              |   2 independent AI sessions   |
              |   communicate via files only  |
              +-------------------------------+
```

> **关键设计**：两个终端的 Claude 实例**完全不共享内存、上下文或进程**。它们只通过 `.dual-claude/` 目录下的文本文件进行异步通信。

> **关于隔离性的诚实说明**：进程级隔离是真实的——两个终端确实是两个独立的 Claude Code 会话，互相看不到对方的上下文。但 `.dual-claude/status.txt` 只是一个普通文本文件，没有任何操作系统级的权限隔离、加锁或签名校验。Worker 在技术上完全可以直接写入 `APPROVED`。这套方案能防住"自我偏袒"，靠的是协议纪律（两个 skill 文件里明确写了谁能写什么），而不是无法绕过的技术屏障。真正让它比单模型可靠的地方是：**没有任何一个模型实例同时控制"审查者看到什么"和"审查结果如何呈现给你"**——而不是"内存不共享"本身（Claude Code 的 subagent 其实也有独立 context，详见下方对比表说明）。

---

## 核心优势

| 特性 | 双终端 | Subagent | 单模型 |
|------|--------|---------|--------|
| **进程隔离** | ✅ 真正独立进程 | ✅ 独立 context（同一 CLI 内） | ❌ 同一实例 |
| **上下文隔离** | ✅ 互不可见 | ✅ Subagent 本身有独立 context | ❌ 完全共享 |
| **编排控制权** | ✅ 分散在两个独立会话 + 人类 | ⚠️ 单一父级实例控制子任务的 prompt 构造与结果转述 | ❌ 单一实例 |
| **模型权重隔离** | ✅ 可配置不同模型 | ⚠️ 通常同一模型实例 | ❌ 同一模型 |
| **Worker 绕过审查的技术门槛** | 需主动违反协议（无 OS 级强制） | 父级实例可单方面构造/转述审查结果 | 无隔离，风险最高 |
| **自动化程度** | ⚠️ 需人工/脚本协调 | ✅ 内置调度 | ✅ 完全自动 |
| **适用场景** | 高 stakes 代码审查 | 日常开发 | 简单任务 |

**关于和 Subagent 的真实差异**：Claude Code 的 subagent 本身也运行在独立的 context 窗口里，"同一进程共享内存"不是它的真实弱点。真正的风险点是：subagent 的审查 prompt 由父级实例构造、审查结果也由父级实例读取后转述给你——如果父级实例本身有偏向（不管是有意还是无意），它可以在"喂给审查者看什么"和"把审查结果说成什么"这两个环节动手脚，而你未必能察觉。双终端方案的价值在于**去掉了这个单点**：人类分别启动两个会话、分别输入指令，没有一个模型实例同时握着"构造审查输入"和"转述审查输出"这两把钥匙。这是关于*控制权归属*的论证，不是关于*内存是否共享*的论证。

---

## 文件结构

解压后你会得到以下文件：

```
dual-terminal-skill/
├── SKILL-worker.md              # Worker 的 Skill 定义
├── SKILL-verifier.md            # Verifier 的 Skill 定义
├── scripts/
│   ├── start-dual-terminal.sh   # 初始化脚本
│   ├── watch-status.sh          # 状态监控脚本（结构化仪表盘）
│   ├── reset.sh                 # 重置脚本
│   ├── wait-for-status.sh       # 有界轮询等待脚本（Worker/Verifier 共用，两级超时）
│   ├── set-status.sh            # 状态原子写入脚本（同时记录事件到 event-log.txt）
│   ├── bump-iteration.sh        # 迭代计数原子递增脚本（Verifier 用）
│   ├── log-verifier-miss.sh     # 记录 Verifier 漏判脚本
│   ├── checkpoint.sh            # 创建回滚点（Worker 改代码前调用）
│   ├── rollback-help.sh         # 打印回滚指引（不自动执行）
│   ├── set-task.sh              # 更新 task.txt 并自动归档旧版本
│   ├── next-round.sh            # 同一项目开始新一轮需求（set-task+reset的组合，保留信誉记录）
│   ├── track-blocker-streak.sh  # 追踪"连续无新增[阻塞]问题"轮数
│   └── heartbeat.sh             # Worker/Verifier 阶段上报，供 watch-status.sh 展示"两端在干什么"
├── README.md                    # 本文件
└── .gitignore                   # Git 忽略规则（忽略运行时生成的 .dual-claude/）
```

**安装到你的项目后**的结构：

```
your-project/
├── .claude/
│   └── skills/
│       ├── worker-terminal.md      ← 从 SKILL-worker.md 复制
│       └── verifier-terminal.md    ← 从 SKILL-verifier.md 复制
│
├── scripts/                         ← 从 scripts/ 整个目录复制（13 个脚本）
│   ├── start-dual-terminal.sh
│   ├── watch-status.sh
│   ├── reset.sh
│   ├── wait-for-status.sh
│   ├── set-status.sh
│   ├── bump-iteration.sh
│   ├── log-verifier-miss.sh
│   ├── checkpoint.sh
│   ├── rollback-help.sh
│   ├── set-task.sh
│   ├── next-round.sh
│   ├── track-blocker-streak.sh
│   └── heartbeat.sh
│
├── .dual-claude/                    ← 运行时自动生成，项目根目录下（不在 scripts/ 内）
│   ├── status.txt
│   ├── created_at.txt              ← start-dual-terminal.sh 创建的启动时间（供参考，各脚本不读取）
│   ├── task.txt
│   ├── task-history.md             ← task.txt 的历史版本归档（跨任务永久保留，set-task.sh 维护）
│   ├── plan.md                     ← 里程碑清单（Worker 第一轮写出，Verifier 逐个确认勾选，set-task.sh 换任务时自动归档重置）
│   ├── plan-history.md             ← plan.md 的历史版本归档（set-task.sh 维护）
│   ├── worker-output.txt
│   ├── verifier-report.txt
│   ├── verifier-report-round-N.txt ← 每轮审查报告的归档副本，供 Verifier 交叉核对自己上一轮的结论
│   ├── iteration.txt
│   ├── limit.txt                   ← 本次审查的迭代上限（Verifier 步骤0写入，watch-status.sh 展示用）
│   ├── violation-log.txt           ← Worker 每轮开头强制读取的历史违规记录
│   ├── verifier-violation-log.txt  ← Verifier 每轮开头强制读取的历史漏判记录
│   ├── no-blocker-streak.txt       ← 连续无新增[阻塞]问题轮数（track-blocker-streak.sh 维护，每任务重置）
│   ├── checkpoint-count.txt        ← 回滚点计数（跨任务永久递增，checkpoint.sh 维护）
│   ├── checkpoints/round-N-*/      ← 非 git 项目的文件快照（git 项目则用 tag，不占用这个目录）
│   ├── worker-phase.txt            ← Worker 当前阶段（heartbeat.sh 维护）
│   ├── verifier-phase.txt          ← Verifier 当前阶段（heartbeat.sh 维护）
│   ├── event-log.txt               ← 状态转移历史（set-status.sh 自动追加，每任务重置）
│   ├── .wait-elapsed-worker        ← Worker 侧累计等待秒数（wait-for-status.sh 维护）
│   └── .wait-elapsed-verifier      ← Verifier 侧累计等待秒数
│
├── README.md                        ← 可选，复制过来参考用
├── .git/                            ← 项目本来没有 git 的话，start-dual-terminal.sh 会自动创建（可用 DUAL_CLAUDE_NO_GIT_INIT=1 跳过）
└── .gitignore                       ← start-dual-terminal.sh 自动追加 `.dual-claude/` 进去（幂等，不会重复追加），不需要手动从 skill 包里复制这一份
```

---

## 安装步骤

### 第一步：放置 Skill 文件

```bash
# 在你的项目根目录执行
mkdir -p .claude/skills

# 复制 Skill 文件到 Claude Code 的 skills 目录
cp SKILL-worker.md .claude/skills/worker-terminal.md
cp SKILL-verifier.md .claude/skills/verifier-terminal.md
```

> **注意**：文件名必须是 `worker-terminal.md` 和 `verifier-terminal.md`，Claude Code 才能识别。

### 第二步：放置脚本文件

```bash
# 复制脚本到项目根目录（13 个脚本一次性全部复制，不要漏）
mkdir -p scripts
cp scripts/*.sh scripts/

# 赋予执行权限
chmod +x scripts/*.sh
```

> **注意**：`start-dual-terminal.sh` 会用自身所在路径的上一级目录作为项目根
> 目录来创建 `.dual-claude/`，所以它必须放在项目根下的 `scripts/` 子目录里
> （而不是项目根目录本身），否则 `.dual-claude/` 会被创建到错误的位置。按上面
> 的路径复制即可，不需要额外处理。

### 第三步：验证安装

```bash
# 检查文件是否存在
ls -la .claude/skills/worker-terminal.md
ls -la .claude/skills/verifier-terminal.md
ls -la scripts/

# 预期能看到 scripts/ 下有 13 个脚本：
# start-dual-terminal.sh  watch-status.sh  reset.sh  wait-for-status.sh
# set-status.sh  bump-iteration.sh  log-verifier-miss.sh
# checkpoint.sh  rollback-help.sh  set-task.sh  next-round.sh
# track-blocker-streak.sh  heartbeat.sh
```

---

## 使用流程

### 准备阶段

```bash
# 进入你的项目目录
cd your-project

# 初始化双终端环境（带任务描述）
bash scripts/start-dual-terminal.sh "帮我写一个 JWT 认证中间件"

# 或者从文件加载任务
# bash scripts/start-dual-terminal.sh task.md
```

输出示例：
```
==========================================
  双终端协作模式 - 初始化
==========================================

✅ 已创建任务描述

==========================================
  环境初始化完成
==========================================

共享目录: /your-project/.dual-claude
当前状态: IDLE
迭代次数: 0

------------------------------------------
  终端 A (Worker)
------------------------------------------
  1. 打开新终端窗口/标签页
  2. cd /your-project
  3. 启动 Claude Code: claude
  4. 加载 Skill: 开始工作
  5. 按 Skill 指引执行

------------------------------------------
  终端 B (Verifier)
------------------------------------------
  1. 打开新终端窗口/标签页
  2. cd /your-project
  3. 启动 Claude Code: claude
  4. 加载 Skill: 开始审查
  5. 按 Skill 指引执行
```

> **同一个项目，审查完一版，想给新一轮需求继续做，不想推倒重来？** 用
> `bash scripts/next-round.sh "<新一轮的目标>"`。它做两件事：更新
> `task.txt`（旧内容自动归档到 `task-history.md`），同时把 `status.txt`/
> `iteration.txt`/`no-blocker-streak.txt` 归零，但**保留**
> `violation-log.txt`/`verifier-violation-log.txt` 这两份信誉记录——单独
> 只用 `set-task.sh` 不够：`iteration.txt` 会停在上一轮结束时的值，如果正
> 好等于 LIMIT，Verifier 的循环条件直接为假，新一轮审查会一次都不执行；
> 单独用 `reset.sh` 又会把 `task.txt` 和两份信誉记录一起清空，不是这个场
> 景想要的。真要连信誉记录都清空、彻底重来，才用 `reset.sh`。

### 终端 A - Worker 执行

**打开新终端窗口**（不要关闭初始化终端）：

```bash
cd your-project
claude
```

在 Claude Code 中说出：

```
开始工作
```

Claude 会自动：
1. 读取 `.dual-claude/task.txt` 中的任务，以及 `.dual-claude/violation-log.txt` 中的历史违规记录（每轮循环开头都会重新读一次）
2. 创建回滚点（`checkpoint.sh`，git 仓库自动 commit + tag，非 git 项目自动快照）
3. 查看项目相关文件
4. 生成代码
5. 将输出写入 `.dual-claude/worker-output.txt`
6. 将状态设置为 `WORKER_DONE`
7. 进入有界轮询等待 Verifier 审查（详见"等待机制说明"一节，不会一次性阻塞几十分钟）

**Worker 终端输出示例**：
```
[Worker] 读取任务: 帮我写一个 JWT 认证中间件
[Worker] 查看项目上下文...
[Worker] 生成代码...
[Worker] 写入输出文件...
[Worker] 设置状态: WORKER_DONE
[Worker] 等待 Verifier 审查...
```

### 终端 B - Verifier 执行

**打开另一个新终端窗口**：

```bash
cd your-project
claude
```

在 Claude Code 中说出：

```
开始审查
```

Claude 会自动：
1. 检测到状态为 `WORKER_DONE`
2. 读取 `.dual-claude/worker-output.txt`
3. 以批判性视角审查代码
4. 将审查报告写入 `.dual-claude/verifier-report.txt`
5. 将结论写入状态文件（`NEEDS_FIX` / `APPROVED` / `REJECTED`）

**Verifier 终端输出示例**：
```
[Verifier] 检测到状态: WORKER_DONE
[Verifier] 读取 Worker 输出...
[Verifier] 独立审查中...
[Verifier] 发现问题: JWT_SECRET 未做非空检查
[Verifier] 写入审查报告...
[Verifier] 设置状态: NEEDS_FIX
```

### 终端 A - Worker 读取结果

Worker 检测到状态变为 `NEEDS_FIX` / `APPROVED` / `REJECTED`，自动读取审查报告：

```
[Worker] 检测到状态: NEEDS_FIX
[Worker] 读取审查报告...
[Worker] 审查结果: NEEDS_FIX
[Worker] 修正建议: 添加 JWT_SECRET 非空检查
[Worker] 修正代码...
[Worker] 重新提交...
```

> Worker 不关心迭代次数，只看状态：APPROVED 就退出，NEEDS_FIX 就继续修，REJECTED 就重来。

### 循环直到通过

```
Worker 提交 → Verifier 审查 → NEEDS_FIX → Worker 修正 → Verifier 审查 → APPROVED
```

由用户指定的迭代次数，超过则人工介入。

### 终端 C - 监控状态（长任务强烈建议开，不只是"可选"）

```bash
bash scripts/watch-status.sh
```

v3.3 之前这只是个"status.txt 变了就打印一行"的简单脚本。真实长会话（68/71
轮）复盘发现，Worker/Verifier 自己的轮询纪律在长会话里会衰减——多次出现需要
用户提醒"你倒是看看反馈报告"的情况。这件事光靠改 SKILL 文件里的文字指令解决
不了，比较现实的办法是人在第三个终端主动盯着一份信息足够完整的仪表盘，而不
是完全指望两端自己一直记得轮询。现在的 `watch-status.sh` 是照这个方向重写
的，每秒检查一次是否有变化，有变化才重绘（不刷屏），输出示例：

```
双终端协作监控        刷新: 14:33:55   (Ctrl+C 退出)

--------------------------------------------
状态机
--------------------------------------------
  当前状态: NEEDS_FIX       迭代: 2 / 5
  连续无新增[阻塞]轮数: 0

--------------------------------------------
Worker（终端 A）
--------------------------------------------
  当前阶段: 等待 Verifier 审查中
  阶段更新于: 3s前
  累计等待: 12s
  已创建回滚点: 2 个
  历史违规记录: 0 条

--------------------------------------------
Verifier（终端 B）
--------------------------------------------
  当前阶段: 审查中 - 核验测试断言/mock语义/根因
  阶段更新于: 8s前
  累计等待: 0s
  历史漏判记录: 1 条 [!]

--------------------------------------------
任务
--------------------------------------------
  修复棋盘坐标偏移，标签与边框重叠的问题...

--------------------------------------------
计划进度
--------------------------------------------
  里程碑: 2 / 5 已完成
  当前: M3: 棋盘外框 padding 重新计算

--------------------------------------------
最近事件（最多 10 条）
--------------------------------------------
  14:32:10 [Worker] IDLE -> WORKER_DONE (iter=0)
  14:32:45 [Verifier] WORKER_DONE -> NEEDS_FIX (iter=1)
  14:33:20 [Worker] NEEDS_FIX -> WORKER_DONE (iter=1)

--------------------------------------------
需要关注
--------------------------------------------
  （暂无）
```

`需要关注`区块会在这些情况下报警：一方累计等待超过升级阈值（默认5分钟）、
迭代已接近上限、违规/漏判记录出现新增条目。状态为 `NEEDS_FIX`/`REJECTED`/
`APPROVED` 时会在最下方附最新审查报告摘要；`APPROVED` 且这次 Verifier 有历
史漏判记录时，会额外提示"建议人工抽查一遍再彻底放心"。

Worker/Verifier 在关键步骤会调用 `heartbeat.sh` 上报当前阶段（"生成代码中"
"等待审查中"这种），这就是仪表盘里"当前阶段"这一栏的数据来源——没有这个，
`status.txt` 不变的时候完全看不出两端各自在干嘛，是在正常工作还是卡住了。

---

## 状态机说明

```
                    ┌─────────────────┐
                    │      IDLE       │
                    │   (等待开始)     │
                    └────────┬────────┘
                             │
                             │ Worker 开始工作
                             ↓
                    ┌─────────────────┐
                    │   WORKER_DONE   │
                    │  Worker 已提交   │
                    └────────┬────────┘
                             │
                             │ Verifier 开始审查
                             ↓
              ┌──────────────────────────┐
              │     NEEDS_FIX /          │
              │  APPROVED / REJECTED     │
              │  Verifier 写入结论       │
              └────────┬─────────────────┘
                       │
              ┌────────┼──────────┐
              │        │          │
              ↓        ↓          ↓
        ┌─────────┐ ┌──────┐ ┌─────────┐
        │APPROVED │ │NEEDS_│ │REJECTED │
        │  通过   │ │ FIX  │ │  重做   │
        └─────────┘ └──┬───┘ └─────────┘
                       │          │
                       │          │
                       ↓          ↓
                  ┌─────────┐ ┌─────────┐
                  │Worker 修│ │重新理解 │
                  │正后提交 │ │  任务   │
                  └────┬────┘ └────┬────┘
                       │           │
                       └─────┬─────┘
                             │
                             ↓
                    ┌─────────────────┐
                    │   WORKER_DONE   │
                    │   (循环开始)     │
                    └─────────────────┘

                    迭代达到上限时：
                    Verifier 在最后一轮只给出 APPROVED 或 REJECTED
```

| 状态 | 含义 | 谁可以操作 |
|------|------|----------|
| `IDLE` | 等待 Worker 开始 | 仅 reset.sh |
| `WORKER_DONE` | Worker 已提交，等待审查 | 仅 Worker |
| `NEEDS_FIX` | 需要 Worker 修正 | 仅 Verifier |
| `APPROVED` | 审查通过，任务完成 | 仅 Verifier |
| `REJECTED` | 严重问题，需要重新理解任务 | 仅 Verifier |

> 上面"谁可以操作"是协议约定，不是文件权限强制——详见下方"防作弊原理"一节。

---

## 等待机制说明

Worker 和 Verifier 都需要"等对方一个动作"：Worker 提交后要等 Verifier 给结
论，Verifier 要等 Worker 提交。v1 版本这两处都是直接写 `while [ status != X ];
do sleep 10; done`，让模型把它当成一次性执行到底的阻塞命令。这个写法在真实
使用中不稳定，尤其是 Worker 这一侧的等待——它等的不只是"Verifier 算得快不
快"，还包括"人类去开第二个终端、启动 Claude Code、敲下'开始审查'"这一整段
纯人工操作的耗时，短则几分钟，长则可能几十分钟。

Claude Code 的 Bash 工具对单次命令执行时长有上限（文档标称默认 2 分钟、显式
指定 timeout 最多可申请到 10 分钟，不同环境下实际生效的上限可能更保守）。如
果把"等对方"这件事塞进一次阻塞调用里，等待时间一旦超过这个上限，命令会被系
统直接杀掉，轮询链条就断在那里，而不是优雅地重试。

v2 版把等待拆成 `scripts/wait-for-status.sh`：

- 单次调用最多阻塞约 **90 秒**（明显低于已知的超时上限），到点即返回，不会
  被系统腰斩。
- 返回码 `0`：已等到目标状态，可以继续。
- 返回码 `1`：这一轮窗口内还没等到，属于正常情况，调用方在自己的循环里再
  调一次即可（SKILL 文件里已经写好了这个重试外层循环）。
- 返回码 `2`：**跨调用累计**已等待时间超过硬性上限（默认 **1800 秒 / 30
  分钟**，可用环境变量 `WAIT_HARD_CAP_SECONDS` 调整），此时不应该继续傻等，
  应该停下来提示人类去检查对方终端是不是卡住或者根本没启动。

实测下来发现"Verifier 长时间无响应"其实是常态（不是偶发），而 v2 最初的设计
只有"正常轮询"和"硬上限断开"两档，中间没有过渡——真等到 30 分钟硬上限才提醒
人，黄花菜都凉了。v3 加了中间档：累计等待超过 **300 秒 / 5 分钟**（可用
`WAIT_ESCALATE_SECONDS` 调整）时，返回码仍然是 `1`（还没到必须停下来的地步，
继续轮询），但输出信息会变成 `TIMEOUT_ESCALATE` 开头，并且往 stderr 发一个
响铃字符（`\a`）。SKILL 文件里已经写了：看到这个信息，Worker/Verifier 会顺手
提醒用户去看一眼对方终端，不为此中断轮询——是"顺手说一声"，不是"停下来"。

三档超时小结：**90 秒**单次调用上限（躲避系统超时）→ **5 分钟**升级提醒（顺
手喊人，继续等）→ **30 分钟**硬上限（真正停下来）。

累计等待时长记录在 `.dual-claude/.wait-elapsed-worker` /
`.wait-elapsed-verifier` 里，跨多次调用持久化，一旦等到目标状态或者
`reset.sh` 执行后会清零。两个角色的计数器分开存放，互不影响。

---

## 防作弊原理

### Worker 有没有能力作弊？有。这套方案防的是什么？（诚实说明）

先说清楚：`.dual-claude/` 下的所有文件都是普通文本文件，Worker 的 Bash 工具
理论上可以直接 `echo APPROVED > .dual-claude/status.txt`，没有任何操作系统权
限、文件锁或签名机制能阻止这件事。**这套方案不提供技术上"不可能"的保证**，
它提供的是：

| 作弊方式 | 实际情况 | 这套方案做了什么 |
|---------|------------|---------|
| **伪造审查结果** | 技术上做不到——Worker 在终端 A，物理上看不到终端 B 里 Verifier 的推理过程和输出，没东西可伪造 | 真正靠上下文隔离防住的唯一一项 |
| **跳过审查** | 技术上可以（直接写 APPROVED / 甚至跳过整个流程直接改代码），但需要主动违反 skill 文件里写明的规则 | 状态机 + `set-status.sh` 的取值校验能防"手滑写错状态"，防不住"故意违规" |
| **篡改审查报告** | Worker 在技术上可以直接编辑 `verifier-report.txt`（skill 文件明确禁止，但没有文件权限强制） | 属于协议纪律，不是技术屏障 |
| **影响 Verifier 判断** | 两个终端完全独立，Worker 无法访问 Verifier 的进程/内存/prompt——这一条是真的做不到 | 真正靠隔离防住的另一项 |
| **隐藏已知问题** | Verifier 若只采信 WORKER_REPORT 的自我声明、不做实际核实，隐瞒是可以蒙混过去的 | v2 版 Verifier skill 要求对能核实的项目实际验证，并把发现的隐瞒写入 `violation-log.txt`，供 Worker 下一轮强制读取 |

真正被技术手段锁死、而不只是靠协议纪律的，只有两条：**Worker 看不到 Verifier
的推理过程**，以及**Worker 无法在 Verifier 生成结论的当下影响它**。除此之
外的所有防线，都是"skill 文件写清楚规则 + 两个独立会话之间没有单一控制点能
同时操纵输入和输出"，靠的是让作弊的操作成本和被发现的代价变高，而不是让作弊
在物理上不可能。如果你需要的是后者，唯一办法是给 `.dual-claude/` 加真正的文
件权限隔离（比如让两个终端用不同的系统用户运行，状态文件只对特定用户可写）
——这套 skill 目前没有做到这一步。

### 隔离性对比

```
单模型（一个 Claude）:
  ┌─────────────────┐
  │   Claude Code   │
  │  Worker + Verifier │  ← 同一上下文，容易自我偏袒
  └─────────────────┘

Subagent（同一父级实例编排）:
  ┌─────────────────┐
  │   父级 Claude    │
  │  ┌───┐  ┌───┐  │
  │  │W  │  │V  │  │  ← W/V 各有独立 context，但
  │  └───┘  └───┘  │     父级实例构造两者的 prompt、
  └─────────────────┘     并转述 V 的结论给你——单点

双终端（独立进程）:
  ┌─────────┐   ┌─────────┐
  │ Claude  │   │ Claude  │
  │ Terminal│   │ Terminal│  ← 完全独立，不共享任何资源
  │    A    │   │    B    │
  └─────────┘   └─────────┘
       │              │
       └──────┬───────┘
              ↓
        .dual-claude/  ← 仅通过文件系统通信
```

---

## Verifier 问责机制

### 为什么 Verifier 比 Worker 更容易偷懒

这是实测中观察到的一个现象，值得说清楚原因，因为它决定了下面这套机制为什么
这样设计，而不是简单复制 Worker 那一套。

- **生成任务有下限约束，审查任务没有。** Worker 哪怕偷懒，也得交出一个能看
  的东西——代码总得存在，偷懒会直接变成看得见的残缺。Verifier 的偷懒和"认真
  查过、确实没问题"在输出层面是同一个东西：一份写着 `PASS` 的报告。你没法
  从"没找到问题"的报告里分辨它是真没问题，还是没认真找。
- **"通过"是认知上更省力的默认选项。** 找出一个具体问题需要定位证据、组织
  论述、给出修正建议——是主动生成内容的路径。给 `PASS` 不需要生成任何新东
  西，只需要不反对。这跟对话中的讨好倾向是同一个根：审查者角色要求模型输出
  摩擦性内容（"这里错了"），这和它默认的合作、友善姿态是逆着来的。
- **后果不对称，而且是单向的。** Worker 偷懒被抓到，还有下一轮机会重写。
  Verifier 偷懒放水，只要 Worker 没有更严格的下一道关卡去发现，这一轮的错
  误批准就永久沉没了——没有任何机制让 Verifier 自己"承担"这个后果。

三条原因本质上都在说同一件事：Worker 的偷懒会自动暴露、自动付出代价；
Verifier 的偷懒不会。下面的机制就是专门把这个原本沉没的后果，重新接回
Verifier 身上。

### 机制设计

对称于 Worker 侧的 `violation-log.txt`，Verifier 侧有 `verifier-violation-
log.txt`，记录 Verifier 自己的历史漏判，每轮循环开头强制读取（不能只在开始
时读一次）：

- **归档每一轮的审查报告**：`verifier-report.txt` 会被同步复制一份到
  `verifier-report-round-N.txt`，保留完整的历史记录。
- **交叉核对**：从第 2 轮开始，Verifier 在审查前会先对照上一轮归档的报告，
  检查这一轮发现的问题里，有没有哪条其实上一轮就该抓到、却被标了 `PASS`。
  这是一个**可核实的客观信号**，不依赖 Verifier 主动坦白——如果上一轮说
  `PASS`、这一轮在同一处发现问题，这就是证据确凿的漏判。
- **人工/Worker 也能记录**：`scripts/log-verifier-miss.sh "<描述>"` 可以由
  人类事后发现某次 `APPROVED` 判错时手动调用，也可以由 Worker 在发现
  Verifier 明显没检查自己已经坦白过的风险点时调用。
- **VERIFIER_REPORT 里加了对称的直接追问**：仿照对 Worker 有效的"是否偷工
  减料+后果声明"手法，要求 Verifier 在给出结论前，直接回答"是否放过了某个
  有怀疑但没深究的地方"，并明确 `APPROVED` 是终局判断、没有下一轮补救机会，
  比判错 `NEEDS_FIX` 的代价更重。

### 这个机制解决不了什么

- 如果 `APPROVED` 之后任务直接结束、也没有下一轮任务在同一处代码上做交叉
  核对，那次漏判可能永远不会被自动发现——`log-verifier-miss.sh` 提供的是
  事后人工补记的入口，不是自动审计。这套 skill 的范围是单次任务的生命周期，
  不含跨任务、跨会话的自动追踪。
- 交叉核对依赖"问题出现在同一处代码"这种可比对的情形；如果 Verifier 两轮
  漏判的是完全不同的两个地方，交叉核对机制本身抓不到，只能靠 Verifier 自己
  的直接追问环节起作用——而这一环节终究还是自我报告，不是客观机制。

---

## v3：真实项目复盘带来的修复

v2 版发布后，用一个真实项目（双终端协作开发一个五子棋游戏，约 15 轮迭代）
跑了一遍，跑完做了复盘。v3 的改动全部来自这次复盘里实际发生过的问题，不是
纸面推演。

### Verifier 红线：永远不碰代码

复盘中发生过一次 Verifier 直接改代码的越权事件（改完才想起来该走流程）。
`SKILL-verifier.md` 里原来"不要偏袒 Worker"这类规则不够具体，没有专门针对
"顺手改一行"这种冲动的红线。v3 把这条单独列出来，并且写清楚了为什么不能有
例外：**一旦 Verifier 改过代码，就不再是独立第三方——审查的是自己参与生成
的东西，整个双终端隔离模型的信任基础就没了。** 这不是态度问题，是结构问题，
所以没有"这次很简单可以破例"这种情况。

### 三次真实漏判，同一个模式

复盘记录了三次漏判，模式完全一样：**看到一个可验证的数值（"22/22 通过"）→
数值本身没问题 → 停止思考**。针对这个模式，`SKILL-verifier.md` 加了三个
要求"必须产出具体内容"的强制步骤（不是自我报告式的是非题，写不出来就是没
做到）：

- **技术一·数值先翻译再采信**：聚合数值（"N/N 通过"）不能直接当证据，要先
  为每条测试写一句人话描述它实际在验证什么，再问覆盖了什么、漏了什么。复盘
  里的真实案例：一条叫"活二得分大于0"的测试，翻译出来发现测试数据 `[0,1,1,0]`
  实际是两端封堵的死二，测试名字和测试内容对不上。
- **技术二·mock 语义审计**：测试里出现 mock（`setTimeout`、DOM、网络请求等）
  时，光看测试跑通不够，要验证 mock 的行为语义和真实环境是否一致。复盘里的
  真实案例：`setTimeout` 被 mock 成立即同步执行，导致 `clearTimeout` 在测试
  环境里永远是对 `undefined` 调用、变成 no-op——"定时器被正确清理"这件事从
  设计上就测不出来，但测试全部通过。
- **技术三·根因三层问**：确认"已修复"时按顺序问——解决了报告的具体现象吗？
  根因是什么，打在根因上还是表层？有没有波及对称/关联维度？复盘里的真实
  案例：棋盘标签不与边框重叠了（表层现象解决），但没人检查过外框本身的
  padding 设计不合理、整体偏左 1 个格子（根因没碰），也没人检查过水平方向
  是否受同样问题影响（对称维度没查）。

### 记录不是防线

复盘里有一句话，直接推翻了 v2 对 `verifier-violation-log.txt` 的部分设计
预期：**"记录漏判、自我批评本身不是防线——它们制造了'已经处理过了'的心理
完结感，反而降低了后续的警觉。"** v3 保留了这套记录机制（客观的交叉核对信号
仍然有价值），但明确降级了它的定位：记录本身不是防线，上面那三个"必须产出
具体内容"的技术才是——因为具体内容写不出来是可核查的，自我报告的态度好不好
不是。

### 问题分级 + 收敛机制

"循环不要停止直至满意"这个要求在复盘的项目里造成了后 5 轮都在为坐标偏移
0.05 个格子这种细节反复打回，产品其实第 5 轮就已经完成了。v3 给每条发现的
问题强制标注 `[阻塞]` 或 `[细节]`，只有 `[阻塞]` 能触发 `NEEDS_FIX`/
`REJECTED`；新增 `scripts/track-blocker-streak.sh` 追踪"连续多少轮没有新增
阻塞问题"，连续 2 轮以上时倾向于结束循环，把细节问题列为后续建议而不是继续
挑。

### 终局判断三问

判 `APPROVED` 之前，`VERIFIER_REPORT` 里新增了三个必须写出具体内容的问题
（复盘里"5.4 对终局判断"的原话搬过来的）：如果现在判 APPROVED 最可能错在
哪里（写不出具体假设就不能判）、是否处于疲劳状态（标准是否已经漂移）、是否
有"差不多行了"的念头（有的话把 task.txt 里没确认过的需求重新过一遍）。第一
问尤其关键——它要求生成一个具体假设，这一点上是非题很好蒙混，具体假设蒙混
不了。

### 基础设施补丁：checkpoint、任务版本管理

三个纯粹是复盘里"根本没有对应机制"的缺口，不是规则问题：

- **`scripts/checkpoint.sh`**：Worker 每轮改代码之前自动调用。是 git 仓库就
  commit + 打 tag；不是就把项目文件快照到 `.dual-claude/checkpoints/`。只
  负责"存"，不负责"退"——回滚是有损操作，交给人自己决定。`rollback-help.sh`
  只打印现有回滚点和操作步骤，不自动执行任何 `git reset` 或覆盖文件的命令。
- **`scripts/set-task.sh`**：复盘里 `task.txt` 从 v1.0 一路 append 到 v3.0
  继续修订，新旧需求混在一起，Worker 和 Verifier 对"现在在改哪个问题"的理解
  经常对不上。这个脚本更新 `task.txt` 时会自动把旧内容归档到
  `task-history.md`，`task.txt` 永远只保留当前这一轮的目标。

### v3.1：`set-task.sh` 和 `reset.sh` 各管各的，单独用哪个都不对

发布后有人问了一句"`set-task.sh` 和 `reset.sh` 怎么协作"，一测发现真有问题：
单独用 `set-task.sh` 换新一轮需求时，`iteration.txt` 还停在上一轮结束时的
值——如果正好等于 `LIMIT`，Verifier 的 `while [ "$ITER" -lt "$LIMIT" ]` 循环
条件直接为假，新一轮审查一次都不会执行。单独用 `reset.sh` 又会把
`task.txt` 之外的东西全清，包括两份信誉记录，不是"换一批需求继续做"这个场
景想要的。

加了 `scripts/next-round.sh`，专门对应"同一个项目，新一轮需求，但历史信誉
记录还有参考价值"这个场景：内部是 `set-task.sh`（换任务）+
`reset.sh --keep-violation-logs`（归零 `status`/`iteration`/
`no-blocker-streak`，但跳过清空两份信誉记录和 `checkpoint-count.txt`）的组
合，顺序上先归档任务再重置状态，这样归档记录里"第 N 轮结束"用的是重置前的
真实轮次。`reset.sh` 本身新增了 `--keep-violation-logs` 这个可选参数，不加
参数时行为和以前完全一样。

### v3.2：`git init` 要不要自动做

v3.1 的说法是"这个脚本不会自己跑 `git init`"，理由是"避免给项目一个意外的
副作用"。这个理由站不住——`git init` 只创建 `.git/`，不碰任何已有文件，纯增
量、`rm -rf .git` 就能撤销，风险级别跟"回滚"、"覆盖文件"这类真正需要人把关的
有损操作完全不是一回事，之前把它们归到同一类需要谨慎的操作是判断错了。

`start-dual-terminal.sh` 现在默认行为：**项目不是 git 仓库时自动 `git init`**
（连带配置本地 `user.email`/`user.name`，用固定的
`dual-terminal-skill@local` 兜底，避免全新环境里 `git commit` 因为没配身份
直接报错退出）。已经是 git 仓库（包括嵌套在上级目录的仓库）就跳过，不会
重复初始化。真不想要，设置环境变量 `DUAL_CLAUDE_NO_GIT_INIT=1` 即可跳过，
`checkpoint.sh` 会自动退回文件快照模式。

**这个改动顺带暴露了一个和自动 init 无关、本来就存在的问题**：`checkpoint.sh`
的 `git add -A` 会把 `.dual-claude/` 自己的状态文件（`status.txt`、等待计数
器……）和真正的代码改动提交进同一个 commit——不管 git 是刚被自动初始化的，
还是项目本来就有，只要没配 `.gitignore`，这个问题都会发生（实测复现过：13 个
协调文件全部混进了一次普通代码改动的 commit 里）。现在 `start-dual-terminal.sh`
和 `checkpoint.sh` 都会检查并在需要时把 `.dual-claude/` 追加进项目的
`.gitignore`（幂等，不会重复追加），`checkpoint.sh` 里的检查是防御性兜底，
应对项目从旧版本升级上来、或者 `.gitignore` 后来被手动删掉的情况。

### v3.3：第一次真实长会话（68/71 轮）压力测试后的修复

前面几条修复都是在小规模验证下做的。这次是同一个项目分别产出的 Worker 侧
和 Verifier 侧自评报告（68 轮 vs 71 轮，两边独立统计，数字对不上，总分也是
自评、水分不小，但两份报告在**具体案例**上互相印证，下面的修复都是照具体
案例来的，不是照总分来的）。

**发现的核心模式**：把两份报告里"做得好"和"做得差"的项目分开看，靠脚本/
状态机强制的环节（`checkpoint.sh` 52 次基本每次都做、`set-status.sh` 从未被
绕过、Verifier 红线 10/10）全部扛住了；只靠 SKILL 文件里文字指令、指望模型
"记得做"的环节（步骤2.5 交叉核对 68 轮只做了 1 次、漏判记录只记了 1 条、
实测验证不到 5 次）全面衰减。这次修复的思路就是：**能变成强制步骤或者具体
触发条件的，都不再只是文字建议。**

- **实测验证具体化（技术四）**：复盘发现"自动化测试全部通过"和"这个改动
  被验证过了"被系统性划了等号——尤其是 UI/布局类改动，测试套件跑通只能
  证明没崩溃，证明不了呈现结果对不对。现在要求 Verifier 先判断改动类别，
  涉及 UI/视觉呈现的必须有一次实际观察验证（截屏、CDP 布局数据、或等价
  手段），报告里要贴具体观察到了什么，不能只写"已验证正常"。
- **REJECTED 触发条件具体化**：之前 REJECTED 和 NEEDS_FIX 只有"严重问题用
  REJECTED"这种描述性区分，两份报告都独立指出这导致 REJECTED 从未被真正
  用过（即使发生过"Worker 声称已修复但代码没改"这种情况）。现在有两条具体
  触发条件：Worker 报告与代码事实不符（诚信问题，直接 REJECTED）；同一个
  `[阻塞]` 问题连续 3 轮未解决（循环没在收敛，REJECTED 打断重启）。
- **步骤2.5（交叉核对）从建议改成强制读取**：之前只是文字描述"应该对照上
  一轮报告"，没有对应的强制读取动作，68 轮里实际只执行了 1 次。现在和读
  `violation-log.txt` 一样，是主循环里每轮（第2轮起）都要执行的显式
  `cat` 命令。
- **终局判断三问要求基于本轮实测**：复盘里最值得警惕的一条——早期两次
  APPROVED 都**写了**终局三问的具体内容，但依据的是推理不是实测，形式满足
  了、实质没满足。现在第一问（"最可能错在哪里"）明确要求基于本轮"实测记录"
  里实际做过的验证，纯推理写不出有依据的内容，不能判 APPROVED。
- **Worker 侧改动确认**：对应"Node.js 替换脚本静默失败，Worker 以为改了、
  代码其实没变"这个具体案例，提交前新增强制步骤——用 git diff 或 grep 确认
  改动真的落地，不能仅凭"脚本执行了、没报错"就认定修复完成。同时禁止
  "全流程正确执行"这类无法核实的笼统声明，WORKER_REPORT 新增"改动确认"栏，
  要求逐项写清楚怎么确认的。

**没有改脚本逻辑、诚实记录为已知局限的一条**：两份报告都独立提到 Verifier/
Worker 在长会话里会出现轮询纪律衰减，需要用户反复提醒才继续轮询。
`wait-for-status.sh` 的有界轮询设计已经是这套框架能做到的极限——它解决的是
"单次调用会不会被系统杀掉"，解决不了"模型会不会在自己的 agent loop 里持续
发起下一次调用"，这是长会话本身的连续性问题，不是轮询脚本设计得不够好。
比较现实的应对不是继续在轮询脚本上打补丁，而是把 `watch-status.sh` 提升为
长任务的推荐标准操作——人在第三个终端主动盯着一份信息完整的仪表盘，比完全
指望两端自己记得轮询更可靠。这也是"使用流程 → 终端 C"一节里 `watch-status.sh`
重写的直接动机。

### v3.4：Worker 和 Verifier 之间缺一个共同的工程计划

之前所有版本都有一个结构性缺口：Worker 从"读 `task.txt`"直接跳到"写代码"，
中间没有任何拆解/规划的环节。这会导致两种相反的失败模式——**"做到哪里算
哪里"**（没有整体规划，每轮想到什么改什么，没人知道"做完了"该是什么样）和
**"一次性做完不拆分"**（把整个任务糅成一次巨大的提交，Verifier 的举证式
审查在这种改动面下实际做不到位，技术一到技术四都会因为要看的东西太多而
被迫走过场）。之前加的"步进确认"指引想解决第二种，但只是一句软建议，没有
共同依据，两边各想各的。

新增 `.dual-claude/plan.md`：Worker 在新任务的第一轮，写代码之前，先把
`task.txt` 拆解成里程碑清单，每条都带具体、可核查的验收标准：

```markdown
# 项目计划

## 里程碑清单

- [ ] M1: hard 模式威胁检测重写
  验收标准: AI 能正确识别并阻止对手活三/冲四
- [ ] M2: AI 防守测试补全
  验收标准: 测试断言检查阻断位置而非仅返回值非空
```

**拆解粒度**：小到能一轮做完、独立提交、独立审查，不是"整个任务"，也不是
碎到没意义。任务本身足够小、就是一个原子性改动的，里程碑清单可以只有一条，
不强制拆分。

**职责分工延续了这套框架一贯的模式**：Worker 声明"我这轮做的是哪个里程碑"，
但不能自己勾选完成——完没完成由 Verifier 说了算（步骤 4.5：确认里程碑没有
`[阻塞]` 问题、达到验收标准，才把 `- [ ]` 改成 `- [x]`）。这跟"Worker 不能
自己设 APPROVED"是同一个道理：宣布"完成"这件事不能由做这件事的人自己说了
算。Verifier 编辑 `plan.md` 打勾不违反"永不碰代码"的红线——这是协调文档，
跟它已经在写的 `verifier-report.txt`、两份违规日志是同一类东西。

**这个机制同时防住两种失败模式**：防"一次性做完"靠的是 Verifier 核对"本轮
改动范围是否和声明的里程碑一致"（流程合规性检查项），夹带其他里程碑范围
的改动没有正当理由会被记录；防"做到哪里算哪里"靠的是把"计划完整性"变成
`APPROVED` 的硬性前提——终局判断三问加了第四问"plan.md 里的里程碑是不是
全部勾选了"，哪怕当前这个里程碑本身毫无问题，只要还有 `- [ ]` 没打勾，就
不能判 `APPROVED`。到达迭代上限但计划未完成时判 `REJECTED`，报告里会明确
写清楚"这不是质量问题，是范围没做完"，建议用户对剩余里程碑重新发起一轮
审查，不要把这种情况和"代码有严重问题"的 `REJECTED` 混为一谈。

`task.txt` 换了（不管是 `set-task.sh` 直接调用还是 `next-round.sh` 间接
触发），旧的 `plan.md` 大概率也不再适用，会被自动归档到 `plan-history.md`
并重置为待规划占位符——逼着 Worker 在新任务的第一轮重新拆解，而不是拿着对
不上号的旧计划继续走。`watch-status.sh` 仪表盘新增"计划进度"区块，展示
"里程碑 N/M 已完成"和当前在做哪一条，人在监控终端就能看出项目"做到哪了"，
不用去翻 `plan.md` 原文。

**这个机制没有解决的**：拆解质量本身仍然取决于 Worker 这一轮到底拆得好不好
——如果 Worker 把里程碑拆得过粗（比如整个任务就一条），效果跟没拆没什么
区别。Verifier 步骤 2.05 会核对里程碑范围，但审的是"这轮改动和声明的里程碑
是否一致"，不是"这份计划本身的颗粒度是否合理"——粒度合不合理目前还是要靠
人看一眼 `plan.md`，没有做成强制校验。

### 没有解决、也不打算装作解决的问题

**步进确认**（"改一项确认一项，不要混在一起提交"）复盘里也提到了，但这条
本质上取决于 task.txt 怎么描述任务、以及模型会不会自己拆分——`SKILL-worker.md`
加了一条指引，但这终究是引导不是强制，模型完全可能为了"看起来一次交差"而
无视它。这条改动做了，但不承诺它一定管用，效果不如上面几条确定。

**长会话本身的轮询/注意力连续性问题**——见上方 v3.3，这条明确记录为局限，
不是"下个版本会解决"的待办。

---

## 故障排查

### 问题 1: Worker 无法开始工作

**症状**: Claude 说找不到任务文件

**解决**:
```bash
# 检查 .dual-claude 目录是否存在
ls -la .dual-claude/

# 如果不存在，重新初始化
bash scripts/start-dual-terminal.sh "你的任务"
```

### 问题 2: Verifier 无法读取 Worker 输出

**症状**: Verifier 一直在等待

**检查**:
```bash
# 查看当前状态
cat .dual-claude/status.txt

# 应该是 WORKER_DONE，如果不是：
# 1. Worker 可能还没完成
# 2. 状态文件被意外修改

# 手动修复（谨慎使用，一律用 set-status.sh，不要直接 echo 重定向）
bash scripts/set-status.sh WORKER_DONE
```

### 问题 3: Worker 无法读取审查报告

**症状**: Worker 一直在等待

**检查**:
```bash
# 查看当前状态
cat .dual-claude/status.txt

# 应该是 NEEDS_FIX / APPROVED / REJECTED

# 如果 Verifier 已经完成但状态未更新：
cat .dual-claude/verifier-report.txt  # 查看报告内容
bash scripts/set-status.sh NEEDS_FIX  # 手动更新状态（或 APPROVED / REJECTED）
```

### 问题 4: 迭代次数达到上限，循环无法结束

**症状**: Verifier 到达第 N 轮（N 为你启动审查时口头指定的次数，未指定则默认
3）后仍然给不出确定结论

**解决**:
```bash
# 查看当前迭代次数
cat .dual-claude/iteration.txt

# 正常情况下，到达上限的那一轮 Verifier 必须直接判 APPROVED 或 REJECTED
# 二选一（v2 版已修复"到点自动 APPROVED"的漏洞，见 SKILL-verifier.md 的
# "最后一轮"逻辑）。如果 Verifier 仍然卡住给不出结论，人工介入：
# 1. 查看 Worker 输出、Verifier 报告和 violation-log.txt
# 2. 手动决定最终结果
# 3. 重置状态
bash scripts/reset.sh
```

### 问题 5: 状态混乱，想重新开始

**解决**:
```bash
# 重置所有状态，保留任务描述
bash scripts/reset.sh

# 输出：
# 🔄 重置双终端协作状态...
# ✅ 状态已重置
# 备份目录: .dual-claude/backup-20260706-143020
# 当前状态: IDLE
# 迭代次数: 0
```

### 问题 6: 等待轮询一直卡着不动 / 长时间没反应

**症状**: Worker 或 Verifier 反复提示"本轮窗口未等到目标状态"，或者干脆提示
"等待已超过硬性上限"后停下来了

**说明**: 这是 v2 版的预期行为，不是 bug。`wait-for-status.sh` 单次最多等待
约 90 秒就会返回一次结果，等不到会自己重试，这是为了避免撞上 Claude Code 单
次 Bash 命令的执行时长上限（详见"等待机制说明"一节）。如果连续等待累计超过
默认 30 分钟（可用 `WAIT_HARD_CAP_SECONDS` 环境变量调整），脚本会主动停止并
提示你去检查另一个终端：

```bash
# 检查另一个终端是否还活着、Claude Code 是否卡在权限确认等交互上
# 确认对方终端状态正常后，可以让对应角色重新调用 wait-for-status.sh 继续等待；
# 如果对方终端已经不可用，按"问题 5"重置状态，重新开始
```

---

## 自定义配置

### 修改迭代次数限制

迭代上限的默认值**只在 `verifier-terminal.md` 一个文件里**，Worker 一侧的
skill 文件不追踪迭代次数、也没有对应字段，不要去那边找。

```markdown
<!-- .claude/skills/verifier-terminal.md，"0. 解析迭代上限"一节 -->
# 如果说了"循环N次"或"循环N轮"，LIMIT = N
# 如果没说，默认 3 次      ← 改这里的默认值
```

也可以不改文件，直接在启动 Verifier 时口头指定，比如"开始审查，本次循环5
次"，这个值只对当次会话生效，不会持久化。

### 修改审查维度

编辑 `.claude/skills/verifier-terminal.md`：

```markdown
## 审查清单
### 你的自定义维度
- [ ] 检查项 1
- [ ] 检查项 2
```

### 使用不同的模型

两个终端可以独立配置不同的 Claude 模型：

```yaml
# .claude/skills/worker-terminal.md
---
name: worker-terminal
model: claude-sonnet-4   # Worker 用轻量级模型
---
```

```yaml
# .claude/skills/verifier-terminal.md
---
name: verifier-terminal
model: claude-opus-4     # Verifier 用强推理模型
---
```

### 更换共享目录位置

13 个脚本里都用同一种方式定位共享目录：`脚本所在目录的上一级` + `.dual-claude`
（即约定脚本永远放在项目根下的 `scripts/` 子目录里，共享目录在项目根）。如果
要换成固定路径而不是"相对脚本位置"，需要**同时改全部 13 个脚本**，保持一致，
否则会重现 v1 版"初始化脚本和其他脚本对目录位置的假设不一致"的那个 bug：

```bash
# 每个脚本里都是这一行（写法略有差异但语义相同），改成你要的固定路径：
DUAL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.dual-claude"
# 例如改成固定路径：
# DUAL_DIR="/your/fixed/path/.dual-claude"
```

### 关闭自动 git init

```bash
DUAL_CLAUDE_NO_GIT_INIT=1 bash scripts/start-dual-terminal.sh "任务描述"
```

设置这个环境变量后，即使项目不是 git 仓库，`start-dual-terminal.sh` 也不会自动
`git init`，`checkpoint.sh` 会一直走文件快照分支。只影响"要不要自动建 git 仓
库"这一件事——如果项目已经是 git 仓库，不管有没有设这个变量，`checkpoint.sh`
都会用 git 模式。

---

## 架构原理（深入）

### 文件系统状态机解决的是"协调"问题，不是"信任"问题

```
Subagent（父级实例编排）:
  W/V 各自有独立 context → 但父级实例读取 V 的输出后，
  由父级实例决定怎么转述给你
  └── 风险不在"内存篡改"，在于转述环节是单点

文件系统状态机（双终端）:
  Worker 生成结果 → 写入文件 A → 设置状态 S1
  Verifier 读取文件 A → 写入文件 B → 设置状态 S2
  Worker 读取文件 B → 等待状态 S2
  └── 好处是"协调节点"客观存在、双方都能看到同一份文件；
      不代表 Worker 没有能力去写 S1/S2 之外的值——它只是
      按协议"不这么做"
```

### 状态写入为什么改成 `set-status.sh` 而不是直接 `echo >`

```bash
# v1 的写法（有风险）：
echo "WORKER_DONE" > .dual-claude/status.txt
# 如果这条命令在写入过程中被中断（比如进程被杀），另一端有极小概率读到
# 半截内容；而且没有取值校验，拼错状态名不会报错，状态机会静默卡死。

# v2 的写法：
bash scripts/set-status.sh WORKER_DONE
# 内部是"写临时文件 -> mv 覆盖"，mv 在同一文件系统内是原子操作，读者
# 要么读到旧值要么读到完整新值；同时会校验状态名是否合法。
```

### 关于"Worker 试图伪造状态会怎样"——如实说明

v1 版文档曾经写"如果 Worker 试图伪造状态，Verifier 会在下一轮重新覆盖，伪造
无效"——这个说法不准确，需要澄清：如果 Worker 在自己那一轮直接把状态写成
`APPROVED`，而这时候人类（或 Worker 自己的等待循环）看到 `APPROVED` 就认为
任务完成、不再等 Verifier 真正跑完，这个伪造在那一刻就已经"生效"了，不会有
任何机制自动纠正它——因为根本没有 Verifier 在运行去"重新覆盖"它。

这套协议真正依赖的，是 Worker 遵守 skill 文件里"不要设置 APPROVED/NEEDS_FIX
/REJECTED"这条规则。这里要澄清一点：`event-log.txt` 里每条事件标的
`[Worker]`/`[Verifier]` 角色，是从**要设置的状态值**反推的（设
`WORKER_DONE` 就标 Worker，设 `APPROVED` 就标 Verifier），不是从"谁真正调用
了这个脚本"反推的——如果 Worker 真的伪造 `set-status.sh APPROVED`，日志里
照样会显示成 `[Verifier] ... -> APPROVED`，光看这个角色标注分辨不出来。

真正能用的检测依据是**伪造的状态前面缺了该有的铺垫**：正常的 `APPROVED`/
`REJECTED` 前面必然有 `iteration.txt` 递增、`verifier-report.txt` 更新、
`verifier-phase.txt` 走过"审查中→撰写报告中"这几个阶段——`watch-status.sh`
仪表盘上这几项都能看到。如果状态突然跳到 `APPROVED`，但迭代数没变、审查报告
内容还是上一轮的旧内容、Verifier 的阶段也没有对应更新过，这些"缺了该有的
铺垫"比角色标注本身更能说明问题，需要人工介入核实。

---

## 附录：这套框架里人最好在哪些地方介入

下面不是泛泛的"注意事项"清单，是按**系统自己在设计上已经承认弱、或者主动选择不自动决定**这个标准排的——脚本和强制步骤已经覆盖得很好的环节不在其中，人工在上面做重复检查的边际价值很低。

### 第一档：系统结构性弱的地方，人必须补位

**1. APPROVED 之前的抽查，尤其当 Verifier 有历史漏判记录时**

这是整套框架里最薄弱的一环，不是我随口说的——`watch-status.sh` 里专门为这个场景写了一条警告：Verifier 有历史漏判记录时，`APPROVED` 后会提示"建议人工抽查一遍再彻底放心"。原因是结构性的：Verifier 偷懒的产出和认真审查的产出长得一模一样——都叫"PASS"——而 `APPROVED` 是终局状态，没有下一轮纠错机会。系统能做的只是把"这次 Verifier 有前科"这个信号摆出来，剩下的判断——"这次是不是真的可信"——机制本身给不出答案，只能人来看。**如果只挑一个地方投入人工精力，是这里。**

**2. `plan.md` 里程碑拆解质量**

v3.4 里明确写了"没有解决"的缺口：Verifier 只核对"这轮改动是否符合声明的里程碑"，不核对"这份拆解本身合不合理"。一个拆得过粗的里程碑清单（比如整个任务就一条）能让所有防"一次性做完"的机制形同虚设，但没有任何自动检查会告诉你这件事发生了。这条检查成本很低——扫一眼 `plan.md` 的里程碑清单，看颗粒度是不是真的可审查、验收标准是不是具体——但只有人会做，Verifier 不会主动质疑 Worker 拆出来的计划粒度。建议在 Worker 第一轮写出 `plan.md` 后、进入正式循环前，人看一眼这份清单。

**3. 强制 REJECTED 触发的时候（尤其"同一[阻塞]连续 3 轮未解决"）**

这条触发意味着 `NEEDS_FIX` 这条路径没在收敛——Worker 改了三轮同一个问题还没改对。系统能做的是识别"没在收敛"这个现象（靠交叉核对），但诊断不出**为什么**没收敛：需求本身有歧义？Worker 一直没找到正确方向？这个问题的复杂度超出了当前拆解粒度？这几种情况需要完全不同的下一步动作，而这个判断只有人能做。看到这个 `REJECTED`，别自动 `next-round.sh` 重来一遍指望下次运气好，先看一眼报告里记录的"已确认的根因和之前几轮的修复尝试"。

**4. 长会话下持续盯 `watch-status.sh`**

这条在 README 里明说了是"诚实记录为局限，不是下个版本能解决的"——`wait-for-status.sh` 的有界轮询解决的是"单次调用会不会被系统杀掉"，解决不了"模型在长会话里会不会在 agent loop 中持续发起下一次轮询调用"。这是几个设计上主动放弃了在脚本层面继续打补丁、转而要求人介入的地方之一。任务预期要跑十几轮以上时，开着仪表盘是必要操作，不是锦上添花。

### 第二档：低频出现，但一次判断的影响很大

**5. 初始 `task.txt` 和 `LIMIT` 的设定**

这两个决定了整条流水线的输入质量和预算，没人能替你想清楚要做什么、允许几轮。任务描述含糊，后面所有的验收标准、里程碑拆解都会跟着含糊——这是唯一一个真正"垃圾进垃圾出"的环节。

**6. `rollback-help.sh` 之后要不要真的回滚，回滚到哪个点**

这是刻意设计成人工专属的——`checkpoint.sh` 全自动（每轮改代码前自动创建回滚点），但 `rollback-help.sh` 只打印信息，不执行任何 `git reset` 或覆盖操作。这不是没做完，是有意留下的口子：回滚是有损操作，值不值得丢弃这之后的工作，只有人清楚。

**7. `REJECTED` 之后怎么办**

系统在 `REJECTED` 之后就停了，不会自己决定"要不要用 `next-round.sh` 重新来一轮、要不要先手动改一下 `task.txt` 重新拆解、还是这个方向本身就该放弃"。这个决策树系统完全没有涉足，全部留给人。

### 第三档：出现信号时值得看一眼，不必每次都主动介入

- **违规/漏判记录新增**（`watch-status.sh` 的"需要关注"会标出来）——不是每次都要立刻处理，但至少扫一眼具体记的是什么，判断要不要提前打断。
- **Worker 声明"里程碑耦合无法拆分"时**——偶尔抽查这个理由是不是站得住，还是在拿"耦合"当借口把好几个里程碑糅在一起绕过范围约束。
- **涉及真实视觉呈现的技术四验证**——如果你的环境里 Verifier 没有真正能截图/查看渲染结果的工具，它写的"实测记录"可能是它能拿到的最好替代品，但终究不如人眼直接看一眼来得可靠。这类任务，人自己偶尔打开跑起来的东西看一眼，比信任 Verifier 的文字描述更保险——这一点系统没法替你判断你的环境里 Verifier 到底有没有这个能力，需要你自己清楚。

### 一句话总结

**系统自己已经在设计上明说"这里我不替你决定"的地方（APPROVED 前、REJECTED 后、rollback 执行），和系统在文档里承认"这里防不住"的地方（`plan.md` 粒度、长会话轮询纪律），加起来就是人真正该花精力的地方——其余被脚本和强制步骤覆盖的环节，人工重复检查的边际价值很低。**

---

## 贡献与许可

- **问题反馈**: 通过 GitHub Issues
- **功能建议**: 通过 GitHub Discussions
- **许可**: MIT

---

> **提示**: 双终端模式的核心价值在于**去掉编排过程里的单一控制点，让审查结论不由同一个模型实例既构造又转述**。它不是"不可作弊"的技术保证，代价是需要人工分别操作两个终端。如果你需要完全自动化的流程，请使用 Subagent 方案；如果你需要更高的审查可信度、并且愿意承担人工协调的成本，再考虑双终端方案。
