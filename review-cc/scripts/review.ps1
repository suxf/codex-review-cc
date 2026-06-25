<#
.SYNOPSIS
  调用 Claude Code CLI 审核当前工作区的代码改动。
  自动识别 git / svn 仓库；两者皆无时使用 -Files 指定的文件清单。
  脚本自行获取变更内容并嵌入 prompt，Claude Code 仅需只读分析。

.PARAMETER ContextFile
  Codex 写入的设计思路文件路径。内容会作为"本次功能设计思路"传给 Claude Code。

.PARAMETER Files
  非 VCS 目录时，分号分隔的变动文件清单。路径必须相对当前目录且不得越界。

.PARAMETER Target
  changes (默认) | staged | commit | base

.PARAMETER Base
  Target=base 时的基准点。git 为分支名/tag/commit ref，svn 为修订号。

.PARAMETER Model
  传给 claude --model 的别名，如 sonnet/opus。

.PARAMETER DryRun
  仅做 VCS/Files 探测与可审核性判定，不调用 Claude Code。用于试跑或循环审核前置校验，避免浪费 API 调用。
#>
[CmdletBinding()]
param(
    [string]$ContextFile = '',
    [string]$Files = '',
    [ValidateSet('changes','staged','commit','base')]
    [string]$Target = 'changes',
    [string]$Base = '',
    [string]$Model = '',

    [switch]$DryRun
)

# 退出码约定：0=审核完成；1=错误；2=所选范围无改动
$ExitOK   = 0
$ExitErr  = 1
$ExitNone = 2

# 校验 claude 可用
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Host "未找到 claude 命令，请先安装并登录 Claude Code CLI。" -ForegroundColor Red
    exit $ExitErr
}

$SkillRoot  = Split-Path -Parent $PSScriptRoot
$PromptFile = Join-Path $SkillRoot 'references\review_prompt.md'
if (-not (Test-Path $PromptFile)) {
    Write-Host "审核 prompt 模板缺失: $PromptFile" -ForegroundColor Red
    exit $ExitErr
}

# 读取设计思路
$context = '（未提供设计思路，仅依据 diff 审查）'
if ($ContextFile -and (Test-Path $ContextFile)) {
    $context = (Get-Content $ContextFile -Raw -Encoding UTF8).TrimStart([char]0xFEFF).Trim()
}

# 探测 VCS 类型：先 git，再 svn
$Vcs = ''
git rev-parse --is-inside-work-tree 2>$null | Out-Null
if ($LASTEXITCODE -eq 0) { $Vcs = 'git' }
else {
    svn info 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $Vcs = 'svn' }
}

# 组装变更内容
$changeSection = ''
$scope = ''
$stat = ''

