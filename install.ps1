$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Repository = 'lwt-sadais/dsh-desktop-bootstrap'
$ArchiveUrl = "https://github.com/$Repository/archive/refs/heads/main.zip"
$DshHome = Join-Path $HOME '.dsh'
$ProfileDirectory = Join-Path $DshHome 'profiles/desktop'
$BetterSidebarFork = 'github:lwt-sadais/DSH-better-sidebar#0465d33db156bbeaf3fdb8e944bc9e7818bdb613'
$BetterSidebarBuildKey = 'dsh-better-sidebar@https://codeload.github.com/lwt-sadais/DSH-better-sidebar/tar.gz/0465d33db156bbeaf3fdb8e944bc9e7818bdb613'
$CodexPresetId = 'codex-mode'
$AgentPresetsDirectory = Join-Path $DshHome '.agent-presets'
$SettingsFile = Join-Path $DshHome 'settings.yaml'
$Plugins = @(
    '@linxin666/dsh-web-ui-all@0.2.7',
    $BetterSidebarFork,
    'github:FSMargoo/dsh-at-file',
    'github:MuWinds/dsh-archived-sessions',
    'github:lwt-sadais/dsh-git-diff',
    'github:lwt-sadais/dsh-local-file-reference',
    'github:lwt-sadais/dsh-reasoning-efforts'
)
$MinimumReleaseAgeExcludes = @(
    '@linxin666/dsh-chat-recovery@0.2.7',
    '@linxin666/dsh-client-ui-aionui-panel@0.2.7',
    '@linxin666/dsh-client-ui-community-plugins@0.2.7',
    '@linxin666/dsh-client-ui-git-graph@0.2.7',
    '@linxin666/dsh-client-ui-plugin-manager@0.2.7',
    '@linxin666/dsh-client-ui-skill-explorer@0.2.7',
    '@linxin666/dsh-client-ui-skin-center@0.2.7',
    '@linxin666/dsh-client-ui-task-board@0.2.7',
    '@linxin666/dsh-client-ui-web-ui-settings@0.2.7',
    '@linxin666/dsh-desktop-launcher@0.2.7',
    '@linxin666/dsh-liangshen@0.2.7',
    '@linxin666/dsh-pet@0.2.7',
    '@linxin666/dsh-remote-web-ui@0.2.7',
    '@linxin666/dsh-skins@0.2.7',
    '@linxin666/dsh-ssh@0.2.7',
    '@linxin666/dsh-tool-describe-image@0.2.7',
    '@linxin666/dsh-web-ui-all@0.2.7'
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
    if (-not (Get-Command 'node' -ErrorAction SilentlyContinue)) {
        throw '当前终端中找不到 node，无法安全更新 DSH 用户设置。'
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

# 备份已有同名 Agent 预设，并安装仓库中的 Codex 模式。
function Install-AgentPresets {
    $sourcePath = Join-Path $script:SourceDirectory "agent-presets/$CodexPresetId"
    $targetPath = Join-Path $AgentPresetsDirectory $CodexPresetId
    $compositionPath = Join-Path $sourcePath 'agent.cordis.yml'
    $metadataPath = Join-Path $sourcePath 'preset.yml'

    if (-not (Test-Path -LiteralPath $compositionPath -PathType Leaf) -or -not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        throw '初始化资源中缺少 Codex 模式预设。'
    }
    New-Item -ItemType Directory -Path $AgentPresetsDirectory -Force | Out-Null

    if (Test-Path -LiteralPath $targetPath) {
        $timestamp = Get-Date -Format 'yyyyMMddHHmmss'
        $backupPath = "$targetPath.backup.$timestamp"
        Copy-Item -LiteralPath $targetPath -Destination $backupPath -Recurse -Force
        Write-InitLog "已备份现有 Codex 模式：$backupPath"
        Remove-Item -LiteralPath $targetPath -Recurse -Force
    }

    Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Recurse -Force
    Write-InitLog '已安装 Codex 模式。'
}

# 保留其余用户设置，仅将新会话的默认 Agent 预设设为 Codex 模式。
function Set-DefaultAgentPreset {
    $yamlModule = Join-Path $ProfileDirectory 'node_modules/yaml'
    if (-not (Test-Path -LiteralPath $yamlModule -PathType Container)) {
        throw "未找到 Desktop Profile 的 yaml 依赖，无法安全更新 $SettingsFile。"
    }
    New-Item -ItemType Directory -Path $DshHome -Force | Out-Null

    $nodeScript = @'
const { readFile, rename, rm, writeFile } = require('node:fs/promises')
const { pathToFileURL } = require('node:url')

;(async () => {
  const settingsFile = process.env.DSH_SETTINGS_FILE
  const yamlModule = process.env.DSH_YAML_MODULE
  const presetId = process.env.DSH_CODEX_PRESET_ID
  const { parseDocument } = await import(pathToFileURL(require.resolve(yamlModule)).href)
  let source = ''
  try {
    source = await readFile(settingsFile, 'utf8')
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error
  }
  const document = parseDocument(source)
  if (document.errors.length > 0) throw document.errors[0]
  document.setIn(['agent-presets', 'default'], presetId)
  const temporaryFile = `${settingsFile}.tmp-${process.pid}`
  try {
    await writeFile(temporaryFile, document.toString(), { flag: 'wx', mode: 0o600 })
    await rename(temporaryFile, settingsFile)
  } catch (error) {
    await rm(temporaryFile, { force: true })
    throw error
  }
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
'@

    $previousSettingsFile = $env:DSH_SETTINGS_FILE
    $previousYamlModule = $env:DSH_YAML_MODULE
    $previousPresetId = $env:DSH_CODEX_PRESET_ID
    try {
        $env:DSH_SETTINGS_FILE = $SettingsFile
        $env:DSH_YAML_MODULE = $yamlModule
        $env:DSH_CODEX_PRESET_ID = $CodexPresetId
        $nodeScript | & node
        if ($LASTEXITCODE -ne 0) {
            throw '设置默认 Agent 预设失败。'
        }
    }
    finally {
        $env:DSH_SETTINGS_FILE = $previousSettingsFile
        $env:DSH_YAML_MODULE = $previousYamlModule
        $env:DSH_CODEX_PRESET_ID = $previousPresetId
    }
    Write-InitLog '已将默认 Agent 预设设为 Codex 模式。'
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

# 将已核对的 Web UI 精确版本加入最短发布时间豁免，同时保留用户已有配置。
function Add-MinimumReleaseAgeExcludes {
    if (-not (Get-Command 'pnpm' -ErrorAction SilentlyContinue)) {
        throw '当前终端中找不到 pnpm，无法配置依赖供应链策略。'
    }
    if (-not (Test-Path -LiteralPath $ProfileDirectory -PathType Container)) {
        throw "未找到 Desktop Profile 目录 $ProfileDirectory。"
    }

    Push-Location $ProfileDirectory
    try {
        $currentJson = (& pnpm config get --location project --json minimumReleaseAgeExclude 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw '读取 Desktop Profile 的 minimumReleaseAgeExclude 配置失败。'
        }

        $currentExcludes = @()
        if ($currentJson) {
            $currentExcludes = @([string[]]($currentJson | ConvertFrom-Json))
        }
        $mergedExcludes = [string[]]@(@($currentExcludes) + @($MinimumReleaseAgeExcludes) | Select-Object -Unique)
        $mergedJson = ConvertTo-Json -InputObject $mergedExcludes -Compress

        # Windows 的 pnpm 命令垫片经由 shell 转发参数，JSON 双引号需要保留转义。
        $escapedJson = $mergedJson.Replace('"', '\"')
        & pnpm config set --location project --json minimumReleaseAgeExclude $escapedJson
        if ($LASTEXITCODE -ne 0) {
            throw '写入 Desktop Profile 的 minimumReleaseAgeExclude 配置失败。'
        }

        $verifiedJson = (& pnpm config get --location project --json minimumReleaseAgeExclude 2>$null | Out-String).Trim()
        $verifiedExcludes = @([string[]]($verifiedJson | ConvertFrom-Json))
        foreach ($requiredExclude in $MinimumReleaseAgeExcludes) {
            if ($requiredExclude -notin $verifiedExcludes) {
                throw "供应链策略配置验证失败，缺少精确豁免 $requiredExclude。"
            }
        }
    }
    finally {
        Pop-Location
    }

    Write-InitLog '已保留现有策略，并加入 Web UI 0.2.7 的精确发布时间豁免。'
}

# 拒绝可选的 cpu-features 原生构建，再批准其余全部待审批依赖脚本。
function Approve-PendingBuildsExceptCpuFeatures {
    param([Parameter(Mandatory)][string]$Output)

    if (-not (Get-Command 'pnpm' -ErrorAction SilentlyContinue)) {
        throw '当前终端中找不到 pnpm，无法批准依赖构建脚本。'
    }
    if (-not (Test-Path -LiteralPath $ProfileDirectory -PathType Container)) {
        throw "未找到 Desktop Profile 目录 $ProfileDirectory。"
    }

    Push-Location $ProfileDirectory
    try {
        if ($Output -match '(?m)(?:^|[\s,:])cpu-features(?:@|[\s,]|$)') {
            Write-InitLog '正在拒绝可选原生依赖 cpu-features 的构建脚本……'
            & pnpm approve-builds '!cpu-features'
            if ($LASTEXITCODE -ne 0) {
                return $false
            }
        }

        Write-InitLog '正在批准除 cpu-features 外的全部待审批依赖构建脚本……'
        & pnpm approve-builds --all
        return ($LASTEXITCODE -eq 0)
    }
    finally {
        Pop-Location
    }
}

# 允许固定提交的 Fork 执行 prepare 构建；键精确到 codeload URL，不放宽其它 GitHub 包。
function Enable-BetterSidebarBuild {
    if (-not (Get-Command 'pnpm' -ErrorAction SilentlyContinue)) {
        throw '当前终端中找不到 pnpm，无法批准 better-sidebar Fork 构建。'
    }

    Push-Location $ProfileDirectory
    try {
        $currentJson = (& pnpm config get --location project --json allowBuilds 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0) {
            throw '读取 Desktop Profile 的 allowBuilds 失败。'
        }
        $merged = [ordered]@{}
        if ($currentJson -and $currentJson -ne 'null' -and $currentJson -ne 'undefined') {
            $current = $currentJson | ConvertFrom-Json
            foreach ($property in $current.PSObject.Properties) {
                $merged[$property.Name] = $property.Value
            }
        }
        $merged[$BetterSidebarBuildKey] = $true
        $mergedJson = ConvertTo-Json -InputObject $merged -Compress
        $escapedJson = $mergedJson.Replace('"', '\"')
        & pnpm config set --location project --json allowBuilds $escapedJson
        if ($LASTEXITCODE -ne 0) {
            throw '写入 Desktop Profile 的 better-sidebar allowBuilds 失败。'
        }
        $verifiedJson = (& pnpm config get --location project --json allowBuilds 2>$null | Out-String).Trim()
        $verified = $verifiedJson | ConvertFrom-Json
        if ($verified.$BetterSidebarBuildKey -ne $true) {
            throw "better-sidebar allowBuilds 验证失败，读取到：$verifiedJson"
        }
    }
    finally {
        Pop-Location
    }

    Write-InitLog '已批准固定 better-sidebar Fork 提交执行构建脚本。'
}

# 在单个恢复事务中安装全部插件；忽略 cpu-features 后批准其余全部并重试一次。
function Install-DesktopPlugins {
    $arguments = @('plugin', 'add', '--profile', 'desktop') + $Plugins

    Write-InitLog "正在安装 Desktop Profile 插件：$($Plugins -join ', ')……"
    $result = Invoke-CapturedCommand -FilePath 'dsh' -ArgumentList $arguments
    if ($result.ExitCode -eq 0) {
        Write-InitLog '已完成 Desktop Profile 插件安装。'
        return
    }

    if ($result.Output -match '(?i)pnpm\s+approve-builds|ERR_PNPM_IGNORED_BUILDS') {
        if (-not (Approve-PendingBuildsExceptCpuFeatures -Output $result.Output)) {
            throw 'Desktop Profile 插件依赖构建审批失败。请查看上方 pnpm 输出。'
        }
        Write-InitLog '正在重试 Desktop Profile 插件批量安装……'
        $retryResult = Invoke-CapturedCommand -FilePath 'dsh' -ArgumentList $arguments
        if ($retryResult.ExitCode -eq 0) {
            Write-InitLog '已完成 Desktop Profile 插件安装。'
            return
        }
    }

    throw "Desktop Profile 插件安装失败：$($Plugins -join ', ')"
}

# 验证关键文件均已落盘，避免仅凭命令退出状态判断初始化成功。
function Test-Installation {
    $requiredPaths = @(
        (Join-Path $DshHome 'AGENTS.md'),
        (Join-Path $DshHome 'skills/commit/SKILL.md'),
        (Join-Path $DshHome 'skills/gpt-image-generator/SKILL.md'),
        (Join-Path $AgentPresetsDirectory "$CodexPresetId/agent.cordis.yml"),
        (Join-Path $AgentPresetsDirectory "$CodexPresetId/preset.yml")
    )

    foreach ($requiredPath in $requiredPaths) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "验证失败，未找到 $requiredPath。"
        }
    }

    $verifyScript = @'
const { readFile } = require('node:fs/promises')
const { pathToFileURL } = require('node:url')

;(async () => {
  const { parse } = await import(pathToFileURL(require.resolve(process.env.DSH_YAML_MODULE)).href)
  const settings = parse(await readFile(process.env.DSH_SETTINGS_FILE, 'utf8'))
  if (settings?.['agent-presets']?.default !== process.env.DSH_CODEX_PRESET_ID) process.exit(1)
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
'@
    $previousSettingsFile = $env:DSH_SETTINGS_FILE
    $previousYamlModule = $env:DSH_YAML_MODULE
    $previousPresetId = $env:DSH_CODEX_PRESET_ID
    try {
        $env:DSH_SETTINGS_FILE = $SettingsFile
        $env:DSH_YAML_MODULE = Join-Path $ProfileDirectory 'node_modules/yaml'
        $env:DSH_CODEX_PRESET_ID = $CodexPresetId
        $verifyScript | & node
        if ($LASTEXITCODE -ne 0) {
            throw '验证失败，默认 Agent 预设不是 Codex 模式。'
        }
    }
    finally {
        $env:DSH_SETTINGS_FILE = $previousSettingsFile
        $env:DSH_YAML_MODULE = $previousYamlModule
        $env:DSH_CODEX_PRESET_ID = $previousPresetId
    }
    Write-InitLog '文件与默认 Agent 预设验证通过。'
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
        Install-AgentPresets
        Set-DefaultAgentPreset
        Add-MinimumReleaseAgeExcludes
        Enable-BetterSidebarBuild
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
