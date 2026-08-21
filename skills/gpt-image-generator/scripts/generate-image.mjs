#!/usr/bin/env node

import { randomBytes } from "node:crypto";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { basename, dirname, extname, isAbsolute, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { isIP } from "node:net";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SKILL_DIR = resolve(SCRIPT_DIR, "..");
const DEFAULT_CONFIG_PATH = resolve(SKILL_DIR, ".env");
const REQUIRED_CONFIG_NAMES = [
  "SADAIS_IMAGE_API_KEY",
  "SADAIS_IMAGE_BASE_URL",
  "SADAIS_IMAGE_MODEL",
];
const REQUEST_TIMEOUT_MS = 300_000;
const DOWNLOAD_TIMEOUT_MS = 120_000;
const MAX_IMAGE_BYTES = 12 * 1024 * 1024;
const HOST_LIMIT_TIMEOUT_MS = 5_000;
const VALID_SIZES = new Set(["auto", "1024x1024", "1536x1024", "1024x1536"]);
const VALID_QUALITIES = new Set(["auto", "low", "medium", "high"]);

/**
 * 根据 Skill 安装结构确定默认图片目录，标准用户级安装写入宿主根目录，其他结构回退当前项目。
 * @param {string} skillDir 当前 Skill 的绝对目录。
 * @param {string} workingDirectory 当前工作目录。
 * @returns {string}
 */
export function resolveDefaultOutputDirectory(skillDir, workingDirectory) {
  const skillsDirectory = dirname(skillDir);
  if (basename(skillsDirectory) === "skills") {
    return resolve(skillsDirectory, "..", "generated-images");
  }
  return resolve(workingDirectory, "output/imagegen");
}

/**
 * 创建带时间戳和随机后缀的默认文件路径，降低并发调用时的重名概率。
 * @param {string} outputDirectory 默认图片目录。
 * @param {Date} now 用于文件名的当前时间。
 * @returns {string}
 */
export function createDefaultOutputPath(outputDirectory, now = new Date()) {
  const timestamp = now.toISOString().replace(/[-:]/gu, "").replace(/\.\d{3}Z$/u, "Z");
  const uniqueSuffix = randomBytes(4).toString("hex");
  return resolve(outputDirectory, `generated-image-${timestamp}-${uniqueSuffix}.png`);
}

/**
 * 优先使用用户指定的绝对路径，否则按 Skill 安装位置生成默认输出路径。
 * @param {string | undefined} output 用户指定的输出路径。
 * @param {string} skillDir 当前 Skill 的绝对目录。
 * @param {string} workingDirectory 当前工作目录。
 * @returns {string}
 */
export function resolveOutputPath(output, skillDir = SKILL_DIR, workingDirectory = process.cwd()) {
  if (output) {
    if (!isAbsolute(output)) {
      throw new Error("--output 必须是绝对路径");
    }
    return resolve(output);
  }
  return createDefaultOutputPath(resolveDefaultOutputDirectory(skillDir, workingDirectory));
}

/**
 * 解析命令行参数并校验生成图片所需的输入。
 * @param {string[]} argv Node 进程收到的命令行参数。
 * @returns {{checkConfig: true} | {checkHostLimit: true} | {prompt: string, output: string, size: string, quality: string, model?: string}}
 */
function parseArguments(argv) {
  const values = new Map();
  const flags = new Set();

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (!argument.startsWith("--")) {
      throw new Error(`无法识别的参数：${argument}`);
    }

    const name = argument.slice(2);
    if (name === "check-config" || name === "check-host-limit") {
      flags.add(name);
      continue;
    }

    const value = argv[index + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`参数 --${name} 缺少值`);
    }

    values.set(name, value);
    index += 1;
  }

  if (flags.has("check-config") || flags.has("check-host-limit")) {
    if (values.size > 0 || flags.size > 1) {
      throw new Error("检查参数不能与其他参数同时使用");
    }
    return flags.has("check-config") ? { checkConfig: true } : { checkHostLimit: true };
  }

  const prompt = values.get("prompt")?.trim();
  const output = values.get("output")?.trim();
  const size = values.get("size")?.trim() || "auto";
  const quality = values.get("quality")?.trim() || "auto";
  const model = values.get("model")?.trim();

  if (!prompt) {
    throw new Error("必须提供非空的 --prompt");
  }
  if (!VALID_SIZES.has(size)) {
    throw new Error(`不支持的尺寸：${size}`);
  }
  if (!VALID_QUALITIES.has(quality)) {
    throw new Error(`不支持的质量：${quality}`);
  }

  return { prompt, output: resolveOutputPath(output), size, quality, model };
}

/**
 * 读取简单的 KEY=VALUE 私密配置，不覆盖进程中已经设置的环境变量。
 * @param {string} filePath 私密配置文件的绝对路径。
 * @returns {Promise<Record<string, string>>}
 */
