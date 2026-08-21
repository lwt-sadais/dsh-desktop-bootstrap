---
allowed-tools: Bash(git *), AskUserQuestion, Skill
description: 创建 git 提交（含代码质量检查，支持嵌套子模块）
---

# Git Commit 命令（智能提交）

## 命令说明

这是一个增强版的 git commit 命令，在提交前可以：
1. ❓ **可选的代码质量检查**（simplify skill，询问用户是否需要）
2. 🔄 **支持循环优化**（直到用户满意）
3. 📝 **生成规范的提交消息**（约定式提交 + emoji）
4. 🚀 **自动推送到远程**
5. 🔗 **完整的子模块支持**（递归检测、嵌套处理、独立推送）

---

## 工作流程总览

```
/commit
  ↓
【准备阶段】
  ├─ 0. 检测已有暂存文件
  ├─ 1. 递归收集所有变更（主项目 + 所有子模块）
  ├─ 2. 构建提交依赖树（子模块 → 父模块）
  └─ 3. 询问：是否需要代码质量检查？
        ├─ 是 → 进入第一阶段
        └─ 否 → 直接跳到第二阶段
  ↓
【第一阶段：代码质量检查】（可选，可循环）
  ├─ 4. simplify skill 分析代码
  ├─ 5. 有优化建议？
  │     ├─ 是 → 询问用户 → 处理 → 回到步骤 4
  │     └─ 否 → 进入第二阶段
  ↓
【第二阶段：Git 提交流程】
  ├─ 6. 按依赖顺序逐个处理每个模块（从最深层子模块开始）：
  │     ├─ 6.1 ⚠️ 【必须】同步远程 (`git -C ... fetch` + `git -C ... pull`)
  │     ├─ 6.2 分析变更
  │     ├─ 6.3 拆分提交（详见附录 A）
  │     ├─ 6.4 生成消息
  │     ├─ 6.5 执行提交
  │     └─ 6.6 推送
  └─ 7. 最后处理主项目（同样先同步远程）
```

---

## 准备阶段

### 步骤 -1：锁定最外层主项目根目录

无论 `/commit` 从主项目、子模块还是嵌套子模块中启动，都必须先解析到最外层主项目根目录：

```bash
current_root=$(git rev-parse --show-toplevel)
while super_root=$(git -C "$current_root" rev-parse --show-superproject-working-tree 2>/dev/null) && [ -n "$super_root" ]; do
  current_root="$super_root"
done
SUPERPROJECT_ROOT="$current_root"
git -C "$SUPERPROJECT_ROOT" rev-parse --show-toplevel
```

### 步骤 0：检测已有暂存文件

在开始任何操作前，检测工作区是否已有暂存内容：

```bash
git -C "$SUPERPROJECT_ROOT" diff --cached --name-only
```

如果暂存区非空，使用 AskUserQuestion 询问用户：

```
⚠️ 检测到已有暂存文件：
  [列出文件列表]

如何处理？
1. 将这些文件纳入本次 /commit 流程统一处理
2. 先执行 `git -C "$SUPERPROJECT_ROOT" reset HEAD`（取消暂存）再由 /commit 重新分析
3. 中止，我来手动处理
```

根据用户选择决定是否继续。

---

### 步骤 1：递归收集所有变更

#### 1.1 检测子模块结构

```bash
# 同步主项目远程更新
git -C "$SUPERPROJECT_ROOT" fetch origin
local=$(git -C "$SUPERPROJECT_ROOT" rev-parse @)
remote=$(git -C "$SUPERPROJECT_ROOT" rev-parse @{u} 2>/dev/null)

if [ -n "$remote" ] && [ "$local" != "$remote" ]; then
  echo "⚠️ 主项目远程有新提交，正在同步..."
  git -C "$SUPERPROJECT_ROOT" pull --rebase || {
    echo "❌ 自动同步失败，请手动处理冲突后重试"
    exit 1
  }
fi

# 获取所有子模块路径（包括嵌套）
git -C "$SUPERPROJECT_ROOT" submodule status --recursive

# 检查主项目状态
git -C "$SUPERPROJECT_ROOT" status

# 获取当前分支
git -C "$SUPERPROJECT_ROOT" branch --show-current

# 查看提交历史（参考提交风格）
git -C "$SUPERPROJECT_ROOT" log --oneline -10
```

#### 1.2 递归检查每个模块的状态

> **说明：** 此处对每个子模块执行一次远程同步。步骤 6.1 会在实际提交前再同步一次，
> 属于有意设计的双重保障——准备阶段获取初始状态，提交前确保无新增远程提交。

