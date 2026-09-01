#!/usr/bin/env bash

set -uo pipefail

readonly REPOSITORY="lwt-sadais/dsh-desktop-bootstrap"
readonly ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/main.tar.gz"
readonly DSH_HOME="${HOME}/.dsh"
readonly PROFILE_DIR="${DSH_HOME}/profiles/desktop"
readonly COMPAT_PLUGIN_NAME="dsh-settings-alpha1-compat"
readonly COMPAT_PLUGIN_DIR="${DSH_HOME}/plugins/${COMPAT_PLUGIN_NAME}"
readonly BETTER_SIDEBAR_FORK="github:lwt-sadais/DSH-better-sidebar#ed28df8d66f1b9f9871fb358c6616289d23358f3"
readonly CODEX_PRESET_ID="codex-mode"
readonly AGENT_PRESETS_DIR="${DSH_HOME}/.agent-presets"
readonly SETTINGS_FILE="${DSH_HOME}/settings.yaml"
readonly PLUGIN_NAMES=(
  "${COMPAT_PLUGIN_NAME}"
  "@linxin666/dsh-web-all"
  "dsh-better-sidebar"
  "dsh-at-file"
  "@muwinds/dsh-archived-sessions"
  "dsh-git-diff"
  "dsh-git-history"
  "dsh-local-file-reference"
  "dsh-plan-review-card"
  "dsh-reasoning-efforts"
)
readonly PLUGIN_SOURCES=(
  "link:${COMPAT_PLUGIN_DIR}"
  "@linxin666/dsh-web-all@0.3.9"
  "${BETTER_SIDEBAR_FORK}"
  "github:lwt-sadais/dsh-at-file#6dbc6209a881c97ae094081e5fb8899a9f4b1b05"
  "github:lwt-sadais/dsh-archived-sessions#6154d11f11493cc24057321a69fbef4bc346f05b"
  "github:lwt-sadais/dsh-git-diff#69c8458d3eefc507f4512983934cc046b4e736dd"
  "github:lwt-sadais/dsh-git-history#cf22d3e2c839d38f63064568021cdc2b854dd41d"
  "github:lwt-sadais/dsh-local-file-reference#4ccc956cc14b1e2d4c19634287b52dcfc3a3c955"
  "github:lwt-sadais/dsh-plan-review-card#43d8f2ddf55512f181c26a2e09fc63ece8c11377"
  "github:lwt-sadais/dsh-reasoning-efforts#eb66af3df2c99e5d5014bcedd61abb7d7c61a7d3"
)
readonly OBSOLETE_PLUGIN_NAMES=(
  "@linxin666/dsh-web-ui-all"
)
readonly MINIMUM_RELEASE_AGE_EXCLUDES=(
  "@linxin666/dsh-client-ui-plugin-manager@0.3.9"
  "@linxin666/dsh-client-ui-community-plugins@0.3.9"
  "@linxin666/dsh-client-ui-market@0.3.9"
  "@linxin666/dsh-client-ui-task-board@0.3.9"
  "@linxin666/dsh-client-ui-git-graph@0.3.9"
  "@linxin666/dsh-perf@0.3.9"
  "@linxin666/dsh-pet@0.3.9"
  "@linxin666/dsh-remote-web-ui@0.3.9"
  "@linxin666/dsh-ssh@0.3.9"
  "@linxin666/dsh-tool-describe-image@0.3.9"
  "@linxin666/dsh-liangshen@0.3.9"
  "@linxin666/dsh-client-ui-skill-explorer@0.3.9"
  "@linxin666/dsh-desktop-launcher@0.3.9"
  "@linxin666/dsh-doctor@0.3.9"
  "@linxin666/dsh-usage@0.3.9"
  "@linxin666/dsh-client-ui-web-ui-settings@0.3.9"
  "@linxin666/dsh-client-ui-skin-center@0.3.9"
  "@linxin666/dsh-web-all@0.3.9"
)

