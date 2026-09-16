$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Repository = 'lwt-sadais/dsh-desktop-bootstrap'
# 分支阶段自包含：脚本与资源都取自本分支；合并回 main 时改回 'main'。
$SourceRef = 'adapt-desktop-2.0.10'
$ArchiveUrl = "https://github.com/$Repository/archive/refs/heads/$SourceRef.zip"
# v2.0.7 起桌面支持自定义数据目录；优先环境变量 DSH_HOME，最后回退 ~/.dsh。
$DshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
$ProfileDirectory = Join-Path $DshHome 'profiles/desktop'
$BetterSidebarUpstream = 'github:omdsh-dev/DSH-better-sidebar#8753096a583ff2891d57a0074f1ac71cd5c6003e'
$CodexPresetId = 'codex-mode'
$AgentPresetsDirectory = Join-Path $DshHome '.agent-presets'
$SettingsFile = Join-Path $DshHome 'settings.yaml'
$Plugins = @(
    [pscustomobject]@{ Name = 'dsh-git-diff'; Source = 'github:lwt-sadais/dsh-git-diff#3d955d2ab876d68faa1fa1a58a54462b4dde1465' },
    [pscustomobject]@{ Name = 'dsh-git-history'; Source = 'github:lwt-sadais/dsh-git-history#31617eeb709a25e53c52928c4a5f2f14179d8247' },
    [pscustomobject]@{ Name = 'dsh-local-file-reference'; Source = 'github:lwt-sadais/dsh-local-file-reference#4dba61891126af8ae71cd327a8f9b72124450e93' },
    [pscustomobject]@{ Name = 'dsh-plan-review-card'; Source = 'github:lwt-sadais/dsh-plan-review-card#07c3fa29e3b33272930f1fb9776469cf497df81e' },
    [pscustomobject]@{ Name = 'dsh-reasoning-efforts'; Source = 'github:lwt-sadais/dsh-reasoning-efforts#9332e2365d6ecccf33e47f87f345c56b12b92b81' },
    [pscustomobject]@{ Name = 'dsh-better-sidebar'; Source = $BetterSidebarUpstream },
    [pscustomobject]@{ Name = '@muwinds/dsh-archived-sessions'; Source = 'github:MuWinds/dsh-archived-sessions#5654381f0f54a4ada786bde569378235e2df01bf' },
    [pscustomobject]@{ Name = '@linxin666/dsh-web-all'; Source = '@linxin666/dsh-web-all@0.3.22' },
    [pscustomobject]@{ Name = 'dsh-free-search'; Source = 'dsh-free-search@0.4.28' }
)
$ObsoletePluginNames = @('@linxin666/dsh-web-ui-all', 'dsh-settings-alpha1-compat', 'dsh-at-file')
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
    if (-not (Get-Command 'pnpm' -ErrorAction SilentlyContinue)) {
        throw '当前终端中找不到 pnpm，无法管理 Desktop Profile 插件。'
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

    # 归档顶层目录名随 SourceRef 变化（分支名会拼入目录名），按固定前缀探测唯一目录。
    $extracted = @(Get-ChildItem -LiteralPath $script:TempDirectory -Directory -Filter 'dsh-desktop-bootstrap-*')
    if ($extracted.Count -ne 1) {
        throw '下载内容中未找到预期的仓库目录。'
    }
    $script:SourceDirectory = $extracted[0].FullName
}