⚠️ **CRITICAL: 必须对每个子模块执行 fetch 检查远程更新**

从 `git submodule status --recursive` 的输出中解析所有子模块路径，对每个子模块执行：

```bash
# 解析子模块路径示例
# git submodule status --recursive 输出格式：
#  4b58655ef7c311b5151c3e710eb6838c1eef7bcb src/lowcode-console (heads/master)
#  45bb1f2edbdf2065424950438aaa211db4e70397 src/vue3-common (heads/dev)

# 提取路径（第二列），路径以主项目根目录为基准
submodule_paths=$(git -C "$SUPERPROJECT_ROOT" submodule status --recursive | awk '{print $2}')

# 对每个子模块执行检查
for submodule_path in $submodule_paths; do
  module_path="$SUPERPROJECT_ROOT/$submodule_path"

  # ⚠️ CRITICAL: 检查并同步远程更新
  git -C "$module_path" fetch origin
  local=$(git -C "$module_path" rev-parse @)
  remote=$(git -C "$module_path" rev-parse @{u} 2>/dev/null)

  if [ -n "$remote" ] && [ "$local" != "$remote" ]; then
    echo "⚠️ 子模块 $submodule_path 远程有新提交，正在同步..."
    git -C "$module_path" pull --rebase || {
      echo "❌ 子模块 $submodule_path 同步失败，请手动处理冲突后重试"
      exit 1
    }
  fi

  # 检查状态
  git -C "$module_path" status --porcelain
  git -C "$module_path" diff HEAD --name-status
  git -C "$module_path" branch --show-current
done
```

**重要提示：**
- 不能只执行 `git submodule status`，这只显示当前状态，不会检测远程更新
- 必须对每个子模块执行 `git -C "$module_path" fetch` 才能发现远程新提交
- 如果子模块远程有更新但本地未同步，会导致主项目检测不到子模块指针变更

#### 1.3 构建变更摘要

输出格式：

```
📦 主项目 (/)
  - 修改: 3 个文件
  - 分支: main

📦 子模块 (path/to/submodule1)
  - 修改: 2 个文件
  - 分支: develop

📦 嵌套子模块 (path/to/submodule1/nested)
  - 修改: 1 个文件
  - 分支: feature/xxx
```

**特殊情况处理：**
- 如果所有模块都没有变更，提示用户并结束
- 如果只有主项目有变更，按单项目流程处理
- 如果只有子模块有变更，只处理子模块

---

### 步骤 2：构建提交依赖树

根据子模块嵌套关系，构建提交顺序：

```
提交顺序（从深到浅）：
1. path/to/submodule1/nested  (最深层)
2. path/to/submodule1         (中间层)
3. path/to/submodule2         (同级)
4. /                          (主项目，最后)
```

**规则：**
- 子模块必须在父模块之前提交
- 同级子模块可以并行处理（但实际按顺序执行）
- 主项目永远最后提交

---

### 步骤 3：询问是否需要代码质量检查

使用 AskUserQuestion 工具询问：

```
问题：是否需要在提交前进行代码质量检查？

选项：
1. 是，使用 simplify skill 检查代码质量
2. 否，直接进入提交流程
```

**根据用户选择：**
- 选择 1 → 进入第一阶段（代码质量检查）
- 选择 2 → 跳过第一阶段，直接进入第二阶段

---

## 第一阶段：代码质量检查（可选）

### 步骤 4：执行代码质量分析

**重要：** 此阶段必须保护用户的修改内容，不能重置工作区。

使用 Skill 工具调用 `simplify` skill，对所有修改的文件进行分析：

```
使用 Skill("simplify") 对变更文件列表执行分析
```

**输出：**
- 代码质量问题列表
- 优化建议
- 潜在的 bug

---

### 步骤 5：处理优化建议

如果 simplify 有优化建议：

#### 5.1 询问用户

使用 AskUserQuestion 工具：

```
问题：simplify 发现了以下优化建议：

[列出所有建议]

你希望如何处理？

选项：
1. 应用所有优化建议
2. 选择性应用（逐个确认）
3. 跳过优化，直接提交
```

#### 5.2 根据用户选择执行

**选项 1：应用所有优化**
使用 Skill("simplify") 应用全部建议，然后回到步骤 4（重新分析）

**选项 2：选择性应用**
逐个询问用户是否应用每个建议，然后回到步骤 4

**选项 3：跳过优化**
直接进入第二阶段。没有更多建议时同样直接进入第二阶段。

---

## 第二阶段：Git 提交流程