async function readPrivateConfig(filePath) {
  let content;
  try {
    content = await readFile(filePath, "utf8");
  } catch (error) {
    if (error?.code === "ENOENT") {
      return {};
    }
    throw new Error(`无法读取私密配置：${error.message}`);
  }

  const config = {};
  for (const rawLine of content.split(/\r?\n/u)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }

    const separator = line.indexOf("=");
    if (separator <= 0) {
      throw new Error("私密配置包含无效行");
    }

    const name = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    config[name] = value;
  }

  return config;
}

/**
 * 合并环境变量与私密文件，生成调用接口所需的配置。
 * @param {Record<string, string>} privateConfig 私密文件解析结果。
 * @param {string | undefined} modelOverride 命令行指定的模型。
 * @returns {{apiKey: string, baseUrl: string, model: string}}
 */
function resolveApiConfig(privateConfig, modelOverride) {
  const resolvedConfig = Object.fromEntries(REQUIRED_CONFIG_NAMES.map((name) => [
    name,
    process.env[name]?.trim() || privateConfig[name]?.trim(),
  ]));
  const missingNames = REQUIRED_CONFIG_NAMES.filter((name) => !resolvedConfig[name]);

  if (missingNames.length > 0) {
    throw new Error(`技能配置不完整，缺少：${missingNames.join(", ")}`);
  }

  return {
    apiKey: resolvedConfig.SADAIS_IMAGE_API_KEY,
    baseUrl: resolvedConfig.SADAIS_IMAGE_BASE_URL,
    model: modelOverride || resolvedConfig.SADAIS_IMAGE_MODEL,
  };
}

/**
 * 检查技能目录中 .env 的完整性，只返回字段名而不输出任何配置值。
 * @param {Record<string, string>} privateConfig 私密文件解析结果。
 * @returns {{configured: boolean, missing: string[]}}
 */
function inspectPrivateConfig(privateConfig) {
  const missing = REQUIRED_CONFIG_NAMES.filter((name) => !privateConfig[name]?.trim());
  return { configured: missing.length === 0, missing };
}

/**
 * 将兼容服务的基础地址规范化为图片生成接口地址。
 * @param {string} baseUrl 用户配置的服务基础地址。
 * @returns {string}
 */
function buildGenerationEndpoint(baseUrl) {
  let url;
  try {
    url = new URL(baseUrl);
  } catch {
    throw new Error("SADAIS_IMAGE_BASE_URL 不是有效 URL");
  }

  if (url.protocol !== "https:") {
    throw new Error("图片接口基础地址必须使用 HTTPS");
  }

  const normalizedPath = url.pathname.replace(/\/+$/u, "");
  url.pathname = normalizedPath.endsWith("/v1")
    ? `${normalizedPath}/images/generations`
    : `${normalizedPath}/v1/images/generations`;
  url.search = "";
  url.hash = "";
  return url.toString();
}

/**
 * 在指定超时内执行 fetch，并确保计时器总能被清理。
 * @param {string} url 请求地址。
 * @param {RequestInit} options fetch 请求参数。
 * @param {number} timeoutMs 超时毫秒数。
 * @returns {Promise<Response>}
 */
async function fetchWithTimeout(url, options, timeoutMs) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } catch (error) {
    if (error?.name === "AbortError") {
      throw new Error(`请求在 ${Math.round(timeoutMs / 1000)} 秒后超时`);
    }
    throw new Error(`网络请求失败：${error.message}`);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * 从当前 DSH 会话的 imageLimits 投影读取宿主附件限制；其他宿主或探测失败时回退脚本安全上限。
 * @returns {Promise<{maxBytes: number, source: "dsh" | "fallback"}>}
 */
async function resolveHostImageByteLimit() {
  const webUrl = process.env.DSH_WEB_URL?.trim();
  const sessionId = process.env.DSH_SESSION_ID?.trim();
  if (!webUrl || !sessionId) {
    return { maxBytes: MAX_IMAGE_BYTES, source: "fallback" };
  }

  let endpoint;
  try {
    endpoint = new URL("/api/session.history", webUrl);
  } catch {
    return { maxBytes: MAX_IMAGE_BYTES, source: "fallback" };
  }
  if (!(["127.0.0.1", "localhost", "[::1]"].includes(endpoint.hostname))) {
    return { maxBytes: MAX_IMAGE_BYTES, source: "fallback" };
  }

  const rpcId = `image-limit-${Date.now()}-${randomBytes(4).toString("hex")}`;
  try {
    const response = await fetchWithTimeout(endpoint.toString(), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        type: "client-request",
        rpcId,
        method: "session.history",
        payload: { sessionId, maxMessages: 1 },
      }),
    }, HOST_LIMIT_TIMEOUT_MS);
    if (!response.ok) {
      return { maxBytes: MAX_IMAGE_BYTES, source: "fallback" };
    }

    const payload = await response.json();
    const result = payload?.rpcId === rpcId ? payload?.result : undefined;
    const limits = result?.ok === true ? result.value?.projections?.values?.imageLimits : undefined;
    const candidates = [limits?.maxImageBytes, limits?.maxMessageImageBytes]
      .filter((value) => Number.isSafeInteger(value) && value > 0);
    if (candidates.length === 0) {
      return { maxBytes: MAX_IMAGE_BYTES, source: "fallback" };
    }
    return { maxBytes: Math.min(MAX_IMAGE_BYTES, ...candidates), source: "dsh" };
  } catch {
    return { maxBytes: MAX_IMAGE_BYTES, source: "fallback" };
  }
}

