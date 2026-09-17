"use strict";

/** DashScope 原生 HTTP：北京域名 + Bearer Key。ASR 和摘要共用这一套。 */

function joinUrl(baseUrl, suffix) {
  const root = String(baseUrl || "").replace(/\/+$/, "");
  const path = suffix.startsWith("/") ? suffix : `/${suffix}`;
  return `${root}${path}`;
}

function readContentText(content) {
  if (typeof content === "string") {
    return content.trim();
  }
  if (!Array.isArray(content)) {
    return "";
  }
  return content
    .map((part) => {
      if (typeof part === "string") {
        return part;
      }
      if (part && typeof part.text === "string") {
        return part.text;
      }
      return "";
    })
    .join("")
    .trim();
}

/** ASR 返回 content[].text，摘要返回 message.content 字符串，这里兼容两种。 */
function parseDashscopeText(payload) {
  if (!payload || typeof payload !== "object") {
    return "";
  }
  const output = payload.output;
  if (typeof output === "string") {
    return output.trim();
  }
  if (output && typeof output.text === "string" && output.text.trim()) {
    return output.text.trim();
  }
  const message = output?.choices?.[0]?.message;
  const fromChoices = readContentText(message?.content);
  if (fromChoices) {
    return fromChoices;
  }
  return readContentText(payload.choices?.[0]?.message?.content);
}

function isDashscopeErrorPayload(payload) {
  if (!payload || typeof payload !== "object") {
    return false;
  }
  const code = payload.code;
  return typeof code === "string" && code.length > 0 && code !== "Success";
}

async function postDashscopeJson({
  fetchImpl,
  baseUrl,
  apiKey,
  path,
  body,
  timeoutMs,
}) {
  const response = await fetchImpl(joinUrl(baseUrl, path), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeoutMs),
  });
  const raw = await response.text();
  let payload = null;
  try {
    payload = raw ? JSON.parse(raw) : null;
  } catch {
    payload = null;
  }
  return { ok: response.ok, status: response.status, payload };
}

module.exports = {
  joinUrl,
  parseDashscopeText,
  postDashscopeJson,
  isDashscopeErrorPayload,
};
