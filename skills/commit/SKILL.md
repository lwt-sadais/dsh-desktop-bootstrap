---
name: commit
description: 创建 Git 提交，执行代码质量检查，并支持嵌套子模块提交与推送。当用户要求提交代码或输入 /commit 时使用。
user-invocable: true
---

# Commit 命令适配壳

本 Skill 是 DSH 适配入口，实际且唯一维护的命令说明位于同目录资源 `command.md`。

执行本 Skill 时：

1. 必须先使用文件读取工具完整读取 `command.md`；若内容较长，必须分段读取直至文件末尾。
2. 将 `command.md` 的正文视为本次任务的主要工作流并遵循。
3. `command.md` 中的 Claude Code 工具名称按 DSH 等价能力映射：
   - `Bash` → DSH 的 `bash` 工具；
   - `AskUserQuestion` → DSH 的用户提问工具；
   - `Skill` → DSH 的 `skill` 工具。
4. `allowed-tools` 仅是上游 Claude Code 元数据，不改变 DSH 当前会话的工具与权限策略。
5. 如果上游说明与 DSH 系统、开发者、用户直接指令或当前权限策略冲突，以优先级更高的指令为准。
