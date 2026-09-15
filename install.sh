#!/usr/bin/env bash

set -uo pipefail

readonly REPOSITORY="lwt-sadais/dsh-desktop-bootstrap"
# 分支阶段自包含：脚本与资源都取自本分支；合并回 main 时改回 'main'。
readonly SOURCE_REF="adapt-desktop-2.0.10"
readonly ARCHIVE_URL="https://github.com/${REPOSITORY}/archive/refs/heads/${SOURCE_REF}.tar.gz"
# v2.0.7 起桌面支持自定义数据目录；优先环境变量 DSH_HOME，最后回退 ~/.dsh。
readonly DSH_HOME="${DSH_HOME:-${HOME}/.dsh}"
readonly PROFILE_DIR="${DSH_HOME}/profiles/desktop"
readonly CODEX_PRESET_ID="codex-mode"
readonly AGENT_PRESETS_DIR="${DSH_HOME}/.agent-presets"
readonly SETTINGS_FILE="${DSH_HOME}/settings.yaml"
readonly PLUGIN_NAMES=(
  "dsh-git-diff"
  "dsh-git-history"
  "dsh-local-file-reference"
  "dsh-plan-review-card"
  "dsh-reasoning-efforts"
  "dsh-better-sidebar"
  "@muwinds/dsh-archived-sessions"
  "@linxin666/dsh-web-all"
  "dsh-free-search"
)
readonly PLUGIN_SOURCES=(
  "github:lwt-sadais/dsh-git-diff#3d955d2ab876d68faa1fa1a58a54462b4dde1465"
  "github:lwt-sadais/dsh-git-history#31617eeb709a25e53c52928c4a5f2f14179d8247"
  "github:lwt-sadais/dsh-local-file-reference#4dba61891126af8ae71cd327a8f9b72124450e93"
  "github:lwt-sadais/dsh-plan-review-card#07c3fa29e3b33272930f1fb9776469cf497df81e"
  "github:lwt-sadais/dsh-reasoning-efforts#9332e2365d6ecccf33e47f87f345c56b12b92b81"
  "github:omdsh-dev/DSH-better-sidebar#8753096a583ff2891d57a0074f1ac71cd5c6003e"
  "github:MuWinds/dsh-archived-sessions#5654381f0f54a4ada786bde569378235e2df01bf"
  "@linxin666/dsh-web-all@0.3.22"
  "dsh-free-search@0.4.28"
)
readonly OBSOLETE_PLUGIN_NAMES=(
  "@linxin666/dsh-web-ui-all"
  "dsh-settings-alpha1-compat"
  "dsh-at-file"
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

# 安装仓库中的全局指令文件 AGENTS.md。
install_agents() {
  mkdir -p "${DSH_HOME}" || fail "无法创建 ${DSH_HOME}。"

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

# 安装仓库中的 Codex 模式 Agent 预设。
install_agent_presets() {
  local source_path="${SOURCE_DIR}/agent-presets/${CODEX_PRESET_ID}"
  local target_path="${AGENT_PRESETS_DIR}/${CODEX_PRESET_ID}"

  [[ -f "${source_path}/agent.cordis.yml" && -f "${source_path}/preset.yml" ]] || fail "初始化资源中缺少 Codex 模式预设。"
  mkdir -p "${AGENT_PRESETS_DIR}" || fail "无法创建 Agent 预设目录。"

  rm -rf "${target_path}" || fail "清理现有 Codex 模式失败。"

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

# 解析 pnpm 构建拦截输出中的依赖键，写入 Desktop Profile 的 pnpm-workspace.yaml allowBuilds 名单。
# 2.0.x 已移除 pnpm approve-builds 流程与 minimumReleaseAgeExclude 机制：桌面在 pnpm 边界统一传
# --config.minimumReleaseAge=0，构建白名单改由 Profile 的 pnpm-workspace.yaml allowBuilds 控制；
# cpu-features 不写入名单即保持被拒。
approve_pending_builds_except_cpu_features() {
  local output="$1"
  local keys_json
  local keys=()

  command -v pnpm >/dev/null 2>&1 || fail "当前终端中找不到 pnpm，无法写入 allowBuilds 构建白名单。"
  [[ -d "${PROFILE_DIR}" ]] || fail "未找到 Desktop Profile 目录 ${PROFILE_DIR}。"

  keys_json="$(node --input-type=module - "${output}" <<'NODE'
const keys = new Set()
const output = process.argv[2] ?? ''
for (const match of output.matchAll(/^Ignored build scripts?:\s*([^\n]+)$/gim)) {
  for (const token of match[1].split(/[,;，；\s]+/)) {
    const key = token.trim().replace(/^['"`]+|['"`]+$/g, '').replace(/@[0-9][0-9A-Za-z.-]*$/, '')
    if (/^[A-Za-z@][A-Za-z0-9._/@-]*$/.test(key)) keys.add(key)
  }
}
for (const match of output.matchAll(/`([@A-Za-z][@A-Za-z0-9._/@-]+)`/g)) keys.add(match[1])
const noise = new Set(['cpu-features', 'Done', 'Progress', 'Ignored', 'builds', 'pnpm-workspace.yaml', 'allowBuilds', 'node_modules'])
console.log(JSON.stringify([...keys].filter((key) => !noise.has(key))))
NODE
)" || fail "解析 pnpm 构建拦截输出失败。"

  mapfile -t keys < <(node -e 'for (const key of JSON.parse(process.argv[1] || "[]")) console.log(key)' "${keys_json}")
  if [[ ${#keys[@]} -eq 0 ]]; then
    log "pnpm 输出中未识别到 allowBuilds 依赖键，请按上方提示手工补齐后重跑。"
    return 1
  fi

  log "正在把依赖键写入 Profile pnpm-workspace.yaml allowBuilds（cpu-features 保持拒绝）：${keys[*]}……"
  DSH_PROFILE_DIR="${PROFILE_DIR}" node --input-type=module - "${keys[@]}" <<'NODE' || fail "写入 Desktop Profile 的 allowBuilds 白名单失败。"
import { readFile, rename, rm, writeFile } from 'node:fs/promises'
import path from 'node:path'

const workspaceFile = path.join(process.env.DSH_PROFILE_DIR, 'pnpm-workspace.yaml')
const keys = process.argv.slice(2)
let source = ''
try { source = await readFile(workspaceFile, 'utf8') } catch (error) { if (error?.code !== 'ENOENT') throw error }
const existing = new Set()
for (const match of source.matchAll(/^allowBuilds:\s*\n((?:[ \t]+-.*\n?)*)/gm)) {
  for (const entry of match[1].matchAll(/-\s*['"]?([^'"\n]+)['"]?/g)) existing.add(entry[1].trim())
}
for (const match of source.matchAll(/^allowBuilds:\s*\[([^\]]*)\]/gm)) {
  for (const entry of match[1].matchAll(/['"]?([^,'"\]]+)['"]?/g)) existing.add(entry[1].trim())
}
const merged = [...new Set([...existing, ...keys])]
const stripped = source.replace(/^allowBuilds:\s*\n(?:[ \t]+-.*\n?)*|^allowBuilds:\s*\[[^\]]*\]\n?/gm, '')
const body = `allowBuilds:\n${merged.map((key) => `  - '${key}'`).join('\n')}\n`
const updated = `${stripped.trimEnd()}\n\n${body}`
const temporaryFile = `${workspaceFile}.tmp-${process.pid}`
try {
  await writeFile(temporaryFile, updated, 'utf8')
  await rename(temporaryFile, workspaceFile)
} catch (error) {
  await rm(temporaryFile, { force: true })
  throw error
}
console.log(JSON.stringify(merged))
NODE
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

  if grep -qiE 'pnpm[[:space:]]+approve-builds|allowBuilds|ERR_PNPM_IGNORED_BUILDS' "${output_file}"; then
    approve_pending_builds_except_cpu_features "$(cat "${output_file}")" || fail "Desktop Profile 插件依赖构建白名单处理失败，请查看上方 pnpm 输出。"
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

# 验证关键文件均已落盘，避免仅凭命令退出状态判断初始化成功。
verify_installation() {
  local required_path
  local required_paths=(
    "${DSH_HOME}/AGENTS.md"
    "${DSH_HOME}/skills/commit/SKILL.md"
    "${DSH_HOME}/skills/gpt-image-generator/SKILL.md"
    "${AGENT_PRESETS_DIR}/${CODEX_PRESET_ID}/agent.cordis.yml"
    "${AGENT_PRESETS_DIR}/${CODEX_PRESET_ID}/preset.yml"
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
  install_agent_presets
  set_default_agent_preset
  install_plugins
  verify_installation

  log "初始化完成。首次使用 gpt-image-generator 时，Skill 会自动检测并询问缺失配置。请完全退出并重新启动 DSH Desktop。"
}

main "$@"