### Git 目录锁定规范（强制执行）

- **禁止依赖 cd 执行 git**：在主项目、子模块、嵌套子模块中执行 git 命令时，禁止依赖当前 shell 目录或 `cd` 后续状态。
- **所有 git 命令必须使用 -C**：模块级操作必须使用 `git -C "$module_path" ...`，主项目操作必须使用 `git -C "$SUPERPROJECT_ROOT" ...`。
- **提交前必须打印目标目录**：每次 `git add`、`git commit`、`git push` 前，必须输出当前处理模块名称、模块路径和 `git -C <path> rev-parse --show-toplevel` 的结果。
- **子模块路径以主项目根为基准**：递归子模块路径必须从主项目根目录解析，禁止从当前目录相对解析。
- **失败后禁止继续提交**：任何模块同步、提交或推送失败后，必须停止流程并询问用户，禁止切换到其它目录继续执行。

⚠️ **CRITICAL: 每个模块提交前必须先同步远程更新**

**强制规则：**
- 在执行任何 `git -C <path> add` 或 `git -C <path> commit` 之前
- 必须先执行 `git -C <path> fetch origin` 检查远程更新
- 如果远程有新提交，必须先 `git -C <path> pull --rebase`
- 违反此规则将导致推送失败和不必要的冲突

### 步骤 6：按依赖顺序处理每个模块

对于依赖树中的每个模块（从深到浅）：

#### 6.1 【必须】锁定模块目录并同步远程（在任何提交操作之前）

⚠️ **IMPORTANT: 此步骤必须在 `git -C <path> add/commit` 之前执行**

```bash
module_path="$SUPERPROJECT_ROOT/<module_relative_path>"
echo "📦 当前处理模块: <module_relative_path>"
echo "📁 模块路径: $module_path"
git -C "$module_path" rev-parse --show-toplevel

# 同步远程更新
git -C "$module_path" fetch origin
local=$(git -C "$module_path" rev-parse @)
remote=$(git -C "$module_path" rev-parse @{u} 2>/dev/null)

if [ -n "$remote" ] && [ "$local" != "$remote" ]; then
  echo "⚠️ 检测到远程有新提交，正在同步..."
  git -C "$module_path" pull --rebase || {
    echo "❌ 同步失败，请手动处理冲突后重试"
    exit 1
  }
fi
```

✅ **检查点：确认已完成远程同步，才能继续下一步**

#### 6.2 分析变更内容

```bash
# 查看详细变更
git -C "$module_path" diff HEAD

# 获取文件列表
git -C "$module_path" status --porcelain
```

#### 6.3 拆分提交（按语义）

根据约定式提交规范将变更分类，拆分依据是**变更的语义目的**，详见附录 A.2。

**提交类型：**`fix` / `feat` / `perf` / `refactor` / `style` / `docs` / `test` / `chore`

**规则：**
- 每个语义单独提交，同语义的多个文件可合并
- 同一文件含多个语义时，使用 `git -C "$module_path" add -p` 拆分（详见附录 A.2）

#### 6.4 生成提交消息

对每个提交，生成符合约定式提交的消息：

**格式：**
```
<emoji> <type>(<scope>): <subject>

<body>

<footer>
```

**Emoji 映射：**
- ✨ feat
- 🐛 fix
- ⚡️ perf
- ♻️ refactor
- 💄 style
- 📝 docs
- ✅ test
- 🔧 chore
- 🚀 deploy
- 🔒 security

**示例：**
```
✨ feat(api): 添加用户认证接口

- 实现 JWT token 生成
- 添加登录/登出端点
- 集成 bcrypt 密码加密

Closes #123
```

**生成规则：**
1. 分析代码变更，理解意图
2. 参考 `git -C "$module_path" log` 中的历史提交风格
3. 使用中文描述
4. 包含必要的上下文信息
5. 如果有关联的 issue，添加 footer

#### 6.5 执行提交

```bash
# 检查暂存区不为空，防止空提交
echo "📦 提交目标模块: <module_relative_path>"
echo "📁 模块路径: $module_path"
git -C "$module_path" rev-parse --show-toplevel

if git -C "$module_path" diff --cached --quiet; then
  echo "⚠️ 暂存区为空，跳过此次提交"
else
  git -C "$module_path" commit -m "<generated_message>"
fi
```

#### 6.6 推送到远程

