"use strict";

const fs = require("node:fs/promises");

const { ProviderError } = require("../errors");
const { audioMime } = require("../audio_format");
const {
  isDashscopeErrorPayload,
  parseDashscopeText,
  postDashscopeJson,
} = require("./dashscope_http");

const NOT_CONFIGURED = new ProviderError(
  "ASR_NOT_CONFIGURED",
  "未配置转写服务",
);

/** 百炼同步 ASR：把本地音频编成 Base64 Data URL，不走 OSS / Filetrans。 */
function createAsrProvider(options = {}) {
  const name = String(options.name || "none").toLowerCase();
  const apiKey = String(options.apiKey || "").trim();
  const baseUrl = String(
    options.baseUrl || "https://dashscope.aliyuncs.com/api/v1",
  ).trim();
  const model = String(options.model || "qwen3-asr-flash").trim();
  const fetchImpl = options.fetchImpl || fetch;
  const timeoutMs = options.timeoutMs || 180_000;

  return {
    name,
    async transcribe({ audioPath }) {
      if (name !== "dashscope") {
        throw NOT_CONFIGURED;
      }
      if (!apiKey) {
        throw NOT_CONFIGURED;
      }

      const bytes = await fs.readFile(audioPath);
      const mime = audioMime(audioPath) || "audio/mp4";
      // 官方同步接口三种输入里，内网文件只能用 Base64 Data URL。
      const dataUri = `data:${mime};base64,${bytes.toString("base64")}`;
      let result;
      try {
        result = await postDashscopeJson({
          fetchImpl,
          baseUrl,
          apiKey,
          path: "/services/aigc/multimodal-generation/generation",
          timeoutMs,
          body: {
            model,
            input: {
              messages: [
                {
                  role: "user",
                  content: [{ audio: dataUri }],
                },
              ],
            },
            parameters: {
              asr_options: {
                enable_itn: false,
              },
            },
          },
        });
      } catch {
        throw new ProviderError("ASR_FAILED", "转写服务暂时不可用");
      }

      if (!result.ok || isDashscopeErrorPayload(result.payload)) {
        if (result.status === 401 || result.status === 403) {
          throw NOT_CONFIGURED;
        }
        if (result.status === 429) {
          throw new ProviderError("ASR_FAILED", "转写服务繁忙，请稍后重试");
        }
        throw new ProviderError("ASR_FAILED", "转写失败，请重试");
      }

      const text = parseDashscopeText(result.payload);
      if (!text) {
        throw new ProviderError("ASR_FAILED", "转写结果为空，请重试");
      }
      return { text };
    },
  };
}

module.exports = { createAsrProvider };
