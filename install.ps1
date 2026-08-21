$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Repository = 'lwt-sadais/dsh-desktop-bootstrap'
$ArchiveUrl = "https://github.com/$Repository/archive/refs/heads/main.zip"
$DshHome = Join-Path $HOME '.dsh'
$ProfileDirectory = Join-Path $DshHome 'profiles/desktop'
$Plugins = @(
    'github:zhu1090093659/dsh-web-ui',
    'github:FSMargoo/dsh-at-file',
    'github:MuWinds/dsh-archived-sessions',
    'github:lwt-sadais/dsh-git-diff',
    'github:lwt-sadais/dsh-local-file-reference'
)
$script:TempDirectory = $null
$script:SourceDirectory = $null

# 输出带统一前缀的进度信息，便于用户定位当前步骤。
function Write-InitLog {
    param([Parameter(Mandatory)][string]$Message)

    Write-Host "[DSH 初始化] $Message"
}

# 确认当前位于 DSH Desktop 打开的专用终端，避免普通 PowerShell 无法调用 dsh。
function Test-Prerequisites {
    if (-not (Get-Command 'dsh' -ErrorAction SilentlyContinue)) {
        throw '当前终端无法执行 dsh。请启动 DSH Desktop，从应用内打开 DSH Desktop 专用终端，再在该终端中重新执行本命令；普通 PowerShell 无法直接使用 dsh。'
    }
}

# 下载默认分支源码压缩包并解析仓库根目录。
function Receive-Source {
    $script:TempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("dsh-bootstrap-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $script:TempDirectory -Force | Out-Null
    $archivePath = Join-Path $script:TempDirectory 'source.zip'

    Write-InitLog '正在下载初始化资源……'
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $archivePath -UseBasicParsing
    Expand-Archive -LiteralPath $archivePath -DestinationPath $script:TempDirectory -Force

    $script:SourceDirectory = Join-Path $script:TempDirectory 'dsh-desktop-bootstrap-main'
    if (-not (Test-Path -LiteralPath $script:SourceDirectory -PathType Container)) {
        throw '下载内容中未找到预期的仓库目录。'
    }
}

# 备份已有全局指令文件，并安装仓库中的 AGENTS.md。
function Install-AgentsFile {
    New-Item -ItemType Directory -Path $DshHome -Force | Out-Null
    $targetPath = Join-Path $DshHome 'AGENTS.md'

    if (Test-Path -LiteralPath $targetPath) {
        $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
        $backupPath = "$targetPath.backup.$timestamp"
        Copy-Item -LiteralPath $targetPath -Destination $backupPath -Force
        Write-InitLog "已备份现有 AGENTS.md：$backupPath"
    }

    Copy-Item -LiteralPath (Join-Path $script:SourceDirectory 'AGENTS.md') -Destination $targetPath -Force
    Write-InitLog '已安装全局 AGENTS.md。'
}

# 合并仓库 Skills；仓库不包含 .env，因此不会创建或覆盖用户私密配置。
function Install-UserSkills {
    $skillsTarget = Join-Path $DshHome 'skills'
    $skillsSource = Join-Path $script:SourceDirectory 'skills'
    New-Item -ItemType Directory -Path $skillsTarget -Force | Out-Null
    Copy-Item -Path (Join-Path $skillsSource '*') -Destination $skillsTarget -Recurse -Force
    Write-InitLog '已合并安装用户级 Skills，现有私密配置保持不变。'
}

# 执行外部命令，同时实时显示并返回合并后的标准输出与错误输出。
function Invoke-CapturedCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$ArgumentList
    )

    $previousErrorActionPreference = $ErrorActionPreference
    try {
        # Windows PowerShell 会把原生命令的标准错误包装成非终止错误，捕获期间必须允许其继续流入管道。
        $ErrorActionPreference = 'Continue'
        $output = @(& $FilePath @ArgumentList 2>&1 | ForEach-Object {
            $line = $_.ToString()
            Write-Host $line
            $line
        })
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = ($output -join [Environment]::NewLine)
    }
}

