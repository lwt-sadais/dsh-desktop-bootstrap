#!/usr/bin/env bash

set -uo pipefail

readonly REPOSITORY="lwt-sadais/dsh-desktop-bootstrap"
readonly ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/main.tar.gz"
readonly DSH_HOME="${HOME}/.dsh"
readonly PROFILE_DIR="${DSH_HOME}/profiles/desktop"
readonly PLUGINS=(
  "github:zhu1090093659/dsh-web-ui"
  "github:FSMargoo/dsh-at-file"
  "github:MuWinds/dsh-archived-sessions"
  "github:lwt-sadais/dsh-git-diff"
  "github:lwt-sadais/dsh-local-file-reference"
)

TEMP_DIR=""
SOURCE_DIR=""

# 输出带统一前缀的进度信息，便于用户定位当前步骤。
log() {
  printf '[DSH 初始化] %s\n' "$*"
}

# 输出错误信息并以非零状态结束脚本。
fail() {
  printf '[DSH 初始化] 错误：%s\n' "$*" >&2
  exit 1
}

# 无论脚本成功或失败，都删除本次下载产生的临时目录。
cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}

# 检查脚本依赖的命令，并确认当前位于 DSH Desktop 打开的专用终端。
check_prerequisites() {
  local command_name
  for command_name in curl tar mktemp cp date grep tee; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "缺少命令 ${command_name}，请先安装后重试。"
  done

  command -v dsh >/dev/null 2>&1 || fail "当前终端无法执行 dsh。请启动 DSH Desktop，从应用内打开 DSH Desktop 专用终端，再在该终端中重新执行本命令；普通系统终端无法直接使用 dsh。"
}

# 下载默认分支源码压缩包并解析出唯一的仓库根目录。
download_source() {
  TEMP_DIR="$(mktemp -d)" || fail "无法创建临时目录。"
  log "正在下载初始化资源……"
  curl -fsSL "${ARCHIVE_URL}" -o "${TEMP_DIR}/source.tar.gz" || fail "下载仓库失败，请检查网络或 GitHub 访问状态。"
  tar -xzf "${TEMP_DIR}/source.tar.gz" -C "${TEMP_DIR}" || fail "解压仓库失败。"

  SOURCE_DIR="${TEMP_DIR}/dsh-desktop-bootstrap-main"
  [[ -d "${SOURCE_DIR}" ]] || fail "下载内容中未找到预期的仓库目录。"
}

# 备份已有全局指令文件，并安装仓库中的 AGENTS.md。
install_agents() {
  local backup_path
  mkdir -p "${DSH_HOME}" || fail "无法创建 ${DSH_HOME}。"

  if [[ -e "${DSH_HOME}/AGENTS.md" || -L "${DSH_HOME}/AGENTS.md" ]]; then
    backup_path="${DSH_HOME}/AGENTS.md.backup.$(date +%Y%m%d%H%M%S)"
    cp -L "${DSH_HOME}/AGENTS.md" "${backup_path}" || fail "备份现有 AGENTS.md 失败。"
    log "已备份现有 AGENTS.md：${backup_path}"
  fi

  cp "${SOURCE_DIR}/AGENTS.md" "${DSH_HOME}/AGENTS.md" || fail "安装 AGENTS.md 失败。"
  chmod 0644 "${DSH_HOME}/AGENTS.md" || fail "设置 AGENTS.md 权限失败。"
  log "已安装全局 AGENTS.md。"
}

# 合并仓库 Skills；仓库不包含 .env，因此不会创建或覆盖用户私密配置。
install_skills() {
  mkdir -p "${DSH_HOME}/skills" || fail "无法创建 Skills 目录。"
  cp -R "${SOURCE_DIR}/skills/." "${DSH_HOME}/skills/" || fail "安装 Skills 失败。"
  log "已合并安装用户级 Skills，现有私密配置保持不变。"
}

# 在 Desktop Profile 中批准 pnpm 待执行的依赖构建脚本。
approve_pending_builds() {
  command -v pnpm >/dev/null 2>&1 || {
    log "错误输出要求执行 pnpm approve-builds，但当前终端中找不到 pnpm。"
    return 1
  }
  [[ -d "${PROFILE_DIR}" ]] || {
    log "错误输出要求执行 pnpm approve-builds，但未找到 ${PROFILE_DIR}。"
    return 1
  }

  log "检测到 pnpm approve-builds 提示，正在自动执行 pnpm approve-builds --all……"
  (cd "${PROFILE_DIR}" && pnpm approve-builds --all)
}

# 在单个恢复事务中安装全部插件；检测到 approve-builds 提示时批准后仅重试一次。
install_plugins() {
  local output_file="${TEMP_DIR}/plugin-output.log"
  local status

  log "正在批量安装 Desktop Profile 插件：${PLUGINS[*]}……"
  : >"${output_file}"
  dsh plugin add --profile desktop "${PLUGINS[@]}" > >(tee "${output_file}") 2>&1
  status=$?
  if [[ ${status} -eq 0 ]]; then
    log "已完成 Desktop Profile 插件安装。"
    return 0
  fi

  if grep -qiE 'pnpm[[:space:]]+approve-builds' "${output_file}"; then
    approve_pending_builds || fail "Desktop Profile 插件安装失败，且无法批准 pnpm 待执行的依赖构建脚本。"
    log "正在重试 Desktop Profile 插件批量安装……"
    dsh plugin add --profile desktop "${PLUGINS[@]}" || fail "Desktop Profile 插件批量安装重试失败。"
    log "已完成 Desktop Profile 插件安装。"
    return 0
  fi

  fail "Desktop Profile 插件安装失败，请根据上方错误处理后重试。"
}

# 验证关键文件均已落盘，避免仅凭命令退出状态判断初始化成功。
verify_installation() {
  local required_path
  local required_paths=(
    "${DSH_HOME}/AGENTS.md"
    "${DSH_HOME}/skills/commit/SKILL.md"
    "${DSH_HOME}/skills/gpt-image-generator/SKILL.md"
  )

  for required_path in "${required_paths[@]}"; do
    [[ -f "${required_path}" ]] || fail "验证失败，未找到 ${required_path}。"
  done

  log "文件验证通过。"
}

# 按固定顺序执行初始化流程，确保失败时立即停止后续关键步骤。
main() {
  trap cleanup EXIT
  check_prerequisites
  download_source
  install_agents
  install_skills
  install_plugins
  verify_installation

  log "初始化完成。首次使用 gpt-image-generator 时，Skill 会自动检测并询问缺失配置。请完全退出并重新启动 DSH Desktop。"
}

main "$@"
