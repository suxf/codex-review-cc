# Codex Review-CC

一个 [Codex](https://github.com/openai/codex) 技能，调用本机 Claude Code CLI 对当前工作区的代码改动进行审查。

## 功能

在 Codex 对话框输入 `/review-cc` 或 `$review-cc`，技能会：

1. 自动检测当前目录是 **git** 还是 **svn** 仓库（先探 git，再探 svn），都不是则使用手动文件清单。
2. 脚本自行获取 diff 内容并嵌入 prompt。
3. 以 `claude -p`（Claude Code CLI 非交互模式）调用，仅授予只读工具权限（`Read`、`Glob`、`Grep`）。
4. Claude Code 分析变更后返回结构化审查结果。

### 循环审核模式

`/review-cc-loop` 触发迭代审核循环：

```
审查 → 修改 → 审查 → 修改 → ... → 无严重问题
```

Codex 在审查（通过 Claude Code）与修改代码之间交替进行，直到审核结果中不再包含"严重（必须修复）"级别的问题。超过 10 轮或连续 2 轮严重问题相同则强制停止，报告卡住的问题等待用户介入。

## 安装

### 方式一：智能体自主安装

把本仓库链接发给 Codex 对话，让它自行安装：

```
帮我安装这个 Codex 技能：https://github.com/suxf/codex-review-cc
```

Codex 会克隆仓库到本地，将 `review-cc` 文件夹复制到技能目录 `~/.codex/skills/`。

### 方式二：手动安装

将 `review-cc` 文件夹复制到你的 Codex 技能目录：

```powershell
git clone https://github.com/suxf/codex-review-cc.git
Copy-Item -Recurse codex-review-cc\review-cc "$env:USERPROFILE\.codex\skills\review-cc"
Copy-Item -Recurse codex-review-cc\review-cc-loop "$env:USERPROFILE\.codex\skills\review-cc-loop"
```

## 前置要求

- 已安装并登录 [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)（`claude --version`）
- PATH 中可用 `git` 或 `svn`（非 VCS 目录可用 `-Files` 参数）

## 用法

### 单次审核

在 Codex 对话中输入：

```
/review-cc
```

### 循环审核

```
/review-cc-loop
```

### 脚本参数

| 参数         | 说明                                                          |
|--------------|---------------------------------------------------------------|
| `-ContextFile` | Codex 写入的设计思路文件路径，内容作为审核背景传给 Claude Code |
| `-Files`       | 非 VCS 目录时的变动文件清单，分号分隔，路径须相对当前目录且不得越界 |
| `-Target`      | `changes`（默认）/ `staged` / `commit` / `base`               |
| `-Base`        | `base` 模式的基准点，git 为分支名/tag/commit ref，svn 为修订号 |
| `-Model`       | Claude 模型别名（如 `sonnet`、`opus`）                        |

### 各 VCS 的审核范围

| Target  | git                          | svn                        |
|---------|------------------------------|----------------------------|
| changes | `git diff HEAD`              | `svn diff`                 |
| staged  | `git diff --cached`          | `svn diff`                 |
| commit  | `git diff HEAD~1 HEAD`       | `svn diff -r PREV:HEAD`    |
| base    | `git diff <base>...HEAD`     | `svn diff -r <base>:HEAD`  |

## 安全说明

- Claude Code 仅获得 `Read`、`Glob`、`Grep` 三个只读工具权限，不能执行任何命令。
- 脚本自行获取 diff 内容并嵌入 prompt，Claude Code 无需 Bash 权限。
- `-Base` 参数做白名单校验（git 仅允许 `[A-Za-z0-9._/\-]`，svn 仅允许 `[A-Za-z0-9_:\-]`）。
- `-Files` 路径必须相对当前目录，绝对路径和 `..` 越界访问被拒绝。

## 退出码

| 退出码 | 含义           |
|--------|----------------|
| 0      | 审核完成       |
| 1      | 错误           |
| 2      | 所选范围无改动 |

## 项目结构

```
codex-review-cc/
├── review-cc/                      # 单次审核技能
│   ├── SKILL.md                    # 技能元数据与 Codex 执行指令
│   ├── scripts/
│   │   └── review.ps1             # 主脚本：VCS 检测、diff 获取、claude 调用
│   ├── references/
│   │   └── review_prompt.md       # 审核 prompt 模板（含占位符）
│   └── agents/
│       └── openai.yaml            # 技能列表 UI 元数据
├── review-cc-loop/                 # 循环审核技能
│   ├── SKILL.md                    # 循环审核指令（复用 review-cc 的脚本和模板）
│   └── agents/
│       └── openai.yaml            # 技能列表 UI 元数据
├── LICENSE                         # MIT 开源协议
├── README.md                       # 说明文档（中文）
└── README_EN.md                    # 说明文档（英文）
```

## 开源协议

[MIT](LICENSE)

## 其他语言

[English](README_EN.md)
