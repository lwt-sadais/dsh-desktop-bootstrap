$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Repository = 'lwt-sadais/dsh-desktop-bootstrap'
$ArchiveUrl = "https://github.com/$Repository/archive/refs/heads/main.zip"
$DshHome = Join-Path $HOME '.dsh'
$ProfileDirectory = Join-Path $DshHome 'profiles/desktop'
$CompatPluginName = 'dsh-settings-alpha1-compat'
$CompatPluginDirectory = Join-Path $DshHome "plugins/$CompatPluginName"
$BetterSidebarFork = 'github:lwt-sadais/DSH-better-sidebar#ed28df8d66f1b9f9871fb358c6616289d23358f3'
$CodexPresetId = 'codex-mode'
$AgentPresetsDirectory = Join-Path $DshHome '.agent-presets'
$SettingsFile = Join-Path $DshHome 'settings.yaml'
$Plugins = @(
    [pscustomobject]@{ Name = $CompatPluginName; Source = "link:$CompatPluginDirectory" },
    [pscustomobject]@{ Name = '@linxin666/dsh-web-all'; Source = '@linxin666/dsh-web-all@0.3.9' },
    [pscustomobject]@{ Name = 'dsh-better-sidebar'; Source = $BetterSidebarFork },
    [pscustomobject]@{ Name = 'dsh-at-file'; Source = 'github:lwt-sadais/dsh-at-file#6dbc6209a881c97ae094081e5fb8899a9f4b1b05' },
    [pscustomobject]@{ Name = '@muwinds/dsh-archived-sessions'; Source = 'github:lwt-sadais/dsh-archived-sessions#f65469cad684c674d56c6646183149dc2f568654' },
    [pscustomobject]@{ Name = 'dsh-git-diff'; Source = 'github:lwt-sadais/dsh-git-diff#69c8458d3eefc507f4512983934cc046b4e736dd' },
    [pscustomobject]@{ Name = 'dsh-git-history'; Source = 'github:lwt-sadais/dsh-git-history#cf22d3e2c839d38f63064568021cdc2b854dd41d' },
    [pscustomobject]@{ Name = 'dsh-local-file-reference'; Source = 'github:lwt-sadais/dsh-local-file-reference#4ccc956cc14b1e2d4c19634287b52dcfc3a3c955' },
    [pscustomobject]@{ Name = 'dsh-plan-review-card'; Source = 'github:lwt-sadais/dsh-plan-review-card#43d8f2ddf55512f181c26a2e09fc63ece8c11377' },
    [pscustomobject]@{ Name = 'dsh-reasoning-efforts'; Source = 'github:lwt-sadais/dsh-reasoning-efforts#eb66af3df2c99e5d5014bcedd61abb7d7c61a7d3' }
)
$ObsoletePluginNames = @('@linxin666/dsh-web-ui-all')
$MinimumReleaseAgeExcludes = @(
    '@linxin666/dsh-client-ui-plugin-manager@0.3.9',
    '@linxin666/dsh-client-ui-community-plugins@0.3.9',
    '@linxin666/dsh-client-ui-market@0.3.9',
    '@linxin666/dsh-client-ui-task-board@0.3.9',
    '@linxin666/dsh-client-ui-git-graph@0.3.9',
    '@linxin666/dsh-perf@0.3.9',
    '@linxin666/dsh-pet@0.3.9',
    '@linxin666/dsh-remote-web-ui@0.3.9',
    '@linxin666/dsh-ssh@0.3.9',
    '@linxin666/dsh-tool-describe-image@0.3.9',
    '@linxin666/dsh-liangshen@0.3.9',
    '@linxin666/dsh-client-ui-skill-explorer@0.3.9',
    '@linxin666/dsh-desktop-launcher@0.3.9',
    '@linxin666/dsh-doctor@0.3.9',
    '@linxin666/dsh-usage@0.3.9',
    '@linxin666/dsh-client-ui-web-ui-settings@0.3.9',
    '@linxin666/dsh-client-ui-skin-center@0.3.9',
    '@linxin666/dsh-web-all@0.3.9'
)
$script:TempDirectory = $null
$script:SourceDirectory = $null
$script:YamlModule = $null

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

