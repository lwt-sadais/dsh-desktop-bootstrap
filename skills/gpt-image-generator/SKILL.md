---
name: gpt-image-generator
description: 使用 gpt-image-2 按文字需求生成并展示图片。用户要求生成、绘制、设计、渲染图片、插画、海报视觉、建筑或室内效果图、产品图、概念图、背景图、头像等任何图像时必须使用本技能。
---

# GPT 图片生成

通过本技能自带的脚本生成图片。不要临时重写接口调用，也不要改用网页图片生成器。

## 脚本与输出目录

先根据当前宿主加载技能时提供的来源路径，取得本 `SKILL.md` 所在的绝对目录，并将其记为 `IMAGE_SKILL_DIR`。不要根据当前工作目录猜测技能目录，也不要写死 ZCode、Codex 或用户名路径。

脚本路径：

```text
$IMAGE_SKILL_DIR/scripts/generate-image.mjs
```

用户未指定保存位置时，不传 `--output`，由脚本根据实际安装结构生成唯一的绝对输出路径：

- 标准安装 `<宿主根目录>/skills/<技能目录>`：保存到 `<宿主根目录>/generated-images/`。
- 例如安装在 `~/.zcode/skills/` 或 `~/.codex/skills/` 下时，分别保存到对应宿主根目录的 `generated-images/`。
- 非标准安装结构：保存到 `<当前工作目录>/output/imagegen/`。

用户明确指定保存位置时，使用用户指定的绝对路径传入 `--output`。脚本默认生成带时间戳和随机后缀的 `.png` 文件，并拒绝覆盖已有文件。

## 工作流程

1. 每次生成前先运行配置检查：

```bash
node "$IMAGE_SKILL_DIR/scripts/generate-image.mjs" --check-config
```

2. 解析检查结果中的 `missing` 字段。没有缺项时继续生成；存在缺项时，必须先按“首次与缺项配置”流程询问用户并写入 `.env`，不得直接调用图片接口。
3. 从用户请求中提取主体、场景、风格、构图、色彩、光线、画幅和必须避免的内容。
4. 需求已经足以生成时直接执行，不要为了非必要细节重复追问。
5. 用户只给出简短需求时，在不改变其核心意图的前提下，将其整理成清晰、具体的生成提示词。不要擅自加入品牌、人物、文字或敏感内容。
6. 根据构图选择尺寸：
   - 方图：`1024x1024`
   - 横图：`1536x1024`
   - 竖图：`1024x1536`
   - 用户未表达画幅且无法可靠判断：`auto`
7. 调用脚本。命令示例：

```bash
node "$IMAGE_SKILL_DIR/scripts/generate-image.mjs" \
  --prompt "用户需求整理后的完整提示词" \
  --size "1536x1024" \
  --quality "auto"
```

用户指定保存位置时，再增加 `--output "/用户指定的绝对路径/图片.png"`。

8. 脚本会自动读取当前 DSH 会话的 `imageLimits` 投影，以 `maxImageBytes`、`maxMessageImageBytes` 与脚本安全上限中的最小值作为附件字节上限；非 DSH 宿主或探测失败时使用脚本安全上限。需要单独检查时运行：

```bash
node "$IMAGE_SKILL_DIR/scripts/generate-image.mjs" --check-host-limit
```

9. 不要通过管道、命令替换或重定向捕获脚本 stdout。成功时 stdout 是一行 JSON：

```json
{"path":"/绝对路径/图片.png","mediaType":"image/png","bytes":123456,"attachmentMaxBytes":5242880,"attachmentLimitSource":"dsh"}
```

解析 `path` 作为后续步骤的精确文件路径。`attachmentLimitSource` 为 `dsh` 表示限制来自当前宿主投影，`fallback` 表示宿主不可探测而使用脚本安全上限。

