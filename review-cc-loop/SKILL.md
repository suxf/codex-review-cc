---
name: review-cc-loop
description: 循环审核模式。调用本机 Claude Code CLI 对当前工作区的代码改动进行审查与修改的迭代循环，直到审核结果中不再包含严重（必须修复）级别的问题为止。当用户输入 /review-cc-loop 或 $review-cc-loop，或要求"循环审核""反复审查直到没问题"时触发。复用 review-cc 技能的 scripts/review.ps1 和 references/review_prompt.md。
---

# Review-CC-Loop

循环审核模式。Codex 交替执行审查（通过 Claude Code）与代码修改，直到审核结果中不再包含"严重（必须修复）"级别的问题为止。

复用 `review-cc` 技能的 `scripts/review.ps1` 和 `references/review_prompt.md`，脚本路径为 `<review-cc 技能目录>\scripts\review.ps1`。

## 前置条件

- `claude` 命令可用（Claude Code CLI 已安装并完成登录）。
- `git` 或 `svn` 命令可用且当前目录在其仓库内；或通过 `-Files` 手动指定变动文件。
- `review-cc` 技能已安装（本技能复用其脚本和模板）。

## 执行流程

进入循环模式后，Codex 按以下流程交替执行审查与修改：

### 每一轮的执行步骤

1. 准备 ContextFile，每轮使用独立路径（如 `work/review-context-1.txt`、`work/review-context-2.txt`），写入以下内容：
   - 本次功能的设计思路与变更说明
   - 当前是第 N 轮审核（首轮写"第 1 轮"）
   - 非首轮时，额外写入：上一轮发现的严重问题清单、Codex 已做的修改说明
2. 运行审核脚本：

   `& "<review-cc 技能目录>\scripts\review.ps1" -ContextFile "<临时文件路径>"`

   非 VCS 目录时加 `-Files "file1.py;file2.js"`。

3. 从 Claude Code 返回的审核结果中提取"严重（必须修复）"部分。
4. 如果没有严重问题：循环结束，向用户报告最终结果（含最后一轮的警告和建议）。
5. 如果有严重问题：Codex 根据审核建议逐一修改代码，然后回到步骤 1 进入下一轮。

### 终止条件

- 正常终止：某轮审核结果中"严重（必须修复）"为"无"。
- 强制终止（防死循环）：超过 10 轮，或连续 2 轮的严重问题归一化后相同（去除行号、文件路径、空白后的文本相等，说明修改未生效）。此时向用户报告卡住的问题，请用户介入。
- 错误终止：脚本返回非零退出码（1=错误，2=无改动），应立即停止循环并报告给用户，不要继续下一轮。

### 编排要求

- 每轮审核结果和 Codex 的修改都要同步告知用户。
- 严重问题阻塞循环；警告和建议不阻塞，但最后一轮有则一并报告。
- Codex 的修改必须针对审核指出的具体问题，不要做无关重构。
- 不要擅自修改与审核结果无关的代码。