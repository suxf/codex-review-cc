# Codex Review-CC

A [Codex](https://github.com/openai/codex) skill that invokes the local Claude Code CLI to review code changes in your current workspace.

## Features

Type `/review-cc` or `$review-cc` in Codex chat, and the skill will:

1. Auto-detect whether the current directory is a **git** or **svn** repository (tries git first, then svn). Falls back to a manual file list if neither is found.
2. Fetch the diff content itself and embed it into the prompt.
3. Call `claude -p` (Claude Code CLI in non-interactive mode) with read-only tool permissions (`Read`, `Glob`, `Grep` only).
4. Claude Code analyzes the changes and returns a structured review.

### Loop review mode

`/review-cc-loop` triggers an iterative review cycle:

```
review -> fix -> review -> fix -> ... -> no critical issues
```

Codex alternates between reviewing (via Claude Code) and fixing code until no "critical" issues remain. Safety guards stop after 10 rounds or if the same critical issues persist for 2 consecutive rounds.

## Install

### Option 1: Agent self-install

Send the repo link to a Codex conversation and let it install itself:

```
Install this Codex skill: https://github.com/suxf/codex-review-cc
```

Codex will clone the repo and copy the `review-cc` folder into `~/.codex/skills/`.

### Option 2: Manual install

Copy the `review-cc` folder into your Codex skills directory:

```powershell
git clone https://github.com/suxf/codex-review-cc.git
Copy-Item -Recurse codex-review-cc\review-cc "$env:USERPROFILE\.codex\skills\review-cc"
Copy-Item -Recurse codex-review-cc\review-cc-loop "$env:USERPROFILE\.codex\skills\review-cc-loop"
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated (`claude --version`)
- `git` or `svn` available on PATH (or use `-Files` for non-VCS directories)

## Usage

### Single review

In Codex chat:

```
/review-cc
```

### Loop review

```
/review-cc-loop
```

### Script parameters

| Parameter      | Description                                                              |
|----------------|--------------------------------------------------------------------------|
| `-ContextFile` | Path to a file containing the design rationale and change summary       |
| `-Files`       | Semicolon-separated file list for non-VCS directories                    |
| `-Target`      | `changes` (default) / `staged` / `commit` / `base`                       |
| `-Base`        | Baseline ref for `base` target (git: branch/tag/commit; svn: revision)  |
| `-Model`       | Claude model alias (e.g. `sonnet`, `opus`)                                |

### Review scope by VCS

| Target  | git                          | svn                        |
|---------|------------------------------|----------------------------|
| changes | `git diff HEAD`              | `svn diff`                 |
| staged  | `git diff --cached`          | `svn diff`                 |
| commit  | `git diff HEAD~1 HEAD`       | `svn diff -r PREV:HEAD`    |
| base    | `git diff <base>...HEAD`     | `svn diff -r <base>:HEAD`  |

## Security

- Claude Code receives only `Read`, `Glob`, `Grep` permissions — no command execution.
- The script fetches diff content itself and embeds it into the prompt.
- `-Base` is validated against a whitelist (`[A-Za-z0-9._/\-]` for git, `[A-Za-z0-9_:\-]` for svn).
- `-Files` paths must be relative to the current directory; absolute paths and `..` traversal are rejected.

## Exit codes

| Code | Meaning                |
|------|------------------------|
| 0    | Review completed       |
| 1    | Error                  |
| 2    | No changes in scope    |

## Project structure

```
codex-review-cc/
├── review-cc/                      # Single review skill
│   ├── SKILL.md                    # Skill metadata and Codex instructions
│   ├── scripts/
│   │   └── review.ps1             # Main script: VCS detection, diff fetch, claude invocation
│   ├── references/
│   │   └── review_prompt.md       # Review prompt template with placeholders
│   └── agents/
│       └── openai.yaml            # UI metadata for skill lists
├── review-cc-loop/                 # Loop review skill
│   ├── SKILL.md                    # Loop review instructions (reuses review-cc scripts)
│   └── agents/
│       └── openai.yaml            # UI metadata for skill lists
├── LICENSE                         # MIT License
├── README.md                       # Documentation (Chinese)
└── README_EN.md                    # Documentation (English)
```

## License

[MIT](LICENSE)

## Other languages

[中文](README.md)