/**
 * 从错误响应中提取有限长度的安全信息，避免回显凭据或大段响应。
 * @param {Response} response 接口返回的非成功响应。
 * @returns {Promise<string>}
 */
async function formatApiError(response) {
  const text = (await response.text()).slice(0, 1000);
  try {
    const payload = JSON.parse(text);
    const message = payload?.error?.message || payload?.message;
    const code = payload?.error?.code || payload?.code;
    return [message, code ? `code=${code}` : ""].filter(Boolean).join("；") || `HTTP ${response.status}`;
  } catch {
    return text.trim() || `HTTP ${response.status}`;
  }
}

/**
 * 调用 OpenAI 兼容图片生成接口并返回响应数据。
 * @param {string} endpoint 完整的图片生成接口地址。
 * @param {{apiKey: string, model: string}} config 接口认证与模型配置。
 * @param {{prompt: string, size: string, quality: string}} input 生成参数。
 * @returns {Promise<unknown>}
 */
async function requestImage(endpoint, config, input) {
  const response = await fetchWithTimeout(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${config.apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: config.model,
      prompt: input.prompt,
      n: 1,
      size: input.size,
      quality: input.quality,
      output_format: "png",
    }),
  }, REQUEST_TIMEOUT_MS);

  if (!response.ok) {
    throw new Error(`图片接口返回 ${response.status}：${await formatApiError(response)}`);
  }

  try {
    return await response.json();
  } catch {
    throw new Error("图片接口返回了无法解析的 JSON");
  }
}

/**
 * 判断 IPv4 或 IPv6 字面量是否属于不应下载的本地或私有地址。
 * @param {string} hostname URL 中的主机名。
 * @returns {boolean}
 */
function isPrivateIpLiteral(hostname) {
  const address = hostname.replace(/^\[|\]$/gu, "").toLowerCase();
  const version = isIP(address);
  if (version === 4) {
    const [a, b] = address.split(".").map(Number);
    return a === 10
      || a === 127
      || (a === 169 && b === 254)
      || (a === 172 && b >= 16 && b <= 31)
      || (a === 192 && b === 168)
      || a === 0;
  }
  if (version === 6) {
    return address === "::1" || address === "::" || address.startsWith("fc") || address.startsWith("fd") || address.startsWith("fe80:");
  }
  return hostname.toLowerCase() === "localhost";
}

/**
 * 下载接口返回的临时图片 URL，不向图片主机转发 API 凭据。
 * @param {string} imageUrl 图片临时地址。
 * @param {number} maxImageBytes 当前宿主允许导入附件的单图字节上限。
 * @returns {Promise<{bytes: Buffer, hintedMimeType: string | null}>}
 */
async function downloadImage(imageUrl, maxImageBytes) {
  let url;
  try {
    url = new URL(imageUrl);
  } catch {
    throw new Error("图片响应包含无效的下载 URL");
  }

  if (url.protocol !== "https:" || url.username || url.password || isPrivateIpLiteral(url.hostname)) {
    throw new Error("图片下载 URL 不符合安全要求");
  }

  const response = await fetchWithTimeout(url.toString(), { redirect: "follow" }, DOWNLOAD_TIMEOUT_MS);
  if (!response.ok) {
    throw new Error(`图片下载失败：HTTP ${response.status}`);
  }

  const contentLength = Number(response.headers.get("content-length") || 0);
  if (contentLength > maxImageBytes) {
    throw new Error(`生成图片超过宿主附件大小上限（${maxImageBytes} 字节）`);
  }

  const bytes = Buffer.from(await response.arrayBuffer());
  return { bytes, hintedMimeType: response.headers.get("content-type")?.split(";", 1)[0]?.trim() || null };
}

/**
 * 从接口响应中取得 Base64 图片或下载 URL 图片。
 * @param {unknown} payload 图片接口的 JSON 响应。
 * @param {number} maxImageBytes 当前宿主允许导入附件的单图字节上限。
 * @returns {Promise<{bytes: Buffer, hintedMimeType: string | null}>}
 */