TEMP_DIR=""
SOURCE_DIR=""
YAML_MODULE=""

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
  for command_name in curl tar mktemp cp date grep tee node; do
    command -v "${command_name}" >/dev/null 2>&1 || fail "缺少命令 ${command_name}，请先安装后重试。"
  done

  command -v dsh >/dev/null 2>&1 || fail "当前终端无法执行 dsh。请启动 DSH Desktop，从应用内打开 DSH Desktop 专用终端，再在该终端中重新执行本命令；普通系统终端无法直接使用 dsh。"
}

# 兼容 Desktop 2.0.1 的 Profile 依赖布局和 2.0.2 起由桌面应用提供依赖的布局。
resolve_yaml_module() {
  local profile_yaml_module="${PROFILE_DIR}/node_modules/yaml"
  local resolved_package

  if [[ -f "${profile_yaml_module}/package.json" ]]; then
    YAML_MODULE="${profile_yaml_module}"
    return
  fi

  resolved_package="$(node -p "require.resolve('yaml/package.json')" 2>/dev/null)" \
    || fail "当前 DSH Desktop 运行环境无法解析 yaml 依赖，无法安全更新 ${SETTINGS_FILE}。"
  [[ -n "${resolved_package}" ]] \
    || fail "当前 DSH Desktop 运行环境无法解析 yaml 依赖，无法安全更新 ${SETTINGS_FILE}。"
  YAML_MODULE="$(node -e 'process.stdout.write(require("node:path").dirname(process.argv[1]))' "${resolved_package}")" \
    || fail "无法确定 yaml 依赖目录。"
  [[ -f "${YAML_MODULE}/package.json" ]] || fail "解析到的 yaml 依赖无效：${YAML_MODULE}。"
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

# 安装仓库内置的 Harness alpha.1 设置 API 兼容插件。
install_settings_compat_plugin() {
  local source_path="${SOURCE_DIR}/plugins/${COMPAT_PLUGIN_NAME}"

  [[ -f "${source_path}/package.json" ]] || fail "兼容插件源码不完整：${source_path}。"
  mkdir -p "${COMPAT_PLUGIN_DIR}" || fail "无法创建兼容插件目录 ${COMPAT_PLUGIN_DIR}。"
  cp -R "${source_path}/." "${COMPAT_PLUGIN_DIR}/" || fail "安装设置 API 兼容插件失败。"
  log "已安装 Harness alpha.1 设置 API 兼容插件。"
}

# 备份已有同名 Agent 预设，并安装仓库中的 Codex 模式。
install_agent_presets() {
  local source_path="${SOURCE_DIR}/agent-presets/${CODEX_PRESET_ID}"
  local target_path="${AGENT_PRESETS_DIR}/${CODEX_PRESET_ID}"
  local backup_path

  [[ -f "${source_path}/agent.cordis.yml" && -f "${source_path}/preset.yml" ]] || fail "初始化资源中缺少 Codex 模式预设。"
  mkdir -p "${AGENT_PRESETS_DIR}" || fail "无法创建 Agent 预设目录。"

  if [[ -e "${target_path}" || -L "${target_path}" ]]; then
    backup_path="${target_path}.backup.$(date +%Y%m%d%H%M%S)"
    cp -R -L "${target_path}" "${backup_path}" || fail "备份现有 Codex 模式失败。"
    log "已备份现有 Codex 模式：${backup_path}"
    rm -rf "${target_path}" || fail "清理现有 Codex 模式失败。"
  fi

  cp -R "${source_path}" "${target_path}" || fail "安装 Codex 模式失败。"
  chmod -R u+rwX,go-rwx "${target_path}" || fail "设置 Codex 模式权限失败。"
  log "已安装 Codex 模式。"
}

# 保留其余用户设置，仅将新会话的默认 Agent 预设设为 Codex 模式。
set_default_agent_preset() {
  mkdir -p "${DSH_HOME}" || fail "无法创建 ${DSH_HOME}。"
  DSH_SETTINGS_FILE="${SETTINGS_FILE}" DSH_YAML_MODULE="${YAML_MODULE}" DSH_CODEX_PRESET_ID="${CODEX_PRESET_ID}" node --input-type=module <<'NODE' || fail "设置默认 Agent 预设失败。"
import { readFile, rename, rm, writeFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'

const settingsFile = process.env.DSH_SETTINGS_FILE
const yamlModule = process.env.DSH_YAML_MODULE
const presetId = process.env.DSH_CODEX_PRESET_ID
const require = createRequire(import.meta.url)
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
NODE
  chmod 0600 "${SETTINGS_FILE}" || fail "设置 ${SETTINGS_FILE} 权限失败。"
  log "已将默认 Agent 预设设为 Codex 模式。"
}

# 将已核对的 Web UI 精确版本加入最短发布时间豁免，同时保留用户已有配置。
add_minimum_release_age_excludes() {
  local current_json merged_json verified_json

  command -v pnpm >/dev/null 2>&1 || fail "当前终端中找不到 pnpm，无法配置依赖供应链策略。"
  [[ -d "${PROFILE_DIR}" ]] || fail "未找到 Desktop Profile 目录 ${PROFILE_DIR}。"

  current_json="$(cd "${PROFILE_DIR}" && pnpm config get --location project --json minimumReleaseAgeExclude)" || fail "读取 Desktop Profile 的 minimumReleaseAgeExclude 配置失败。"
  merged_json="$(node -e '
    const current = process.argv[1] ? JSON.parse(process.argv[1]) : [];
    const required = process.argv.slice(2);
    process.stdout.write(JSON.stringify([...new Set([...current, ...required])]));
  ' "${current_json}" "${MINIMUM_RELEASE_AGE_EXCLUDES[@]}")" || fail "合并 Desktop Profile 的 minimumReleaseAgeExclude 配置失败。"

  (cd "${PROFILE_DIR}" && pnpm config set --location project --json minimumReleaseAgeExclude "${merged_json}") || fail "写入 Desktop Profile 的 minimumReleaseAgeExclude 配置失败。"
  verified_json="$(cd "${PROFILE_DIR}" && pnpm config get --location project --json minimumReleaseAgeExclude)" || fail "验证 Desktop Profile 的 minimumReleaseAgeExclude 配置失败。"
  node -e '
    const configured = new Set(JSON.parse(process.argv[1]));
    const missing = process.argv.slice(2).filter((entry) => !configured.has(entry));
    if (missing.length) {
      console.error(`缺少精确豁免：${missing.join(", ")}`);
      process.exit(1);
    }
  ' "${verified_json}" "${MINIMUM_RELEASE_AGE_EXCLUDES[@]}" || fail "供应链策略配置验证失败。"

  log "已保留现有策略，并加入 Web UI 0.3.9 的精确发布时间豁免。"
}

# 拒绝可选的 cpu-features 原生构建，再批准其余全部待审批依赖脚本。
approve_pending_builds_except_cpu_features() {
  local output_file="$1"

  command -v pnpm >/dev/null 2>&1 || return 1
  [[ -d "${PROFILE_DIR}" ]] || return 1

  if grep -qiE '(^|[[:space:],:])cpu-features(@|[[:space:],]|$)' "${output_file}"; then
    log "正在拒绝可选原生依赖 cpu-features 的构建脚本……"
    (cd "${PROFILE_DIR}" && pnpm approve-builds '!cpu-features') || return 1
  fi

  log "正在批准除 cpu-features 外的全部待审批依赖构建脚本……"
  (cd "${PROFILE_DIR}" && pnpm approve-builds --all)
}

# 执行一次插件卸载或安装；依赖构建被拦截时完成审批并仅重试原命令一次。
run_plugin_operation() {
  local action="$1"
  local label="$2"
  shift 2
  local output_file="${TEMP_DIR}/plugin-${action}-output.log"
  local status

  log "正在${label} Desktop Profile 插件：$*……"
  : >"${output_file}"
  dsh plugin --profile desktop "${action}" "$@" > >(tee "${output_file}") 2>&1
  status=$?
  if [[ ${status} -eq 0 ]]; then
    log "已完成 Desktop Profile 插件${label}。"
    return 0
  fi

  if grep -qiE 'pnpm[[:space:]]+approve-builds|ERR_PNPM_IGNORED_BUILDS' "${output_file}"; then
    approve_pending_builds_except_cpu_features "${output_file}" || fail "Desktop Profile 插件依赖构建审批失败，请查看上方 pnpm 输出。"
    log "正在重试 Desktop Profile 插件${label}……"
    dsh plugin --profile desktop "${action}" "$@" || fail "Desktop Profile 插件${label}重试失败。"
    log "已完成 Desktop Profile 插件${label}。"
    return 0
  fi

  fail "Desktop Profile 插件${label}失败，请根据上方错误处理后重试。"
}

# 先卸载所有已存在的目标或废弃插件，再按完整来源统一重新安装目标插件。
install_plugins() {
  local manifest="${PROFILE_DIR}/package.json"
  local managed_flags index
  local managed_names=("${PLUGIN_NAMES[@]}" "${OBSOLETE_PLUGIN_NAMES[@]}")
  local remove_names=()

  [[ ${#PLUGIN_NAMES[@]} -eq ${#PLUGIN_SOURCES[@]} ]] || fail "插件包名与来源配置数量不一致。"
  managed_flags="$(node -e '
    const { readFileSync } = require("node:fs");
    let dependencies = {};
    try { dependencies = JSON.parse(readFileSync(process.argv[1], "utf8")).dependencies ?? {}; }
    catch (error) { if (error?.code !== "ENOENT") throw error; }
    for (const name of process.argv.slice(2)) console.log(Object.hasOwn(dependencies, name) ? "1" : "0");
  ' "${manifest}" "${managed_names[@]}")" || fail "读取 Desktop Profile 插件声明失败。"

  index=0
  while IFS= read -r installed; do
    [[ "${installed}" == "1" ]] && remove_names+=("${managed_names[${index}]}")
    index=$((index + 1))
  done <<<"${managed_flags}"
  [[ ${index} -eq ${#managed_names[@]} ]] || fail "Desktop Profile 插件分类结果不完整。"

  if [[ ${#remove_names[@]} -gt 0 ]]; then
    run_plugin_operation remove "卸载现有" "${remove_names[@]}"
  else
    log "当前没有已安装的目标或废弃插件需要卸载。"
  fi

  run_plugin_operation add "安装" "${PLUGIN_SOURCES[@]}"
}

# 确保兼容层先于会调用新设置 API 的第三方聚合包加载。
order_settings_compat_bundle() {
  DSH_PROFILE_DIR="${PROFILE_DIR}" node --input-type=module <<'NODE' || fail "无法调整设置兼容插件的加载顺序。"
import { readFile, writeFile } from 'node:fs/promises'
import { join } from 'node:path'

const manifestPath = join(process.env.DSH_PROFILE_DIR, 'package.json')
const profile = JSON.parse(await readFile(manifestPath, 'utf8'))
const bundles = profile.dsh?.profile?.bundles
if (!Array.isArray(bundles)) throw new Error('Profile manifest 缺少 dsh.profile.bundles')
const compat = 'dsh-settings-alpha1-compat'
const webAll = '@linxin666/dsh-web-all'
const compatIndex = bundles.indexOf(compat)
const webAllIndex = bundles.indexOf(webAll)
if (compatIndex === -1 || webAllIndex === -1) throw new Error('Profile Bundle 列表缺少兼容插件或 dsh-web-all')
if (compatIndex > webAllIndex) {
  bundles.splice(compatIndex, 1)
  bundles.splice(webAllIndex, 0, compat)
  await writeFile(manifestPath, `${JSON.stringify(profile, null, 2)}\n`, 'utf8')
}
NODE
  log "已确认设置兼容插件先于 Web UI 聚合包加载。"
}

# 验证关键文件均已落盘，避免仅凭命令退出状态判断初始化成功。
verify_installation() {
  local required_path
  local required_paths=(
    "${DSH_HOME}/AGENTS.md"
    "${DSH_HOME}/skills/commit/SKILL.md"
    "${DSH_HOME}/skills/gpt-image-generator/SKILL.md"
    "${AGENT_PRESETS_DIR}/${CODEX_PRESET_ID}/agent.cordis.yml"
    "${AGENT_PRESETS_DIR}/${CODEX_PRESET_ID}/preset.yml"
    "${COMPAT_PLUGIN_DIR}/package.json"
    "${COMPAT_PLUGIN_DIR}/index.js"
    "${COMPAT_PLUGIN_DIR}/cordis.patch.yml"
  )

  for required_path in "${required_paths[@]}"; do
    [[ -f "${required_path}" ]] || fail "验证失败，未找到 ${required_path}。"
  done

  DSH_SETTINGS_FILE="${SETTINGS_FILE}" DSH_YAML_MODULE="${YAML_MODULE}" DSH_CODEX_PRESET_ID="${CODEX_PRESET_ID}" node --input-type=module <<'NODE' || fail "验证失败，默认 Agent 预设不是 Codex 模式。"
import { readFile } from 'node:fs/promises'
import { createRequire } from 'node:module'
import { pathToFileURL } from 'node:url'

const require = createRequire(import.meta.url)
const { parse } = await import(pathToFileURL(require.resolve(process.env.DSH_YAML_MODULE)).href)
const settings = parse(await readFile(process.env.DSH_SETTINGS_FILE, 'utf8'))
if (settings?.['agent-presets']?.default !== process.env.DSH_CODEX_PRESET_ID) process.exit(1)
NODE

  DSH_PROFILE_DIR="${PROFILE_DIR}" node --input-type=module - "${PLUGIN_NAMES[@]}" <<'NODE' || fail "验证失败，Desktop Profile 插件声明或安装产物不完整。"
import { access, readFile } from 'node:fs/promises'
import { join } from 'node:path'

const profileDir = process.env.DSH_PROFILE_DIR
const names = process.argv.slice(2)
const profile = JSON.parse(await readFile(join(profileDir, 'package.json'), 'utf8'))
const dependencies = profile.dependencies ?? {}
const bundleList = profile.dsh?.profile?.bundles ?? []
const bundles = new Set(bundleList)
const compatIndex = bundleList.indexOf('dsh-settings-alpha1-compat')
const webAllIndex = bundleList.indexOf('@linxin666/dsh-web-all')
if (compatIndex === -1 || webAllIndex === -1 || compatIndex > webAllIndex) {
  throw new Error('设置兼容插件必须位于 dsh-web-all 之前')
}
for (const name of names) {
  if (!Object.hasOwn(dependencies, name)) throw new Error(`Profile dependencies 缺少 ${name}`)
  const packageDir = join(profileDir, 'node_modules', ...name.split('/'))
  const manifest = JSON.parse(await readFile(join(packageDir, 'package.json'), 'utf8'))
  if (manifest.dsh?.bundle?.patch !== undefined && !bundles.has(name)) {
    throw new Error(`Profile Bundle 列表缺少 ${name}`)
  }
  if (name === 'dsh-plan-review-card') {
    if (manifest.dsh?.client === undefined || manifest.exports?.['./client'] === undefined) {
      throw new Error('dsh-plan-review-card 缺少 Client 声明或导出')
    }
    await access(join(packageDir, manifest.main))
    const clientExport = typeof manifest.exports['./client'] === 'string'
      ? manifest.exports['./client']
      : manifest.exports['./client'].default
    await access(join(packageDir, clientExport))
  }
}
NODE
  log "文件、默认 Agent 预设与 Desktop Profile 插件验证通过。"
}

# 按固定顺序执行初始化流程，确保失败时立即停止后续关键步骤。
main() {
  trap cleanup EXIT
  check_prerequisites
  resolve_yaml_module
  download_source
  install_agents
  install_skills
  install_settings_compat_plugin
  install_agent_presets
  set_default_agent_preset
  add_minimum_release_age_excludes
  install_plugins
  order_settings_compat_bundle
  verify_installation

  log "初始化完成。首次使用 gpt-image-generator 时，Skill 会自动检测并询问缺失配置。请完全退出并重新启动 DSH Desktop。"
}

main "$@"