10. 检查生成命令成功，并确认 JSON 中的文件存在且非空。失败时如实报告经过脱敏的错误，不得声称已经生成。
11. 生成成功后必须立即调用宿主的 `read_image` 工具，参数 `file_path` 使用 JSON 中的绝对 `path`。`read_image` 会把文件导入 DSH attachment store，并返回原生图片块；支持图片提升的 DSH Desktop 会把该轮成功 `read_image` 的图片追加到本轮最终助手消息正文。不要用 Bash 再读取图片，不要把 Base64 写进回复，也不要依赖 Markdown `file://` 或 `data:` 图片。
12. 调用 `read_image` 后再输出本轮最终文本回复；不要在读取图片后继续调用与成图无关的工具，以免最终正文展示与结果说明分散。只有 `read_image` 成功后才能声称图片已在最终消息正文中展示。如果当前宿主没有 `read_image`、附件服务不可用、模型路由不接受图片，或图片仍被宿主拒绝，应保留已生成文件并明确说明“文件已生成但未能导入对话附件”及脱敏后的原因。
13. 最终回复简洁说明：成图已生成并显示在本消息正文、实际保存路径、采用尺寸，以及宿主附件上限。路径使用 Markdown 行内代码，不要再次嵌入本地图片 Markdown。

## 首次与缺项配置

`.env` 可以不存在或为空。配置检查返回缺项时，严格执行以下流程：

1. 只询问 `missing` 中列出的项目，已有项目保持原值，不得要求用户重复输入：
   - `SADAIS_IMAGE_API_KEY`：询问图片接口 API Key。
   - `SADAIS_IMAGE_BASE_URL`：询问 OpenAI 兼容服务 Base URL。
   - `SADAIS_IMAGE_MODEL`：询问图片模型名。
2. 必须使用 `AskUserQuestion` 收集配置。每次最多询问 4 项；用户的自定义输入必须原样保存，不得改写、补全或替换。
3. API Key 属于敏感信息。写入后不得在后续消息、命令参数、stdout、stderr 或配置摘要中复述它。
4. 收集完全部缺项后，将已有配置与新值合并，并完整写入：

```text
$IMAGE_SKILL_DIR/.env
```

文件格式固定为：

```dotenv
SADAIS_IMAGE_API_KEY=<用户输入>
SADAIS_IMAGE_BASE_URL=<用户输入>
SADAIS_IMAGE_MODEL=<用户输入>
```

5. 写入或更新 `.env` 后立即设置权限为 `0600`。不得创建第二份凭据文件，也不得把 `.env` 移出技能目录。
6. 写入后重新运行 `--check-config`。只有返回 `{"configured":true,"missing":[]}` 才能继续生成；否则再次只询问剩余缺项。
7. 若用户拒绝提供任何必需项，停止生成并说明缺少的字段，不得猜测默认值。

## 参数

- `--check-config`：只检查技能目录中的 `.env`，输出是否完整及缺失字段名，不读取或输出配置值。
- `--check-host-limit`：探测当前 DSH 会话附件字节上限，输出 `maxImageBytes` 与来源；不能和其他参数共用。
- `--prompt`：必需，完整的图片生成提示词。
- `--output`：可选，用户指定的图片保存绝对路径；省略时由脚本按安装结构选择目录并生成唯一的 `.png` 文件名。
- `--size`：可选，支持 `auto`、`1024x1024`、`1536x1024`、`1024x1536`，默认 `auto`。
- `--quality`：可选，支持 `auto`、`low`、`medium`、`high`，默认 `auto`。
- `--model`：可选；通常不传，使用 `.env` 中的 `SADAIS_IMAGE_MODEL`。

## 认证与安全

脚本优先读取进程环境变量：

- `SADAIS_IMAGE_API_KEY`
- `SADAIS_IMAGE_BASE_URL`
- `SADAIS_IMAGE_MODEL`

缺失项再从本技能目录中的 `.env` 读取：

```text
$IMAGE_SKILL_DIR/.env
```

`.env` 必须保持 `0600` 权限。不得读取或修改 ZCode、Codex 等宿主内部的 Provider 凭据文件，不得把密钥放进命令参数、提示词、日志、最终回复或生成图片元数据；复制或同步技能目录时必须排除 `.env`。

宿主限制探测只在同时存在 `DSH_WEB_URL` 与 `DSH_SESSION_ID` 时进行，只接受 loopback DSH 地址，并仅调用当前会话的 `session.history` 读取 `imageLimits` 投影；探测异常不会泄露会话历史，也不会阻断非 DSH 宿主生成。