async function extractImage(payload, maxImageBytes) {
  const item = Array.isArray(payload?.data) ? payload.data[0] : undefined;
  if (typeof item?.b64_json === "string" && item.b64_json.length > 0) {
    return { bytes: Buffer.from(item.b64_json, "base64"), hintedMimeType: null };
  }
  if (typeof item?.url === "string" && item.url.length > 0) {
    return await downloadImage(item.url, maxImageBytes);
  }
  throw new Error("图片响应中既没有 b64_json，也没有可用的 url");
}

/**
 * 根据文件魔数识别支持的图片 MIME 类型，并校验服务端提示类型。
 * @param {Buffer} bytes 图片二进制数据。
 * @param {string | null} hintedMimeType HTTP 响应提示的 MIME 类型。
 * @returns {string}
 */
function detectImageMimeType(bytes, hintedMimeType) {
  let detected;
  if (bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    detected = "image/png";
  } else if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[bytes.length - 2] === 0xff && bytes[bytes.length - 1] === 0xd9) {
    detected = "image/jpeg";
  } else if (bytes.subarray(0, 4).toString("ascii") === "RIFF" && bytes.subarray(8, 12).toString("ascii") === "WEBP") {
    detected = "image/webp";
  } else {
    throw new Error("接口返回的内容不是受支持的 PNG、JPEG 或 WebP 图片");
  }

  if (hintedMimeType?.startsWith("image/") && hintedMimeType !== detected) {
    throw new Error(`图片 MIME 类型不一致：响应为 ${hintedMimeType}，内容为 ${detected}`);
  }
  return detected;
}

/**
 * 校验输出扩展名与真实图片类型一致，避免保存出误导性的文件。
 * @param {string} outputPath 用户指定的输出路径。
 * @param {string} mimeType 实际图片 MIME 类型。
 */
function validateOutputExtension(outputPath, mimeType) {
  const allowedExtensions = {
    "image/png": new Set([".png"]),
    "image/jpeg": new Set([".jpg", ".jpeg"]),
    "image/webp": new Set([".webp"]),
  };
  const extension = extname(outputPath).toLowerCase();
  if (!allowedExtensions[mimeType]?.has(extension)) {
    throw new Error(`输出扩展名 ${extension || "（无）"} 与 ${mimeType} 不匹配`);
  }
}

/**
 * 将图片原子性要求之外的必要目录创建后保存为二进制文件。
 * @param {string} outputPath 图片输出绝对路径。
 * @param {Buffer} bytes 已校验的图片内容。
 */
async function saveImage(outputPath, bytes) {
  await mkdir(dirname(outputPath), { recursive: true });
  try {
    await writeFile(outputPath, bytes, { mode: 0o600, flag: "wx" });
  } catch (error) {
    if (error?.code === "EEXIST") {
      throw new Error(`输出文件已存在，请更换路径：${outputPath}`);
    }
    throw error;
  }
}

/**
 * 执行完整的图片生成、宿主限制校验和保存流程，并输出供 read_image 使用的结构化结果。
 */
async function main() {
  const input = parseArguments(process.argv.slice(2));
  const privateConfig = await readPrivateConfig(DEFAULT_CONFIG_PATH);

  if (input.checkConfig) {
    process.stdout.write(`${JSON.stringify(inspectPrivateConfig(privateConfig))}\n`);
    return;
  }
  if (input.checkHostLimit) {
    const hostLimit = await resolveHostImageByteLimit();
    process.stdout.write(`${JSON.stringify({
      maxImageBytes: hostLimit.maxBytes,
      source: hostLimit.source,
    })}\n`);
    return;
  }

  const config = resolveApiConfig(privateConfig, input.model);
  const hostLimit = await resolveHostImageByteLimit();
  const endpoint = buildGenerationEndpoint(config.baseUrl);
  const payload = await requestImage(endpoint, config, input);
  const { bytes, hintedMimeType } = await extractImage(payload, hostLimit.maxBytes);

  if (bytes.length === 0) {
    throw new Error("接口返回了空图片");
  }
  if (bytes.length > hostLimit.maxBytes) {
    throw new Error(`生成图片超过宿主附件大小上限（${hostLimit.maxBytes} 字节）`);
  }

  const mimeType = detectImageMimeType(bytes, hintedMimeType);
  validateOutputExtension(input.output, mimeType);
  await saveImage(input.output, bytes);
  process.stdout.write(`${JSON.stringify({
    path: input.output,
    mediaType: mimeType,
    bytes: bytes.length,
    attachmentMaxBytes: hostLimit.maxBytes,
    attachmentLimitSource: hostLimit.source,
  })}\n`);
}

const isDirectExecution = process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href;
if (isDirectExecution) {
  main().catch((error) => {
    process.stderr.write(`图片生成失败：${error.message}\n`);
    process.exitCode = 1;
  });
}
