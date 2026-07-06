# Dual Terminal Skill - 双终端协作模式

> **真正的进程级隔离双模型架构** — Worker 和 Verifier 运行在两个完全独立的终端中，通过文件系统状态机协调，实现不可作弊的代码审查。

---

## 目录

- [架构概述](#架构概述)
- [核心优势](#核心优势)
- [文件结构](#文件结构)
- [安装步骤](#安装步骤)
- [使用流程](#使用流程)
- [状态机说明](#状态机说明)
- [防作弊原理](#防作弊原理)
- [故障排查](#故障排查)
- [自定义配置](#自定义配置)

---

## 架构概述

```
┌─────────────────────────────────────────────────────────────┐
│                     你的项目目录                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  终端 A (Worker)              终端 B (Verifier)              │
│  ┌───────────────┐          ┌───────────────┐              │
│  │ Claude Code   │          │ Claude Code   │              │
│  │ + worker      │          │ + verifier    │              │
│  │   skill       │          │   skill       │              │
│  │               │          │               │              │
│  │ 1.读取任务    │          │ 1.等待状态    │              │
│  │ 2.生成代码    │          │ 2.读取输出    │              │
│  │ 3.写入文件───│─────────→│ 3.独立审查    │              │
│  │ 4.等待结果    │          │ 4.写入报告───│────────→      │
│  │ 5.读取报告←──│──────────│ 5.等待下一轮  │              │
│  │ 6.修正/完成   │          │               │              │
│  └───────┬───────┘          └───────┬───────┘              │
│          │                          │                      │
│          └──────────┬───────────────┘                      │
│                     ↓                                      │
│            .dual-claude/ (共享目录)                         │
│            ├── status.txt        ← 状态机                  │
│            ├── task.txt          ← 任务描述                │
│            ├── worker-output.txt  ← Worker 输出             │
│            ├── verifier-report.txt ← Verifier 报告        │
│            └── iteration.txt     ← 迭代计数               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**关键设计**：两个终端的 Claude 实例**完全不共享内存、上下文或进程**。它们只通过 `.dual-claude/` 目录下的文本文件进行异步通信。

---

## 核心优势

| 特性 | 双终端 | Subagent | 单模型 |
|------|--------|---------|--------|
| **进程隔离** | ✅ 真正独立进程 | ⚠️ 同一进程切换 | ❌ 同一实例 |
| **内存隔离** | ✅ 不共享上下文 | ⚠️ 共享进程内存 | ❌ 完全共享 |
| **模型权重隔离** | ✅ 可配置不同模型 | ❌ 同一模型实例 | ❌ 同一模型 |
| **Worker 作弊可能** | ❌ **不可能** | ⚠️ 微妙偏袒风险 | 🔴 高风险 |
| **自动化程度** | ⚠️ 需人工/脚本协调 | ✅ 内置调度 | ✅ 完全自动 |
| **适用场景** | 高 stakes 代码审查 | 日常开发 | 简单任务 |

---

## 文件结构

解压后你会得到以下文件：

```
dual-terminal-skill/
├── SKILL-worker.md              # Worker 的 Skill 定义
├── SKILL-verifier.md            # Verifier 的 Skill 定义
├── scripts/
│   ├── start-dual-terminal.sh   # 初始化脚本
│   ├── watch-status.sh          # 状态监控脚本
│   └── reset.sh                 # 重置脚本
├── README.md                    # 本文件
└── .gitignore                   # Git 忽略规则
```

**安装到你的项目后**的结构：

```
your-project/
├── .claude/
│   └── skills/
│       ├── worker-terminal.md      ← 从 SKILL-worker.md 复制
│       └── verifier-terminal.md    ← 从 SKILL-verifier.md 复制
│
├── scripts/                         ← 从 scripts/ 复制
│   ├── start-dual-terminal.sh
│   ├── watch-status.sh
│   └── reset.sh
│
├── .dual-claude/                    ← 运行时自动生成
│   ├── status.txt
│   ├── task.txt
│   ├── worker-output.txt
│   ├── verifier-report.txt
│   └── iteration.txt
│
├── README.md                        ← 可选，参考用
└── .gitignore
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
# 复制脚本到项目根目录
mkdir -p scripts
cp scripts/start-dual-terminal.sh scripts/
cp scripts/watch-status.sh scripts/
cp scripts/reset.sh scripts/

# 赋予执行权限
chmod +x scripts/*.sh
```

### 第三步：验证安装

```bash
# 检查文件是否存在
ls -la .claude/skills/worker-terminal.md
ls -la .claude/skills/verifier-terminal.md
ls -la scripts/start-dual-terminal.sh

# 预期输出：
# .claude/skills/worker-terminal.md
# .claude/skills/verifier-terminal.md
# scripts/start-dual-terminal.sh
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
1. 读取 `.dual-claude/task.txt` 中的任务
2. 查看项目相关文件
3. 生成代码
4. 将输出写入 `.dual-claude/worker-output.txt`
5. 将状态设置为 `WORKER_DONE`

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
5. 将状态设置为 `VERIFIER_DONE`

**Verifier 终端输出示例**：
```
[Verifier] 检测到状态: WORKER_DONE
[Verifier] 读取 Worker 输出...
[Verifier] 独立审查中...
[Verifier] 发现问题: JWT_SECRET 未做非空检查
[Verifier] 写入审查报告...
[Verifier] 设置状态: VERIFIER_DONE
```

### 终端 A - Worker 读取结果

Worker 检测到状态变为 `VERIFIER_DONE`，自动读取审查报告：

```
[Worker] 检测到状态: VERIFIER_DONE
[Worker] 读取审查报告...
[Worker] 审查结果: NEEDS_FIX
[Worker] 修正建议: 添加 JWT_SECRET 非空检查
[Worker] 修正代码...
[Worker] 重新提交...
```

### 循环直到通过

```
Worker 提交 → Verifier 审查 → NEEDS_FIX → Worker 修正 → Verifier 审查 → APPROVED
```

最大 3 次迭代，超过则人工介入。

### 终端 C - 监控状态（可选）

```bash
bash scripts/watch-status.sh
```

输出：
```
🔍 监控双终端协作状态 (按 Ctrl+C 退出)
==========================================

[14:32:10] 状态变更: WORKER_DONE | 迭代: 1
  → Worker 已提交，Verifier 可以开始审查

[14:32:45] 状态变更: VERIFIER_DONE | 迭代: 1
  → Verifier 已完成，Worker 可以读取报告

[14:33:20] 状态变更: WORKER_DONE | 迭代: 2
  → Worker 已提交，Verifier 可以开始审查

[14:33:55] 状态变更: APPROVED | 迭代: 2
  → ✅ 审查通过，任务完成！
```

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
                    ┌─────────────────┐
                    │ VERIFIER_DONE   │
                    │ Verifier 已完成  │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
              ↓              ↓              ↓
        ┌─────────┐   ┌─────────┐   ┌─────────┐
        │APPROVED │   │NEEDS_FIX│   │REJECTED │
        │  通过   │   │ 需修正  │   │  重做   │
        └─────────┘   └────┬────┘   └────┬────┘
                             │              │
                             │              │
                             ↓              ↓
                        ┌─────────┐   ┌─────────┐
                        │Worker修正│   │重新理解 │
                        │重新提交 │   │  任务   │
                        └────┬────┘   └────┬────┘
                             │              │
                             └──────┬───────┘
                                    │
                                    ↓
                           ┌─────────────────┐
                           │   WORKER_DONE   │
                           │   (循环开始)     │
                           └─────────────────┘
```

| 状态 | 含义 | 谁可以操作 |
|------|------|----------|
| `IDLE` | 等待 Worker 开始 | Worker |
| `WORKER_DONE` | Worker 已提交，等待审查 | Verifier |
| `VERIFIER_DONE` | Verifier 已完成，Worker 可读取 | Worker |
| `APPROVED` | 审查通过，任务完成 | 任意 |

---

## 防作弊原理

### 为什么 Worker 无法作弊？

| 作弊方式 | 为什么不可能 | 技术原理 |
|---------|------------|---------|
| **伪造审查结果** | ❌ 不可能 | Worker 在终端 A，看不到终端 B 的 Verifier 输出 |
| **跳过审查** | ❌ 不可能 | 状态机强制：Worker 必须等待 `VERIFIER_DONE` 才能继续 |
| **篡改审查报告** | ❌ 不可能 | Verifier 写入报告后设置状态，Worker 只能读取不能修改 |
| **影响 Verifier 判断** | ❌ 不可能 | 两个终端完全独立，Worker 无法访问 Verifier 的进程/内存 |
| **隐藏已知问题** | ⚠️ 可被检测 | Verifier 会检查 WORKER_REPORT 的完整性 |

### 隔离性对比

```
单模型（一个 Claude）:
  ┌─────────────────┐
  │   Claude Code   │
  │  Worker + Verifier │  ← 同一上下文，容易自我偏袒
  └─────────────────┘

Subagent（同一进程）:
  ┌─────────────────┐
  │   Claude Code   │
  │  ┌───┐  ┌───┐  │
  │  │W  │  │V  │  │  ← 上下文切换，但共享进程/模型
  │  └───┘  └───┘  │
  └─────────────────┘

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

# 手动修复（谨慎使用）
echo "WORKER_DONE" > .dual-claude/status.txt
```

### 问题 3: Worker 无法读取审查报告

**症状**: Worker 一直在等待

**检查**:
```bash
# 查看当前状态
cat .dual-claude/status.txt

# 应该是 VERIFIER_DONE

# 如果 Verifier 已经完成但状态未更新：
cat .dual-claude/verifier-report.txt  # 查看报告内容
echo "VERIFIER_DONE" > .dual-claude/status.txt  # 手动更新状态
```

### 问题 4: 迭代超过 3 次

**症状**: 循环无法结束

**解决**:
```bash
# 查看当前迭代次数
cat .dual-claude/iteration.txt

# 如果超过 3，人工介入：
# 1. 查看 Worker 输出和 Verifier 报告
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

---

## 自定义配置

### 修改迭代次数限制

编辑两个 Skill 文件中的"最大迭代次数"：

```markdown
<!-- .claude/skills/worker-terminal.md -->
## 迭代规则
| 状态 | 动作 |
|------|------|
| **最大迭代** | 3 次 → 改为你的数字 |
```

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

编辑所有脚本中的 `DUAL_DIR` 变量：

```bash
# scripts/start-dual-terminal.sh
DUAL_DIR="$PROJECT_DIR/.dual-claude"  # 改为你的路径
```

---

## 架构原理（深入）

### 为什么文件系统状态机比内存通信更安全？

```
内存通信（Subagent）:
  Worker 生成结果 → 写入内存 → Verifier 读取
  └── 同一进程，Worker 可能篡改内存

文件系统状态机（双终端）:
  Worker 生成结果 → 写入文件 A → 设置状态 S1
  Verifier 读取文件 A → 写入文件 B → 设置状态 S2
  Worker 读取文件 B → 必须等待状态 S2
  └── 文件操作是原子性的，Worker 无法绕过状态检查
```

### 状态转换的原子性

```bash
# Worker 提交时执行的两步操作：
echo "[代码内容]" > .dual-claude/worker-output.txt
echo "WORKER_DONE" > .dual-claude/status.txt

# 如果 Worker 只做了第一步，忘记第二步：
# Verifier 会一直在等待，不会读取不完整的输出

# 如果 Worker 试图伪造状态：
echo "VERIFIER_DONE" > .dual-claude/status.txt
# 但 Verifier 会覆盖这个状态，Worker 的伪造无效
```

---

## 贡献与许可

- **问题反馈**: 通过 GitHub Issues
- **功能建议**: 通过 GitHub Discussions
- **许可**: MIT

---

> **提示**: 双终端模式的核心价值在于**不可作弊的信任**。如果你需要完全自动化的流程，请使用 Subagent 方案；如果你需要最高级别的审查可信度，请使用双终端方案。
