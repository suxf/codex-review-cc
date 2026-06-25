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

0. 前置校验（仅首轮）：运行 `review.ps1 -DryRun`（不调用 Claude Code，仅探测 VCS/Files 可审核性）。exit 0 进入循环，exit 1 报错停止，exit 2 无改动停止。后续轮跳过此校验直接进入步骤 1。
1. 准备 ContextFile，使用随机文件名（如 `work/review-context-$(Get-Random).txt`），写入以下内容：每轮审核结束后立即删除该轮的 ContextFile，不依赖循环结束统一清理。
   - 本次功能的设计思路与变更说明
   - 当前是第 N 轮审核（首轮写"第 1 轮"）
   - 非首轮时，额外写入：上一轮发现的严重问题清单、Codex 已做的修改说明
2. 运行审核脚本：

   `& "<review-cc 技能目录>\scripts\review.ps1" -ContextFile "<临时文件路径>"`

   非 VCS 目录时加 `-Files "file1.py;file2.js"`。

3. 从 Claude Code 返回的 stdout 中截取 `!!!CRITICAL!!!` 标记行之后、`!!!WARNING!!!` 标记行之前的所有行（不包含标记行本身），作为严重问题列表。此解析由 Codex 侧完成，脚本仅输出原始文本。若标记缺失，向用户报告“审核输出格式异常，请人工介入”并停止循环。
4. 如果没有严重问题：循环结束，向用户报告最终结果（含最后一轮的警告和建议）。
5. 如果有严重问题：Codex 根据审核建议逐一修改代码，然后回到步骤 1 进入下一轮。

### 终止条件

审核结果出来后按以下顺序判定（前者优先）：

1. 错误终止：脚本返回退出码 1（错误），立即停止循环并报告给用户。退出码 2（无改动）仅首轮 DryRun 时按前置校验处理；循环中任一轮返回 exit 2 同样停止循环，向用户报告“本轮范围无改动，请确认是否回滚”。
2. 正常终止：`!!!CRITICAL!!!` 块内容为“无”，循环结束，向用户报告最终结果（含最后一轮的警告和建议）。
3. 强制终止（防死循环）：超过 10 轮，或连续 2 轮中至少 1 条严重问题的“文件路径:行号”组合完全重复（以“文件路径:行号”为去重键，且两轮均至少各 1 条严重问题时才检查），或格式校验失败（标记行缺失）。此时向用户报告卡住的问题，请用户介入。

。