# 在 Desktop Profile 中批准 pnpm 待执行的依赖构建脚本。
function Approve-PendingBuilds {
    if (-not (Get-Command 'pnpm' -ErrorAction SilentlyContinue)) {
        Write-InitLog '错误输出要求执行 pnpm approve-builds，但当前终端中找不到 pnpm。'
        return $false
    }
    if (-not (Test-Path -LiteralPath $ProfileDirectory -PathType Container)) {
        Write-InitLog "错误输出要求执行 pnpm approve-builds，但未找到 $ProfileDirectory。"
        return $false
    }

    Write-InitLog '检测到 pnpm approve-builds 提示，正在自动执行 pnpm approve-builds --all……'
    Push-Location $ProfileDirectory
    try {
        & pnpm approve-builds --all
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        Pop-Location
    }
}

# 安装单个插件；检测到 approve-builds 提示时批准后仅重试一次。
function Install-DesktopPlugin {
    param([Parameter(Mandatory)][string]$Plugin)

    Write-InitLog "正在安装插件 $Plugin……"
    $result = Invoke-CapturedCommand -FilePath 'dsh' -ArgumentList @('plugin', 'add', '--profile', 'desktop', $Plugin)
    if ($result.ExitCode -eq 0) {
        return $true
    }

    if ($result.Output -match '(?i)pnpm\s+approve-builds') {
        if (-not (Approve-PendingBuilds)) {
            return $false
        }
        Write-InitLog "正在重试插件 $Plugin……"
        $retryResult = Invoke-CapturedCommand -FilePath 'dsh' -ArgumentList @('plugin', 'add', '--profile', 'desktop', $Plugin)
        return ($retryResult.ExitCode -eq 0)
    }

    return $false
}

# 顺序安装 README 声明的全部 Desktop Profile 插件并汇总失败项。
function Install-DesktopPlugins {
    $failedPlugins = @()
    foreach ($plugin in $Plugins) {
        if (-not (Install-DesktopPlugin -Plugin $plugin)) {
            Write-InitLog "插件安装失败：$plugin"
            $failedPlugins += $plugin
        }
    }

    if ($failedPlugins.Count -gt 0) {
        throw "一个或多个插件安装失败：$($failedPlugins -join ', ')"
    }
    Write-InitLog '已完成 Desktop Profile 插件安装。'
}

# 验证关键文件均已落盘，避免仅凭命令退出状态判断初始化成功。
function Test-Installation {
    $requiredPaths = @(
        (Join-Path $DshHome 'AGENTS.md'),
        (Join-Path $DshHome 'skills/commit/SKILL.md'),
        (Join-Path $DshHome 'skills/gpt-image-generator/SKILL.md')
    )

    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "验证失败，未找到 $requiredPath。"
        }
    }
    Write-InitLog '文件验证通过。'
}

# 删除本次下载产生的临时目录，不保留初始化中间文件。
function Remove-TemporaryFiles {
    if ($script:TempDirectory -and (Test-Path -LiteralPath $script:TempDirectory)) {
        Remove-Item -LiteralPath $script:TempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# 按固定顺序执行初始化流程，并确保最终清理临时目录。
function Start-Initialization {
    try {
        Test-Prerequisites
        Receive-Source
        Install-AgentsFile
        Install-UserSkills
        Install-DesktopPlugins
        Test-Installation
        Write-InitLog '初始化完成。首次使用 gpt-image-generator 时，Skill 会自动检测并询问缺失配置。请完全退出并重新启动 DSH Desktop。'
    }
    finally {
        Remove-TemporaryFiles
    }
}

try {
    Start-Initialization
}
catch {
    Write-Error "[DSH 初始化] 错误：$($_.Exception.Message)"
    exit 1
}