```bash
# 检查是否有远程仓库
echo "📦 推送目标模块: <module_relative_path>"
echo "📁 模块路径: $module_path"
git -C "$module_path" rev-parse --show-toplevel

if ! git -C "$module_path" remote | grep -q .; then
  echo "ℹ️ 未配置远程仓库，跳过推送"
else
  # 获取远程分支
  remote_branch=$(git -C "$module_path" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)

  if [ -n "$remote_branch" ]; then
    # 推送到跟踪的远程分支
    git -C "$module_path" push
  else
    # 首次推送，设置上游分支
    current_branch=$(git -C "$module_path" branch --show-current)
    git -C "$module_path" push -u origin "$current_branch"
  fi
fi
```

**错误处理：**
- 如果推送被拒绝（rejected），询问用户如何处理
- 如果因权限不足被拒绝（remote: Permission denied / protected branch），提示用户检查分支保护规则或权限设置，不自动强推
- 如果 pre-commit hook 或 commit-msg hook 失败，输出 hook 的报错信息，询问用户是否修正后重试

### 步骤 7：处理主项目

在所有子模块处理完成后，处理主项目：

#### 7.0 同步主项目远程更新

```bash
echo "📦 当前处理模块: 主项目"
echo "📁 主项目路径: $SUPERPROJECT_ROOT"
git -C "$SUPERPROJECT_ROOT" rev-parse --show-toplevel

# 同步远程更新
git -C "$SUPERPROJECT_ROOT" fetch origin
local=$(git -C "$SUPERPROJECT_ROOT" rev-parse @)
remote=$(git -C "$SUPERPROJECT_ROOT" rev-parse @{u} 2>/dev/null)

if [ -n "$remote" ] && [ "$local" != "$remote" ]; then
  echo "⚠️ 主项目远程有新提交，正在同步..."
  git -C "$SUPERPROJECT_ROOT" pull --rebase || {
    echo "❌ 同步失败，请手动处理冲突后重试"
    exit 1
  }
fi
```

#### 7.1 分析主项目变更

如果子模块有新提交，主项目会检测到子模块指针变更：

```bash
git -C "$SUPERPROJECT_ROOT" status
# 输出示例：
# modified:   path/to/submodule (new commits)

git -C "$SUPERPROJECT_ROOT" diff HEAD
```

**变更类型：**
1. 仅子模块指针更新
2. 主项目代码变更
3. 两者都有

#### 7.2 拆分提交

**情况 1：仅子模块指针更新**
```bash
echo "📦 提交目标模块: 主项目"
echo "📁 主项目路径: $SUPERPROJECT_ROOT"
git -C "$SUPERPROJECT_ROOT" rev-parse --show-toplevel
git -C "$SUPERPROJECT_ROOT" add path/to/submodule1 path/to/submodule2
git -C "$SUPERPROJECT_ROOT" commit -m "🔗 chore: 更新子模块引用"
```

**情况 2：主项目代码变更**
按照步骤 6.3-6.5 处理

**情况 3：两者都有**
⚠️ **必须合并到同一个提交中**，不可拆分为两次提交。

```bash
echo "📦 提交目标模块: 主项目"
echo "📁 主项目路径: $SUPERPROJECT_ROOT"
git -C "$SUPERPROJECT_ROOT" rev-parse --show-toplevel
git -C "$SUPERPROJECT_ROOT" add path/to/submodule1 src/changed-file.js
git -C "$SUPERPROJECT_ROOT" commit -m "✨ feat(scope): 功能描述（含子模块更新）"
```

> **常见漏洞**：只 `git -C "$SUPERPROJECT_ROOT" add` 了主项目代码文件，忘记把子模块路径也加入暂存区，导致子模块指针遗漏在外，需要额外补一次提交。
> 执行 `git -C "$SUPERPROJECT_ROOT" add` 前务必用 `git -C "$SUPERPROJECT_ROOT" status` 确认所有 `modified: path/to/submodule (new commits)` 的子模块都已包含在内。

#### 7.3 推送主项目

按照步骤 6.6 的逻辑推送（含远程检测、首次推送设 upstream、权限拒绝处理）。

---

## 完成阶段

### 步骤 8：输出提交摘要

生成完整的提交报告：

```
✅ 提交完成！

📦 子模块 path/to/submodule1/nested
  ✨ feat: 添加新功能 (abc1234)
  🐛 fix: 修复 bug (def5678)

📦 子模块 path/to/submodule1
  ♻️ refactor: 重构代码 (ghi9012)

📦 主项目
  🔗 chore: 更新子模块引用 (jkl3456)
  📝 docs: 更新文档 (mno7890)

🚀 所有变更已推送到远程仓库
```

---

## 错误处理

### 1. 未跟踪的文件

如果有未跟踪的文件：