if ($Vcs -eq 'git') {
    # 参数化构建 git diff 参数数组，杜绝命令注入
    $diffArgs = @('diff')
    switch ($Target) {
        'changes' { $diffArgs += @('HEAD');              $scope = '所有未提交的改动（暂存 + 未暂存）' }
        'staged'  { $diffArgs += @('--cached');          $scope = '已暂存但未提交的改动' }
        'commit'  {
            git rev-parse --verify HEAD~1 2>$null | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Host "当前仓库只有 1 个提交，无法用 commit 模式对比上次提交。" -ForegroundColor Yellow
                exit $ExitErr
            }
            $diffArgs += @('HEAD~1','HEAD'); $scope = '最近一次提交引入的改动'
        }
        'base'    {
            if (-not $Base) {
                foreach ($cand in @('main','master','develop','trunk','default')) {
                    git rev-parse --verify --quiet "refs/heads/$cand" 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) { $Base = $cand; break }
                }
                if (-not $Base) {
                    Write-Host "未找到默认分支，请用 -Base 指定基准分支。" -ForegroundColor Yellow
                    exit $ExitErr
                }
            }
            # 白名单校验：只允许分支名/tag/commit ref 中的合法字符
            if ($Base -notmatch '^[A-Za-z0-9._/][A-Za-z0-9._/\-]*$') {
                Write-Host "Base 包含非法字符，仅允许字母、数字、点、下划线、斜杠、连字符。" -ForegroundColor Red
                exit $ExitErr
            }
            $diffArgs += @("$Base...HEAD"); $scope = "相对基准分支 $Base 的改动"
        }
    }
    # 脚本自行获取 diff 内容与统计（参数化调用，非 Invoke-Expression）
    $diffContent = & git @diffArgs 2>$null | Out-String
    $diffExit = $LASTEXITCODE
    $statArgs = @('diff','--stat') + $diffArgs[1..($diffArgs.Count-1)]
    $stat = & git @statArgs 2>$null | Out-String
    if ($diffExit -ne 0) {
        Write-Host "获取 git diff 失败，请检查仓库状态与所选范围。" -ForegroundColor Red
        exit $ExitErr
    }
    if ([string]::IsNullOrWhiteSpace($diffContent)) {
        Write-Host "所选范围内没有代码改动可审核。" -ForegroundColor Yellow
        Write-Host "提示：未跟踪的新文件不在 diff 范围内，请先 git add。" -ForegroundColor Yellow
        exit $ExitNone
    }
    $changeSection = "## 变更概览`n`n`````n$stat`````n`n## 完整 diff`n`n`````n$diffContent`````n"

} elseif ($Vcs -eq 'svn') {
    # 参数化构建 svn diff 参数
    $diffArgs = @('diff')
    switch ($Target) {
        'changes' { $scope = '所有本地未提交的改动' }
        'staged'  { $scope = 'svn 无暂存区，等同所有本地改动' }
        'commit'  { $diffArgs += @('-r','PREV:HEAD');  $scope = '相对上一修订版本的改动' }
        'base'    {
            if (-not $Base) { $Base = 'PREV' }
            if ($Base -notmatch '^[A-Za-z0-9_:][A-Za-z0-9_:\-]*$') {
                Write-Host "Base 包含非法字符，仅允许字母、数字、下划线、冒号、连字符。" -ForegroundColor Red
                exit $ExitErr
            }
            $diffArgs += @('-r',"${Base}:HEAD"); $scope = "相对修订版本 $Base 的改动"
        }
    }
    $diffContent = & svn @diffArgs 2>$null | Out-String
    $diffExit = $LASTEXITCODE
    # svn stat 用 --summarize 对齐 diff 范围（commit/base 模式）或全量 status（changes 模式）
    if ($Target -in @('commit','base')) {
        $statArgs = @('diff','--summarize') + $diffArgs[1..($diffArgs.Count-1)]
        $stat = & svn @statArgs 2>$null | Out-String
    } else {
        $stat = & svn status 2>$null | Out-String
    }
    if ($diffExit -ne 0) {
        Write-Host "获取 svn diff 失败，请检查工作副本状态与所选范围。" -ForegroundColor Red
        exit $ExitErr
    }
    if ([string]::IsNullOrWhiteSpace($diffContent)) {
        Write-Host "所选范围内没有代码改动可审核。" -ForegroundColor Yellow
        Write-Host "提示：未纳入版本控制的新文件不在 diff 范围内，请先 svn add。" -ForegroundColor Yellow
        exit $ExitNone
    }
    $changeSection = "## 变更概览`n`n`````n$stat`````n`n## 完整 diff`n`n`````n$diffContent`````n"

} else {
    # 非 VCS：使用 -Files 指定的文件清单，校验路径不得越界当前目录
    if (-not $Files) {
        Write-Host "当前目录不在 git 或 svn 仓库内，且未通过 -Files 指定变动文件。" -ForegroundColor Yellow
        exit $ExitErr
    }
    $cwd = (Get-Location).Path
    $cwdNorm = $cwd.TrimEnd('\') + '\'
    $validFiles = @()
    foreach ($f in ($Files -split ';' | Where-Object { $_.Trim() })) {
        # 拒绝绝对路径（含盘符或以 \ 开头）
        if ([System.IO.Path]::IsPathRooted($f)) {
            Write-Host "拒绝绝对路径，仅允许相对当前目录的路径: $f" -ForegroundColor Red
            exit $ExitErr
        }
        $full = [System.IO.Path]::GetFullPath((Join-Path $cwd $f))
        if (-not $full.StartsWith($cwdNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "文件路径越界，已拒绝: $f" -ForegroundColor Red
            exit $ExitErr
        }
        if (-not (Test-Path $full)) {
            Write-Host "文件不存在: $f" -ForegroundColor Red
            exit $ExitErr
        }
        $validFiles += $f
    }
    $scope = '非版本控制目录，手动指定的变动文件'
    $fileList = $validFiles | ForEach-Object { "- $_" }
    $changeSection = "## 变动文件清单`n`n以下文件在本轮工作中发生变动，请用 Read 工具逐一阅读后审查：`n`n" + ($fileList -join "`n")
}

Write-Host "仓库类型：$(if ($Vcs) { $Vcs } else { '无（文件清单）' })" -ForegroundColor Cyan
Write-Host "审核范围：$scope" -ForegroundColor Cyan
if ($Vcs) {
    Write-Host "改动概览：" -ForegroundColor Cyan
    Write-Host $stat
}
# 组装 prompt：用单次替换注入占位符
$template = (Get-Content $PromptFile -Raw -Encoding UTF8).TrimStart([char]0xFEFF)
# 两阶段替换，彻底防止输入内容含哨兵时被二次替换
$g1 = [guid]::NewGuid().ToString(); $g2 = [guid]::NewGuid().ToString()
$g3 = [guid]::NewGuid().ToString(); $g4 = [guid]::NewGuid().ToString()
# 阶段 1：模板占位符 → GUID 临时标记
$stage1 = $template.
    Replace('__REVIEW_CONTEXT__', $g1).
    Replace('__REVIEW_VCS__',     $g2).
    Replace('__REVIEW_SCOPE__',   $g3).
    Replace('__REVIEW_CHANGES__',  $g4)
# 阶段 2：GUID 标记 → 实际值
$prompt = $stage1.
    Replace($g1, $context).
    Replace($g2, $(if ($Vcs) { $Vcs } else { '无' })).
    Replace($g3, $scope).
    Replace($g4, $changeSection)

# DryRun 模式：仅探测可审核性，不调用 Claude Code
if ($DryRun) {
    Write-Host "DryRun: 仓库类型=$(if ($Vcs) { $Vcs } else { '无' })，审核范围=$scope，可审核。" -ForegroundColor Green
    exit $ExitOK
}

$exitCode = $ExitErr  # 预设错误，异常路径不会误返回 0
try {
    Write-Host "正在调用 Claude Code 进行审核，请稍候..." -ForegroundColor Cyan
    # 非交互调用 claude，仅允许只读工具（diff 已嵌入 prompt，无需 Bash）
    $claudeArgs = @('-p', $prompt, '--allowedTools', 'Read', 'Glob', 'Grep')
    if ($Model) { $claudeArgs += @('--model', $Model) }

    $rawOutput = & claude @claudeArgs 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode -or $exitCode -eq 0) { $exitCode = $ExitOK } else { $exitCode = $ExitErr }

    # 格式校验：检测四个标记行是否存在
    $lines = $rawOutput -split "`n"
$hasMarkers = (($lines | Where-Object { $_.Trim() -eq '!!!REVIEW-RESULT!!!' }).Count -ge 1) -and
              (($lines | Where-Object { $_.Trim() -eq '!!!CRITICAL!!!' }).Count -ge 1) -and
              (($lines | Where-Object { $_.Trim() -eq '!!!WARNING!!!' }).Count -ge 1) -and
              (($lines | Where-Object { $_.Trim() -eq '!!!SUGGESTION!!!' }).Count -ge 1)
    if (-not $hasMarkers) {
        Write-Host ""
        Write-Host "=== Claude Code 原始输出 ===" -ForegroundColor Yellow
        Write-Host $rawOutput
        Write-Host "=== 格式校验失败 ===" -ForegroundColor Red
        Write-Host "审核输出缺少必要的标记行，无法程序化提取。" -ForegroundColor Red
        Write-Host "请人工查看上方原始输出。" -ForegroundColor Yellow
        $exitCode = $ExitErr
    } else {
        Write-Output $rawOutput
    }
}
catch {
    $exitCode = $ExitErr
    Write-Host "调用 Claude Code 时发生异常: $_" -ForegroundColor Red
}
exit $exitCode
