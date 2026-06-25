---
name: review-cc
description: 调用本机 Claude Code CLI 对当前工作区的代码改动进行代码审查。自动识别 git 或 svn 仓库；两者皆无时使用手动指定的文件清单。脚本自行获取变更内容并嵌入 prompt，Claude Code 仅需只读分析。单次审核模式。循环审核模式请使用 /review-cc-loop。当用户输入 /review-cc 或 $review-cc，或要求"审核/审查当前代码改动""用 claude code review 当前改动"时触发。
---

# Review-CC

调用本机已安装的 Claude Code CLI 对当前工作区的代码改动做代码审查。自动识别 git 或 svn 仓库：先探 git，非 git 则探 svn，都不是则使用手动文件清单。

脚本自行获取完整 diff 内容并嵌入 prompt 传给 Claude Code，Claude Code 不需要执行任何命令，只做只读分析。

## 前置条件

- `claude` 命令可用（Claude Code CLI 已安装并完成登录）。
- `git` 或 `svn` 命令可用且当前目录在其仓库内；或通过 `-Files` 手动指定变动文件。

## 单次审核流程

1. 总结当前对话中本次功能的设计思路与变更内容，写入临时文件（如 `work/review-context.txt`）。
2. 运行审核脚本，把设计思路文件路径传进去：

   `& "<技能目录>\scripts\review.ps1" -ContextFile "<临时文件路径>"`

3. 脚本自动检测 VCS、获取 diff、组装 prompt、调用 `claude -p`，结果输出到 stdout。
4. Codex 把 Claude Code 返回的审核结果原样转述给用户，再根据结果决定后续操作。

### 非 VCS 目录

当前目录既非 git 也非 svn 仓库时，通过 `-Files` 指定变动文件清单（分号分隔，路径必须相对当前目录且不得越界）：

`& "<技能目录>\scripts\review.ps1" -ContextFile "<临时文件>" -Files "file1.py;file2.js"`

## 脚本参数

| 参数         | 说明                                                                 |
|--------------|----------------------------------------------------------------------|
| -ContextFile | Codex 写入的设计思路文件路径，内容作为审核背景传给 Claude Code         |
| -Files       | 非 VCS 目录时的变动文件清单，分号分隔，路径相对当前目录且不得越界      |
| -Target      | changes(默认) / staged / commit / base                               |
| -Base        | Target=base 时的基准点，git 为分支名/tag/commit ref，svn 为修订号     |
| -Model       | 传给 claude 的模型别名（如 sonnet、opus）                             |

## 退出码

| 退出码 | 含义               |
|--------|--------------------|
| 0      | 审核完成           |
| 1      | 错误（含格式校验失败） |
| 2      | 所选范围无改动     |

## 输出契约

脚本调用 Claude Code 后会校验输出中是否包含四个标记行（`!!!REVIEW-RESULT!!!`、`!!!CRITICAL!!!`、`!!!WARNING!!!`、`!!!SUGGESTION!!!`）。缺少任一标记行时，脚本打印原始输出并返回 exit 1。

## 审核范围（VCS 模式）

### git

| Target  | 范围               | 命令                  |
|---------|--------------------|-----------------------|
| changes | 所有未提交改动     | git diff HEAD         |
| staged  | 仅暂存改动         | git diff --cached     |
| commit  | 最近一次提交       | git diff HEAD~1 HEAD  |
| base    | 相对基准分支的改动 | git diff <base>...HEAD|

### svn

| Target  | 范围                 | 命令                   |
|---------|----------------------|------------------------|
| changes | 所有本地改动         | svn diff               |
| staged  | 等同 changes         | svn diff               |
| commit  | 相对上一修订版本     | svn diff -r PREV:HEAD  |
| base    | 相对指定修订版本     | svn diff -r <base>:HEAD|

## 安全说明

脚本自行获取 diff 内容并嵌入 prompt，Claude Code 仅获得 `Read Glob Grep` 三个只读工具权限，不能执行任何命令，审核全程只读。`-Base` 参数做白名单校验（仅允许字母、数字、点、下划线、斜杠、连字符），`-Files` 路径做越界校验（必须相对当前目录）。

## Prompt 模板

审核标准与输出格式定义在 `references/review_prompt.md`，包含 `__REVIEW_CONTEXT__`、`__REVIEW_VCS__`、`__REVIEW_SCOPE__`、`__REVIEW_CHANGES__` 四个哨兵占位符，脚本读取后注入实际内容。如需调整审核维度或输出格式，编辑该文件即可。