```bash
untracked=$(git -C "$module_path" ls-files --others --exclude-standard)
if [ -n "$untracked" ]; then
  echo "⚠️ 检测到未跟踪的文件："
  echo "$untracked"
fi
```

使用 AskUserQuestion 询问用户：
```
选项：
1. 将这些文件加入本次提交
2. 忽略（不提交，也不加入 .gitignore）
3. 加入 .gitignore
```

### 2. 子模块状态异常

**未初始化的子模块：**
```bash
if git -C "$SUPERPROJECT_ROOT" submodule status | grep -q '^-'; then
  echo "⚠️ 检测到未初始化的子模块"
fi
```
使用 AskUserQuestion 询问用户是否执行 `git -C "$SUPERPROJECT_ROOT" submodule update --init --recursive`。

**子模块 detached HEAD：**
```bash
module_path="$SUPERPROJECT_ROOT/$submodule"
if ! git -C "$module_path" symbolic-ref -q HEAD; then
  echo "⚠️ 子模块 $submodule 处于 detached HEAD 状态"
  echo "建议先切换到分支再提交"
fi
```
使用 AskUserQuestion 询问用户是继续提交还是先切换分支。

### 3. 其他约束
- 不添加共同作者页脚
- 提交消息必须是中文
- 遵循约定式提交格式
- 保护用户修改内容（代码质量检查时不能重置用户的修改）
- **选择性提交时，只需 `git -C "$module_path" add <目标文件>` 后直接提交**，未暂存的文件不会进入提交，**严禁**用 `git restore` / `git checkout` / `git reset --hard` 等破坏性命令来"排除"文件，否则会丢失未提交的改动

---

### 附录：提交拆分规则（语义分类）

#### A.1 提交前先输出提交计划供用户确认

在执行任何 `git -C <path> add` / `git -C <path> commit` 前，必须先将拟定的提交计划输出给用户：

```
📋 拟提交计划：

提交 1：🐛 fix(sales-follow-up): 修复详情页空值显示问题
  - src/views/sales-follow-up/detail.vue

提交 2：✨ feat(sales-follow-up): 新增签到信息展示及地图预览
  - src/typings/modules/sales-follow-up.ts
  - src/views/sales-follow-up/detail.vue
  - src/lowcode-console（子模块）
  - src/vue3-common（子模块）

提交 3：🔧 chore(deps): 新增 pdfjs-dist 依赖
  - package.json

请确认或修改后再执行提交。
```

**用户明确确认后才能开始执行提交。**

#### A.2 按语义分类拆分，而非按文件类型

拆分的依据是**变更的语义目的**，而非文件类型或文件名：

- **功能新增**（feat）：新接口、新组件、新字段、新交互
- **缺陷修复**（fix）：修复 bug、空值兜底、异常处理
- **依赖变更**（chore/deps）：新增/升级/移除 npm 包
- **重构**（refactor）：不改变外部行为的代码结构调整
- **样式/格式**（style）：纯 UI 样式、代码格式化

**同一文件可能涉及多个语义**，此时需拆分为多次提交。使用 `git -C "$module_path" add -p <file>` 进行交互式 patch 暂存，只选择属于当前提交语义的 hunk，避免整个文件被一次性暂存：

```bash
# 同一文件拆分示例：detail.vue 同时含 fix 和 feat
git -C "$module_path" add -p src/views/detail.vue   # 交互式选择属于 fix 的 hunk
git -C "$module_path" commit -m "🐛 fix(detail): 修复空值显示问题"

git -C "$module_path" add src/views/detail.vue      # 暂存剩余的 feat hunk
git -C "$module_path" commit -m "✨ feat(detail): 新增签到地址字段"
```

#### A.3 子模块指针与主项目业务提交合并

子模块指针变更（`new commits`）**必须与同批次最核心的业务提交合并**，不单独作为 `🔗 chore: 更新子模块引用` 提交，除非主项目本身没有任何代码变更。

```
✅ 正确：
  git -C "$SUPERPROJECT_ROOT" add src/typings/... src/views/... src/lowcode-console src/vue3-common
  git -C "$SUPERPROJECT_ROOT" commit -m "✨ feat(sales-follow-up): 新增签到信息展示（含子模块更新）"

❌ 错误：
  # 先提交业务代码，再单独提交子模块指针
  git -C "$SUPERPROJECT_ROOT" commit -m "✨ feat: 新增签到信息"
  git -C "$SUPERPROJECT_ROOT" commit -m "🔗 chore: 更新子模块引用"
```

---

**命令结束**