# 安装仓库中的全局指令文件 AGENTS.md。
function Install-AgentsFile {
    New-Item -ItemType Directory -Path $DshHome -Force | Out-Null
    $targetPath = Join-Path $DshHome 'AGENTS.md'

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

# 安装仓库中的 Codex 模式 Agent 预设。
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
        if (Test-Path -LiteralPath $LiteralPath) {
            [System.IO.File]::Replace($temporaryPath, $LiteralPath, $backupPath)
        }
        else {
            # Replace 要求目标文件已存在；全新文件直接落入正式路径。
            [System.IO.File]::Move($temporaryPath, $LiteralPath)
        }
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

# 解析 pnpm 构建拦截输出中的依赖键，写入 Desktop Profile 的 pnpm-workspace.yaml allowBuilds 布尔映射。
# 2.0.x 已移除 pnpm approve-builds 流程与 minimumReleaseAgeExclude 机制：桌面在 pnpm 边界统一传
# --config.minimumReleaseAge=0，构建白名单由 allowBuilds 控制，映射值 true 允许、false 拒绝；
# cpu-features 保持既有拒绝状态（无记录时不写入，默认即拒绝）。
function Approve-PendingBuildsExceptCpuFeatures {
    param([Parameter(Mandatory)][string]$Output)

    if (-not (Test-Path -LiteralPath $ProfileDirectory -PathType Container)) {
        throw "未找到 Desktop Profile 目录 $ProfileDirectory。"
    }

    $candidates = @()
    # 汇总行可能带 [ERR_PNPM_IGNORED_BUILDS] 前缀，不作行首锚定；键形如 cloudflared@0.7.3。
    foreach ($match in [regex]::Matches($Output, '(?im)Ignored build scripts?:\s*(?<list>[^\r\n]+)$')) {
        $candidates += @($match.Groups['list'].Value -split '[,;，；\s]+' |
            ForEach-Object { $_.Trim().Trim('"''`') -replace '@[0-9][0-9A-Za-z.-]*$', '' } |
            Where-Object { $_ -match '^[A-Za-z@][A-Za-z0-9._/@-]*$' })
    }
    # git-hosted 包在解析阶段被拦截（ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED），
    # pnpm 建议块的键形如 包名@https://codeload.github.com/…: true。
    foreach ($match in [regex]::Matches($Output, '(?im)allowBuilds:\s*\r?\n\s*[''"]?(?<key>.+?)[''"]?:\s*true\s*$')) {
        $candidates += @($match.Groups['key'].Value.Trim())
    }
    $noiseWords = @('Done', 'Progress', 'Ignored', 'builds', 'pnpm-workspace.yaml', 'allowBuilds', 'node_modules')
    $keys = @($candidates | Where-Object { $_ -notin $noiseWords } | Select-Object -Unique)
    if ($keys.Count -eq 0) {
        Write-InitLog 'pnpm 输出中未识别到 allowBuilds 依赖键，请按上方提示手工补齐后重跑。'
        return $false
    }

    Write-InitLog "正在把依赖键写入 Profile pnpm-workspace.yaml allowBuilds（cpu-features 保持拒绝）：$($keys -join ', ')……"
    $nodeScript = @'
const { readFile, rename, rm, writeFile } = require('node:fs/promises')
const path = require('node:path')

;(async () => {
  const workspaceFile = path.join(process.env.DSH_PROFILE_DIR, 'pnpm-workspace.yaml')
  const requested = process.argv.slice(2)
  let source = ''
  try { source = await readFile(workspaceFile, 'utf8') } catch (error) { if (error?.code !== 'ENOENT') throw error }
  const allowed = new Map()
  // 兼容两种历史格式：allowBuilds 布尔映射（pnpm 11）与早期依赖键列表。
  const block = source.match(/^allowBuilds:[^\n]*\n((?:[ \t]+[^\n]*\n?)*)/m)
  if (block) {
    for (const line of block[1].split('\n')) {
      // 键可含冒号（git-hosted 键内嵌 URL），按行尾的 ": true/false" 切分；引号键去引号。
      const mapped = line.match(/^[ \t]+(.+?):\s*(true|false)\s*$/)
      if (mapped) { allowed.set(mapped[1].trim().replace(/^["']|["']$/g, ''), mapped[2] === 'true'); continue }
      const listed = line.match(/^[ \t]+-[ \t]*['"]?([^'"\n]+?)['"]?\s*$/)
      if (listed) allowed.set(listed[1].trim(), true)
    }
  }
  let added = 0
  for (const key of requested) {
    if (allowed.has(key)) continue
    // cpu-features 显式写入 false：明确拒绝后 pnpm 不再在每次安装时报 ERR_PNPM_IGNORED_BUILDS。
    allowed.set(key, key !== 'cpu-features')
    added += 1
  }
  // 本轮没有可新增的键说明拦截原因未被解析到，交给上层终止重试，避免死循环。
  if (added === 0) process.exit(3)
  // @ 开头是 YAML 保留指示符，含 @ 或冒号的键需加引号。
  const entry = (key) => /^[A-Za-z0-9._/-]+$/.test(key) ? `${key}: ${allowed.get(key)}` : `${JSON.stringify(key)}: ${allowed.get(key)}`
  const body = `allowBuilds:\n${[...allowed].map(([key]) => `  ${entry(key)}`).join('\n')}\n`
  const head = source.replace(/^allowBuilds:[^\n]*\n(?:[ \t]+[^\n]*\n?)*/m, '').trimEnd()
  const updated = head ? `${head}\n\n${body}` : body
  const temporaryFile = `${workspaceFile}.tmp-${process.pid}`
  try {
    await writeFile(temporaryFile, updated, 'utf8')
    await rename(temporaryFile, workspaceFile)
  } catch (error) {
    await rm(temporaryFile, { force: true })
    throw error
  }
  console.log(JSON.stringify([...allowed].map(([key, value]) => value ? key : `${key}: false`)))
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
'@

    $previousProfile = $env:DSH_PROFILE_DIR
    try {
        $env:DSH_PROFILE_DIR = $ProfileDirectory
        $nodeScript | & node - @($keys)
        if ($LASTEXITCODE -eq 3) {
            # 本轮未解析到新的 allowBuilds 键，通知上层终止重试。
            return $false
        }
        if ($LASTEXITCODE -ne 0) {
            throw '写入 Desktop Profile 的 allowBuilds 白名单失败。'
        }
    }
    finally {
        $env:DSH_PROFILE_DIR = $previousProfile
    }
    return $true
}

# 确保 Desktop Profile 具备插件管理所需的骨架文件；桌面已建好的 profile 原样复用，
# 全新环境按 Electron 侧初始化布局创建最小骨架（依赖清单、bundle 层栈与 pnpm 工作区）。
function Initialize-ProfileLayout {
    $manifestPath = Join-Path $ProfileDirectory 'package.json'
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        return
    }
    New-Item -ItemType Directory -Path $ProfileDirectory -Force | Out-Null
    $manifest = [ordered]@{
        name = 'dsh-profile-desktop'
        private = $true
        dependencies = [ordered]@{}
        dsh = [ordered]@{
            profile = [ordered]@{
                bundles = @('@deepseek-ai/dsh-base', '@deepseek-ai/dsh-web-app')
                patchReload = 'live'
            }
        }
    }
    Write-Utf8Json -LiteralPath $manifestPath -InputObject $manifest
    $workspacePath = Join-Path $ProfileDirectory 'pnpm-workspace.yaml'
    if (-not (Test-Path -LiteralPath $workspacePath -PathType Leaf)) {
        $workspaceBody = "packages:`n  - .`n`nnodeLinker: hoisted`nautoInstallPeers: false`n"
        [System.IO.File]::WriteAllText($workspacePath, $workspaceBody, [System.Text.UTF8Encoding]::new($false))
    }
    Write-InitLog '已初始化 Desktop Profile 骨架。'
}

# pnpm 操作完成后，将 dsh.profile.bundles 与依赖包的 dsh.bundle 声明状态对齐，
# 与 dsh CLI 内置 reconcile 行为一致：声明 bundle 的依赖加入层栈，不再声明的移出；
# 模板内置 bundle（非依赖项）保持原位不动。
function Sync-ProfileBundles {
    $syncScript = @'
const { readFile, rename, rm, writeFile } = require('node:fs/promises')
const path = require('node:path')

;(async () => {
  const profileDir = process.env.DSH_PROFILE_DIR
  const manifestPath = path.join(profileDir, 'package.json')
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'))
  const dependencies = manifest.dependencies ?? {}
  const previous = manifest.dsh?.profile?.bundles ?? []
  const inBox = previous.filter((name) => !Object.hasOwn(dependencies, name))
  const declared = []
  for (const name of Object.keys(dependencies)) {
    let pkg
    try {
      pkg = JSON.parse(await readFile(path.join(profileDir, 'node_modules', ...name.split('/'), 'package.json'), 'utf8'))
    } catch (error) {
      if (error?.code !== 'ENOENT') throw error
    }
    if (pkg?.dsh?.bundle?.patch !== undefined) declared.push(name)
  }
  const merged = [...inBox, ...declared]
  if (JSON.stringify(merged) === JSON.stringify(previous)) return
  manifest.dsh = { ...manifest.dsh, profile: { ...manifest.dsh?.profile, bundles: merged } }
  const temporaryFile = `${manifestPath}.tmp-${process.pid}`
  try {
    await writeFile(temporaryFile, JSON.stringify(manifest, null, 2) + '\n', 'utf8')
    await rename(temporaryFile, manifestPath)
  } catch (error) {
    await rm(temporaryFile, { force: true })
    throw error
  }
})().catch((error) => {
  console.error(error)
  process.exit(1)
})
'@
    $previousProfile = $env:DSH_PROFILE_DIR
    try {
        $env:DSH_PROFILE_DIR = $ProfileDirectory
        $syncScript | & node
        if ($LASTEXITCODE -ne 0) {
            throw '同步 Desktop Profile Bundle 列表失败。'
        }
    }
    finally {
        $env:DSH_PROFILE_DIR = $previousProfile
    }
}

# 执行一次插件卸载或安装；依赖构建被拦截时解析输出、补充 allowBuilds 白名单并循环重试。
# 每个被拦截的 git-hosted 包都会中断一次安装，上限 12 轮（超出插件总数），
# 一轮未解析到新键即终止，避免死循环。
# 0.1.5 起 dsh CLI 拒绝操作 desktop profile，插件管理改由脚本以桌面相同的方式
# （pnpm 于 profile 目录内）完成。
function Invoke-PluginOperation {
    param(
        [Parameter(Mandatory)][ValidateSet('add', 'remove')][string]$Action,
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string[]]$Targets
    )

    $arguments = @('--dir', $ProfileDirectory, $Action) + $Targets
    $maxAttempts = 12
    Write-InitLog "正在$Label Desktop Profile 插件：$($Targets -join ', ')……"
    for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
        $result = Invoke-CapturedCommand -FilePath 'pnpm' -ArgumentList $arguments
        if ($result.ExitCode -eq 0) {
            Sync-ProfileBundles
            Write-InitLog "已完成 Desktop Profile 插件$Label。"
            return
        }

        if ($result.Output -notmatch '(?i)ERR_PNPM_GIT_DEP_PREPARE_NOT_ALLOWED|ERR_PNPM_IGNORED_BUILDS|Ignored build scripts?') {
            break
        }
        if (-not (Approve-PendingBuildsExceptCpuFeatures -Output $result.Output)) {
            throw 'Desktop Profile 插件依赖构建白名单处理失败。请查看上方 pnpm 输出。'
        }
        Write-InitLog "正在重试 Desktop Profile 插件$Label（第 $attempt/$maxAttempts 轮）……"
    }

    throw "Desktop Profile 插件${Label}失败：$($Targets -join ', ')"
}

# 先卸载所有已存在的目标或废弃插件，再按完整来源统一重新安装目标插件。
function Install-DesktopPlugins {
    Initialize-ProfileLayout
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
    # pwsh 6+ 移除了 -Encoding Byte，改用 -AsByteStream；Windows PowerShell 5.1 保持原参数。
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $profilePrefix = @(Get-Content -LiteralPath $profileManifestPath -AsByteStream -TotalCount 3)
    }
    else {
        $profilePrefix = @(Get-Content -LiteralPath $profileManifestPath -Encoding Byte -TotalCount 3)
    }
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
        Install-AgentPresets
        Set-DefaultAgentPreset
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
