# dsh-desktop-bootstrap

用于记录和恢复当前 DSH Desktop 的全局 `AGENTS.md`、用户级 Skills、Agent 预设与 Desktop Profile 插件，方便后续由 AI 读取本仓库并初始化新的 DSH Desktop 环境。

> 本仓库不包含真实 API Key、Token、密码或服务 Base URL。Skills 中的私密配置已替换为占位符，使用前必须在本机重新配置。

## 仓库内容

```text
.
├── AGENTS.md
├── install.ps1
├── install.sh
├── agent-presets
│   └── codex-mode
│       ├── agent.cordis.yml
│       └── preset.yml
└── skills
    ├── commit
    │   ├── SKILL.md
    │   └── command.md
    └── gpt-image-generator
        ├── .env.example
        ├── SKILL.md
        └── scripts
            └── generate-image.mjs
```

## 前置条件

- 已安装并启动 DSH Desktop。
- 必须从 DSH Desktop 应用内打开其专用终端；普通 macOS 终端或普通 Windows PowerShell 无法直接识别 `dsh`。
- 手动安装时需使用 Git 克隆本仓库；一键初始化脚本不依赖本机 Git。
- 安装 GitHub 插件时需要能够访问 GitHub。

## 一键初始化（推荐）

脚本会下载本仓库的默认分支，备份并安装全局 `AGENTS.md`、合并用户级 Skills、安装用户级 Codex 模式 Agent 预设、将其设为新会话的默认模式，并安装本文列出的 Desktop Profile 插件。安装过程不会创建或覆盖任何 Skill 的私密 `.env`。

### 第一步：打开 DSH Desktop 专用终端

先启动 DSH Desktop，然后从应用内打开 **DSH Desktop 专用终端**。该终端会为当前 Desktop Profile 注入 `dsh` 和配套的 `pnpm` 命令；请勿在普通系统终端中执行下方命令。

可先执行以下命令确认环境：

```text
dsh --dump-config
```

能够正常输出配置后，再根据系统执行对应的一键命令。

### macOS

在 DSH Desktop 专用终端中执行：

```bash
curl -fsSL "https://raw.githubusercontent.com/lwt-sadais/dsh-desktop-bootstrap/main/install.sh?t=$(date +%s)" | bash
```

### Windows

在 DSH Desktop 专用 PowerShell 中执行：

```powershell
irm "https://raw.githubusercontent.com/lwt-sadais/dsh-desktop-bootstrap/main/install.ps1?t=$(Get-Date -Format yyyyMMddHHmmss)" | iex
```

### 脚本行为

