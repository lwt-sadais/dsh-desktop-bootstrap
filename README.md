# dsh-desktop-bootstrap

用于记录和恢复当前 DSH Desktop 的全局 `AGENTS.md`、用户级 Skills 与 Desktop Profile 插件，方便后续由 AI 读取本仓库并初始化新的 DSH Desktop 环境。

> 本仓库不包含真实 API Key、Token、密码或服务 Base URL。Skills 中的私密配置已替换为占位符，使用前必须在本机重新配置。

## 仓库内容

```text
.
├── AGENTS.md
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

- 已安装 DSH Desktop。
- 终端中可以执行 `dsh`。
- 已安装 Git，用于克隆本仓库。
- 安装 GitHub 插件时需要能够访问 GitHub。

## 一、克隆仓库

```bash
git clone https://github.com/lwt-sadais/dsh-desktop-bootstrap.git
cd dsh-desktop-bootstrap
```

## 二、安装 AGENTS.md

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

仓库只保存占位配置，不保存原始凭据或服务地址。安装后复制示例文件，并将三个占位符替换为新环境中的真实值：

```bash
cp ~/.dsh/skills/gpt-image-generator/.env.example \
  ~/.dsh/skills/gpt-image-generator/.env
chmod 0600 ~/.dsh/skills/gpt-image-generator/.env
```

需要配置：

- `SADAIS_IMAGE_API_KEY`
- `SADAIS_IMAGE_BASE_URL`
- `SADAIS_IMAGE_MODEL`

配置完成后可执行检查：

```bash
node ~/.dsh/skills/gpt-image-generator/scripts/generate-image.mjs --check-config
```

预期结果：

```json
{"configured":true,"missing":[]}
```

## 四、安装 Desktop Profile 插件

以下列表根据当前 `~/.dsh/profiles/desktop/package.json` 的顶层插件依赖及已安装包元数据生成。统一安装到 `desktop` Profile：

```bash
dsh plugin add --profile desktop github:zhu1090093659/dsh-web-ui
dsh plugin add --profile desktop github:FSMargoo/dsh-at-file
dsh plugin add --profile desktop github:MuWinds/dsh-archived-sessions
dsh plugin add --profile desktop github:lwt-sadais/dsh-git-diff
dsh plugin add --profile desktop github:lwt-sadais/dsh-local-file-reference
```

对应关系：

| 当前安装项 | 检测到的版本 | GitHub 仓库 | 说明 |
| --- | --- | --- | --- |
| `@linxin666/dsh-web-ui-all` | `0.2.5` | [`zhu1090093659/dsh-web-ui`](https://github.com/zhu1090093659/dsh-web-ui) | Web UI 全家桶；包含任务看板、SSH、梁神模式、桌面启动器等子插件 |
| `dsh-at-file` | `0.6.3` | [`FSMargoo/dsh-at-file`](https://github.com/FSMargoo/dsh-at-file) | `@path` 工作区文件引用 |
| `@muwinds/dsh-archived-sessions` | `0.2.0` | [`MuWinds/dsh-archived-sessions`](https://github.com/MuWinds/dsh-archived-sessions) | 归档会话管理 |
| `dsh-git-diff` | `0.1.0` | [`lwt-sadais/dsh-git-diff`](https://github.com/lwt-sadais/dsh-git-diff) | Git Diff 审查 |
| `dsh-local-file-reference` | `0.1.0` | [`lwt-sadais/dsh-local-file-reference`](https://github.com/lwt-sadais/dsh-local-file-reference) | 本地文件路径引用 |

> `@deepseek-ai/dsh-base` 和 `@deepseek-ai/dsh-web-app` 是 DSH Desktop Profile 的内置基础 Bundle，不作为第三方插件重复安装。

安装或更新插件后，请完全退出并重新启动 DSH Desktop，使 Host 与 Web 客户端加载新插件。

## 五、建议交给 AI 的初始化指令

可以在新环境中向 AI 提供本仓库地址，并要求：

```text
请读取 https://github.com/lwt-sadais/dsh-desktop-bootstrap，按照 README.md：
1. 安装仓库中的 AGENTS.md；
2. 安装仓库中的 Skills，但不要猜测或写入任何密钥和 Base URL；
3. 使用 README.md 中列出的 dsh plugin add --profile desktop github:Owner/repo 命令安装插件；
4. 操作前备份已有同名文件，完成后逐项验证。
```

## 安全说明

- 原始 `~/.dsh/skills/gpt-image-generator/.env` 未复制到仓库。
- 仓库使用 `.env.example` 保存配置结构，值均为明确的 `<REDACTED_...>` 占位符。
- `.gitignore` 会忽略所有 `.env` 私密配置，但允许提交 `.env.example`。
- 提交或更新前仍应执行敏感信息扫描，避免把本机新增的凭据、私有服务地址、Cookie、认证头或私钥推送到公开仓库。