# 兼容 Desktop 2.0.1 的 Profile 依赖布局和 2.0.2 起由桌面应用提供依赖的布局。
function Resolve-YamlModule {
    $profileYamlModule = Join-Path $ProfileDirectory 'node_modules/yaml'
    if (Test-Path -LiteralPath (Join-Path $profileYamlModule 'package.json') -PathType Leaf) {
        $script:YamlModule = $profileYamlModule
        return
    }

    $resolvedPackage = (& node -p "require.resolve('yaml/package.json')" 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $resolvedPackage) {
        throw "当前 DSH Desktop 运行环境无法解析 yaml 依赖，无法安全更新 $SettingsFile。"
    }
    $resolvedModule = Split-Path -Parent $resolvedPackage
    if (-not (Test-Path -LiteralPath (Join-Path $resolvedModule 'package.json') -PathType Leaf)) {
        throw "解析到的 yaml 依赖无效：$resolvedModule。"
    }
    $script:YamlModule = $resolvedModule
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

# 安装仓库内置的 Harness alpha.1 设置 API 兼容插件。
function Install-SettingsCompatPlugin {
    $sourcePath = Join-Path $script:SourceDirectory "plugins/$CompatPluginName"
    if (-not (Test-Path -LiteralPath (Join-Path $sourcePath 'package.json') -PathType Leaf)) {
        throw "兼容插件源码不完整：$sourcePath。"
    }

    New-Item -ItemType Directory -Path $CompatPluginDirectory -Force | Out-Null
    Copy-Item -Path (Join-Path $sourcePath '*') -Destination $CompatPluginDirectory -Recurse -Force
    Write-InitLog '已安装 Harness alpha.1 设置 API 兼容插件。'
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
        $env:DSH_YAML_MODULE = $script:YamlModule
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

# 始终按 UTF-8 读取 JSON，避免 Windows PowerShell 5.1 使用系统 ANSI 代码页。
function Read-Utf8Json {
    param([Parameter(Mandatory)][string]$LiteralPath)

    return Get-Content -LiteralPath $LiteralPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

# 以无 BOM UTF-8 原子写回 JSON，避免 Windows PowerShell 5.1 的 utf8 编码破坏 DSH Profile。
function Write-Utf8Json {
    param(
        [Parameter(Mandatory)][string]$LiteralPath,
        [Parameter(Mandatory)]$InputObject
    )

    $operationId = "$PID-$([guid]::NewGuid().ToString('N'))"
    $temporaryPath = "${LiteralPath}.tmp-$operationId"
    $backupPath = "${LiteralPath}.backup-$operationId"
    $content = (ConvertTo-Json -InputObject $InputObject -Depth 20) + [Environment]::NewLine
    $utf8WithoutBom = [System.Text.UTF8Encoding]::new($false)
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $content, $utf8WithoutBom)
        [System.IO.File]::Replace($temporaryPath, $LiteralPath, $backupPath)
    }
    finally {
        foreach ($cleanupPath in @($temporaryPath, $backupPath)) {
            if (Test-Path -LiteralPath $cleanupPath) {
                Remove-Item -LiteralPath $cleanupPath -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

# 显式枚举对象属性名，兼容 Windows PowerShell 严格模式下不支持集合成员枚举的情况。
function Get-ObjectPropertyNames {
    param([Parameter(Mandatory)]$InputObject)

    return @($InputObject.PSObject.Properties | ForEach-Object { $_.Name })
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

    Write-InitLog '已保留现有策略，并加入 Web UI 0.3.9 的精确发布时间豁免。'
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

# 执行一次插件卸载或安装；依赖构建被拦截时完成审批并仅重试原命令一次。
function Invoke-PluginOperation {
    param(
        [Parameter(Mandatory)][ValidateSet('add', 'remove')][string]$Action,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$Targets
    )

    $arguments = @('plugin', '--profile', 'desktop', $Action) + $Targets
    Write-InitLog "正在$Label Desktop Profile 插件：$($Targets -join ', ')……"
    $result = Invoke-CapturedCommand -FilePath 'dsh' -ArgumentList $arguments
    if ($result.ExitCode -eq 0) {
        Write-InitLog "已完成 Desktop Profile 插件$Label。"
        return
    }

    if ($result.Output -match '(?i)pnpm\s+approve-builds|ERR_PNPM_IGNORED_BUILDS') {
        if (-not (Approve-PendingBuildsExceptCpuFeatures -Output $result.Output)) {
            throw 'Desktop Profile 插件依赖构建审批失败。请查看上方 pnpm 输出。'
        }
        Write-InitLog "正在重试 Desktop Profile 插件$Label……"
        $retryResult = Invoke-CapturedCommand -FilePath 'dsh' -ArgumentList $arguments
        if ($retryResult.ExitCode -eq 0) {
            Write-InitLog "已完成 Desktop Profile 插件$Label。"
            return
        }
    }

    throw "Desktop Profile 插件${Label}失败：$($Targets -join ', ')"
}

# 先卸载所有已存在的目标或废弃插件，再按完整来源统一重新安装目标插件。
function Install-DesktopPlugins {
    $manifestPath = Join-Path $ProfileDirectory 'package.json'
    $dependencyNames = @()
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        $manifest = Read-Utf8Json -LiteralPath $manifestPath
        $dependencies = $manifest.PSObject.Properties['dependencies']
        if ($null -ne $dependencies) {
            $dependencyNames = Get-ObjectPropertyNames -InputObject $dependencies.Value
        }
    }

    $managedPluginNames = @($Plugins | ForEach-Object { $_.Name }) + $ObsoletePluginNames
    $removeNames = @($managedPluginNames | Where-Object { $_ -in $dependencyNames } | Select-Object -Unique)
    if ($removeNames.Count -gt 0) {
        Invoke-PluginOperation -Action 'remove' -Label '卸载现有' -Targets $removeNames
    }
    else {
        Write-InitLog '当前没有已安装的目标或废弃插件需要卸载。'
    }

    $installSources = @($Plugins | ForEach-Object { $_.Source })
    Invoke-PluginOperation -Action 'add' -Label '安装' -Targets $installSources
}

# 确保兼容层先于会调用新设置 API 的第三方聚合包加载。
function Set-SettingsCompatBundleOrder {
    $manifestPath = Join-Path $ProfileDirectory 'package.json'
    $profile = Read-Utf8Json -LiteralPath $manifestPath
    $bundlesProperty = $profile.dsh.profile.PSObject.Properties['bundles']
    if ($null -eq $bundlesProperty) {
        throw 'Profile manifest 缺少 dsh.profile.bundles。'
    }

    $bundles = [System.Collections.Generic.List[string]]::new()
    foreach ($bundle in @($bundlesProperty.Value)) { $bundles.Add([string]$bundle) }
    $compatIndex = $bundles.IndexOf($CompatPluginName)
    $webAllIndex = $bundles.IndexOf('@linxin666/dsh-web-all')
    if ($compatIndex -lt 0 -or $webAllIndex -lt 0) {
        throw 'Profile Bundle 列表缺少兼容插件或 dsh-web-all。'
    }
    if ($compatIndex -gt $webAllIndex) {
        $bundles.RemoveAt($compatIndex)
        $bundles.Insert($webAllIndex, $CompatPluginName)
        $profile.dsh.profile.bundles = @($bundles)
        Write-Utf8Json -LiteralPath $manifestPath -InputObject $profile
    }
    Write-InitLog '已确认设置兼容插件先于 Web UI 聚合包加载。'
}

# 验证关键文件均已落盘，避免仅凭命令退出状态判断初始化成功。
function Test-Installation {
    $requiredPaths = @(
        (Join-Path $DshHome 'AGENTS.md'),
        (Join-Path $DshHome 'skills/commit/SKILL.md'),
        (Join-Path $DshHome 'skills/gpt-image-generator/SKILL.md'),
        (Join-Path $AgentPresetsDirectory "$CodexPresetId/agent.cordis.yml"),
        (Join-Path $AgentPresetsDirectory "$CodexPresetId/preset.yml"),
        (Join-Path $CompatPluginDirectory 'package.json'),
        (Join-Path $CompatPluginDirectory 'index.js'),
        (Join-Path $CompatPluginDirectory 'cordis.patch.yml')
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
        $env:DSH_YAML_MODULE = $script:YamlModule
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
    $profileManifestPath = Join-Path $ProfileDirectory 'package.json'
    $profilePrefix = @(Get-Content -LiteralPath $profileManifestPath -Encoding Byte -TotalCount 3)
    if ($profilePrefix.Count -eq 3 -and $profilePrefix[0] -eq 0xEF -and $profilePrefix[1] -eq 0xBB -and $profilePrefix[2] -eq 0xBF) {
        throw '验证失败，Desktop Profile manifest 包含 UTF-8 BOM。'
    }
    $profileManifest = Read-Utf8Json -LiteralPath $profileManifestPath
    $profileDependencies = $profileManifest.PSObject.Properties['dependencies']
    $profileDsh = $profileManifest.PSObject.Properties['dsh']
    $profileSettings = if ($null -ne $profileDsh) { $profileDsh.Value.PSObject.Properties['profile'] } else { $null }
    if ($null -eq $profileDependencies -or $null -eq $profileSettings) {
        throw '验证失败，Desktop Profile manifest 缺少 dependencies 或 dsh.profile。'
    }
    $dependencyNames = Get-ObjectPropertyNames -InputObject $profileDependencies.Value
    $bundles = $profileSettings.Value.PSObject.Properties['bundles']
    $bundleNames = if ($null -ne $bundles) { @($bundles.Value) } else { @() }
    $compatIndex = [array]::IndexOf($bundleNames, $CompatPluginName)
    $webAllIndex = [array]::IndexOf($bundleNames, '@linxin666/dsh-web-all')
    if ($compatIndex -lt 0 -or $webAllIndex -lt 0 -or $compatIndex -gt $webAllIndex) {
        throw '验证失败，设置兼容插件必须位于 dsh-web-all 之前。'
    }
    foreach ($plugin in $Plugins) {
        if ($plugin.Name -notin $dependencyNames) {
            throw "验证失败，Profile dependencies 缺少 $($plugin.Name)。"
        }
        $packageDirectory = Join-Path $ProfileDirectory ("node_modules/" + $plugin.Name)
        $packageManifestPath = Join-Path $packageDirectory 'package.json'
        if (-not (Test-Path -LiteralPath $packageManifestPath -PathType Leaf)) {
            throw "验证失败，未找到插件产物 $packageManifestPath。"
        }
        $packageManifest = Read-Utf8Json -LiteralPath $packageManifestPath
        $packageDsh = $packageManifest.PSObject.Properties['dsh']
        $bundle = if ($null -ne $packageDsh) { $packageDsh.Value.PSObject.Properties['bundle'] } else { $null }
        if ($null -ne $bundle -and $null -ne $bundle.Value.PSObject.Properties['patch'] -and $plugin.Name -notin $bundleNames) {
            throw "验证失败，Profile Bundle 列表缺少 $($plugin.Name)。"
        }
        if ($plugin.Name -eq 'dsh-plan-review-card') {
            $packageExports = $packageManifest.PSObject.Properties['exports']
            $client = if ($null -ne $packageDsh) { $packageDsh.Value.PSObject.Properties['client'] } else { $null }
            $clientExportProperty = if ($null -ne $packageExports) { $packageExports.Value.PSObject.Properties['./client'] } else { $null }
            if ($null -eq $client -or $null -eq $clientExportProperty) {
                throw '验证失败，dsh-plan-review-card 缺少 Client 声明或导出。'
            }
            $hostEntry = Join-Path $packageDirectory $packageManifest.main
            $clientExport = $clientExportProperty.Value
            $clientEntryValue = if ($clientExport -is [string]) { $clientExport } else { $clientExport.default }
            $clientEntry = Join-Path $packageDirectory $clientEntryValue
            if (-not (Test-Path -LiteralPath $hostEntry -PathType Leaf) -or -not (Test-Path -LiteralPath $clientEntry -PathType Leaf)) {
                throw '验证失败，dsh-plan-review-card 的 Host 或 Client 构建入口不存在。'
            }
        }
    }
    Write-InitLog '文件、默认 Agent 预设与 Desktop Profile 插件验证通过。'
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
        Resolve-YamlModule
        Receive-Source
        Install-AgentsFile
        Install-UserSkills
        Install-SettingsCompatPlugin
        Install-AgentPresets
        Set-DefaultAgentPreset
        Add-MinimumReleaseAgeExcludes
        Install-DesktopPlugins
        Set-SettingsCompatBundleOrder
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