- 脚本首先检查当前终端能否执行 `dsh`；如果不能，会提示回到 DSH Desktop 应用内打开专用终端。
- 如果 `~/.dsh/AGENTS.md` 已存在，会先按时间戳备份为 `AGENTS.md.backup.<时间戳>`。
- Skills 采用合并安装，不会删除用户已有的其他 Skill，也不会创建或覆盖私密 `.env`。
- Codex 模式安装到 `~/.dsh/.agent-presets/codex-mode`；若已存在同名文件或目录，会先整体备份为 `codex-mode.backup.<时间戳>`，再安装仓库版本。
- 脚本会保留 `~/.dsh/settings.yaml` 中的其他设置，只写入 `agent-presets.default: codex-mode`；此设置影响此后新建的会话，不切换已运行会话的模式。
- 首次请求生成图片时，`gpt-image-generator` 会运行配置检查，并通过交互提问仅收集缺失配置；已有配置不会要求重复输入。
- Desktop Profile 中缺失的插件会按完整来源通过一条 `dsh plugin add` 命令批量安装；重复运行脚本时，已声明插件会按真实包名通过一条 `dsh plugin update` 命令批量更新。该逻辑面向 DSH Desktop 内置 Harness `0.1.2-alpha.1`；其中 `dsh-plan-review-card` 会让主 Agent 通过 `present_result_card` 输出可审查的结构化卡片，子 Agent 不触发人工审查；完整内容在非阻塞右侧阅读栏展示，可继续操作会话和输入框，并支持拖动调宽、宽度记忆、摘要审查、批准、拒绝、取消、批注调整、复制和 Markdown 导出。
- 脚本安装 `@linxin666/dsh-web-all@0.3.9` 作为 Web UI 聚合包，并把 [`lwt-sadais/DSH-better-sidebar`](https://github.com/lwt-sadais/DSH-better-sidebar) 的固定适配提交作为同名顶层插件。该提交已包含通过验证的构建产物，不依赖已下架的 alpha.1 开发包执行现场构建；Fork 自带聚合重复挂载保护，因此运行时仍只有一个侧边栏实例。
- DSH 的 pnpm 默认拒绝发布不足 24 小时的依赖。脚本会保留用户已有策略，仅将 Web UI 0.3.9 聚合包及其 17 个精确 `@linxin666/*@0.3.9` 依赖合并到 Desktop Profile 的 `minimumReleaseAgeExclude`；不会使用通配符、关闭 `minimumReleaseAge`，也不会通过 `--trust-lockfile` 跳过锁文件校验。
- 如果 pnpm 拦截依赖构建脚本，脚本会先执行 `pnpm approve-builds !cpu-features`，明确拒绝 SSH 的可选原生加速依赖 `cpu-features`，避免没有 C++ 编译器的 Windows 电脑安装失败。
- 排除 `cpu-features` 后，脚本会执行 `pnpm approve-builds --all` 批准其余全部待审批依赖构建脚本，然后仅重试失败的安装或更新操作一次。
- 下载产生的临时文件会在结束时自动清理；任一关键步骤失败时脚本返回非零退出状态。
- 初始化完成后请完全退出并重新启动 DSH Desktop，使全局指令、Skills、Agent 预设与插件重新加载。

> 远程一行命令会直接执行本仓库默认分支中的脚本。如需先审计内容，请查看 [`install.sh`](install.sh) 或 [`install.ps1`](install.ps1)，也可以按照下方步骤手动安装。

## 手动安装

### 一、克隆仓库

```bash
git clone https://github.com/lwt-sadais/dsh-desktop-bootstrap.git
cd dsh-desktop-bootstrap
```

### 二、安装 AGENTS.md

先创建 DSH 用户目录；如果本机已有 `~/.dsh/AGENTS.md`，建议先备份：

```bash
mkdir -p ~/.dsh
if [ -e ~/.dsh/AGENTS.md ] || [ -L ~/.dsh/AGENTS.md ]; then
  cp -L ~/.dsh/AGENTS.md ~/.dsh/AGENTS.md.backup
fi
install -m 0644 AGENTS.md ~/.dsh/AGENTS.md
```

安装后，新建 DSH 会话以确保全局指令被重新读取。

## 三、安装 Skills

将仓库中的 Skills 合并到 DSH 用户级 Skills 目录：

```bash
mkdir -p ~/.dsh/skills
cp -R skills/. ~/.dsh/skills/
```

### 配置 gpt-image-generator

仓库只保存 `.env.example` 配置结构，不保存原始凭据或服务地址。安装时不要将其中的 `<REDACTED_...>` 占位符复制为真实 `.env`。

首次向 AI 请求生成图片时，`gpt-image-generator` Skill 会自动执行配置检查。如果 `.env` 不存在、为空或缺少字段，AI 会通过交互提问仅收集以下缺失项：

- `SADAIS_IMAGE_API_KEY`
- `SADAIS_IMAGE_BASE_URL`
- `SADAIS_IMAGE_MODEL`

收集完成后，Skill 会将配置写入 `~/.dsh/skills/gpt-image-generator/.env`、设置为 `0600` 权限并重新检查。已有字段保持原值，不会要求重复输入。

如需自行检查配置完整性，可执行：

```bash
node ~/.dsh/skills/gpt-image-generator/scripts/generate-image.mjs --check-config
```

完整配置的预期结果：

```json
{"configured":true,"missing":[]}
```

## 四、安装 Codex 模式 Agent 预设

将仓库中的 Codex 模式复制到 DSH 用户级预设目录：

```bash
mkdir -p ~/.dsh/.agent-presets
cp -R agent-presets/codex-mode ~/.dsh/.agent-presets/codex-mode
```

如果目标目录已存在，请先整体备份，避免覆盖本机自定义内容。随后在 `~/.dsh/settings.yaml` 中设置默认模式，同时保留其他设置：

```yaml
agent-presets:
  default: codex-mode
```

安装并重启 DSH Desktop 后，新建会话会默认使用“Codex模式”，也仍可在模式选择器中切换；已运行会话不受影响。该预设是内置标准模式的快照，仅调整编码 Agent 的 persona；未来 DSH 升级若变更标准模式能力，需要人工同步本仓库中的预设。

## 五、安装 Desktop Profile 插件

以下插件已按 DSH Desktop 内置 Harness `0.1.2-alpha.1` 适配，统一安装到 `desktop` Profile。若旧 Profile 仍声明 `@linxin666/dsh-web-ui-all`，请先移除，再安装新的聚合包：

```bash
dsh plugin remove --profile desktop @linxin666/dsh-web-ui-all
dsh plugin add --profile desktop @linxin666/dsh-web-all@0.3.9 github:lwt-sadais/DSH-better-sidebar#ed28df8d66f1b9f9871fb358c6616289d23358f3 github:lwt-sadais/dsh-at-file#6dbc6209a881c97ae094081e5fb8899a9f4b1b05 github:lwt-sadais/dsh-archived-sessions#ada246b0def6db8fc6cdeb424abb520e56ccd068 github:lwt-sadais/dsh-git-diff#69c8458d3eefc507f4512983934cc046b4e736dd github:lwt-sadais/dsh-git-history#cf22d3e2c839d38f63064568021cdc2b854dd41d github:lwt-sadais/dsh-local-file-reference#4ccc956cc14b1e2d4c19634287b52dcfc3a3c955 github:lwt-sadais/dsh-plan-review-card#e73b29c58844c1327d5fd1f0658c7c385cbc92e7 github:lwt-sadais/dsh-reasoning-efforts#4d48a26b99fd1f4a4986403a0c9a3a6499efa897
```

> DSH Desktop 会为每次插件变更创建恢复事务。请等待上一条命令成功并完成恢复验证后再执行下一条；全部完成后完全退出并重新启动 DSH Desktop。

对应关系：

| 当前安装项 | 适配基线 | GitHub 仓库 | 说明 |
| --- | --- | --- | --- |
| `@linxin666/dsh-web-all` | `0.3.9` | [`zhu1090093659/dsh-web`](https://github.com/zhu1090093659/dsh-web) | alpha.1 Web UI 聚合包；安装 18 个固定版本功能依赖，无需旧版插件管理器源码补丁 |
| `dsh-better-sidebar` | `0.1.2-alpha.1` | [`lwt-sadais/DSH-better-sidebar`](https://github.com/lwt-sadais/DSH-better-sidebar) | 顶层 Fork；移除旧 Client Runtime，适配 Remote Gateway 与 token 认证，并保留重复挂载保护 |
| `dsh-at-file` | `0.1.2-alpha.1` | [`lwt-sadais/dsh-at-file`](https://github.com/lwt-sadais/dsh-at-file) | Fork；迁移到 Client Store、Session Controller 与 alpha.1 Remote API |
| `@muwinds/dsh-archived-sessions` | `0.1.2-alpha.1` | [`lwt-sadais/dsh-archived-sessions`](https://github.com/lwt-sadais/dsh-archived-sessions) | Fork；归档会话管理，不创建上游 PR |
| `dsh-git-diff` | `0.1.2-alpha.1` | [`lwt-sadais/dsh-git-diff`](https://github.com/lwt-sadais/dsh-git-diff) | Git Diff 审查；移除已删除的旧 Client Runtime |
| `dsh-git-history` | `0.1.2-alpha.1` | [`lwt-sadais/dsh-git-history`](https://github.com/lwt-sadais/dsh-git-history) | Git 历史与远端同步；移除已删除的旧 Client Runtime |
| `dsh-local-file-reference` | `0.1.2-alpha.1` | [`lwt-sadais/dsh-local-file-reference`](https://github.com/lwt-sadais/dsh-local-file-reference) | 本地文件路径引用；迁移到 `uiSession` 当前绑定 API |
| `dsh-plan-review-card` | `0.1.2-alpha.1` | [`lwt-sadais/dsh-plan-review-card`](https://github.com/lwt-sadais/dsh-plan-review-card) | 结构化审查卡片；适配 alpha.1 `MarkdownText.labels` 契约，并通过 Portal 将完整阅读栏挂载到页面根层，避免 ToolRow 裁剪 |
| `dsh-reasoning-efforts` | `0.1.2-alpha.1` | [`lwt-sadais/dsh-reasoning-efforts`](https://github.com/lwt-sadais/dsh-reasoning-efforts) | 按模型配置 Provider 推理等级与接口映射；使用 alpha.1 `ctx.remote.settings` 读取和保存设置 |

> `@deepseek-ai/dsh-base` 和 `@deepseek-ai/dsh-web-app` 是 DSH Desktop Profile 的内置基础 Bundle，不作为第三方插件重复安装。

安装或更新插件后，请完全退出并重新启动 DSH Desktop，使 Host 与 Web 客户端加载新插件。

## 六、建议交给 AI 的初始化指令

可以在新环境中向 AI 提供本仓库地址，并要求：

```text
请读取 https://github.com/lwt-sadais/dsh-desktop-bootstrap，按照 README.md：
1. 安装仓库中的 AGENTS.md；
2. 安装仓库中的 Skills，但不要猜测或写入任何密钥和 Base URL；
3. 安装仓库中的 codex-mode Agent 预设；
4. 使用 README.md 中列出的 dsh plugin add --profile desktop github:Owner/repo 命令安装插件；
5. 操作前备份已有同名文件，完成后逐项验证。
```

## 安全说明

- 原始 `~/.dsh/skills/gpt-image-generator/.env` 未复制到仓库，安装脚本也不会创建或覆盖该文件。
- 仓库使用 `.env.example` 保存配置结构，值均为明确的 `<REDACTED_...>` 占位符；这些占位符不会作为真实配置安装。
- `.gitignore` 会忽略所有 `.env` 私密配置，但允许提交 `.env.example`。
- 提交或更新前仍应执行敏感信息扫描，避免把本机新增的凭据、私有服务地址、Cookie、认证头或私钥推送到公开仓库。
