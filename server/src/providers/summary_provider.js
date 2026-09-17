"use strict";

const { ProviderError } = require("../errors");
const {
  isDashscopeErrorPayload,
  parseDashscopeText,
  postDashscopeJson,
} = require("./dashscope_http");

const NOT_CONFIGURED = new ProviderError(
  "LLM_NOT_CONFIGURED",
  "未配置摘要服务",
);

/** 转写成功后自动调用。模型默认 qwen-plus，走文本生成而不是多模态接口。 */
function createSummaryProvider(options = {}) {
  const name = String(options.name || "none").toLowerCase();
  const apiKey = String(options.apiKey || "").trim();
  const baseUrl = String(
    options.baseUrl || "https://dashscope.aliyuncs.com/api/v1",
  ).trim();
  const model = String(options.model || "qwen-plus").trim();
  const fetchImpl = options.fetchImpl || fetch;
  const timeoutMs = options.timeoutMs || 60_000;

  return {
    name,
    async summarize({ transcript }) {
      if (name !== "dashscope") {
        throw NOT_CONFIGURED;
      }
      if (!apiKey) {
        throw NOT_CONFIGURED;
      }

      let result;
      try {
        result = await postDashscopeJson({
          fetchImpl,
          baseUrl,
          apiKey,
          path: "/services/aigc/text-generation/generation",
          timeoutMs,
          body: {
            model,
            input: {
              messages: [
                {
                  role: "system",
                  content:
                    "你是录音笔记助手。根据用户提供的转写全文，写一段不超过120字的中文摘要。只输出摘要正文。",
                },
                {
                  role: "user",
                  content: transcript,
                },
              ],
            },
            parameters: {
              result_format: "message",
            },
          },
        });
      } catch {
        throw new ProviderError("LLM_FAILED", "摘要服务暂时不可用");
      }

      if (!result.ok || isDashscopeErrorPayload(result.payload)) {
        if (result.status === 401 || result.status === 403) {
          throw NOT_CONFIGURED;
        }
        if (result.status === 429) {
          throw new ProviderError("LLM_FAILED", "摘要服务繁忙，请稍后重试");
        }
        throw new ProviderError("LLM_FAILED", "摘要失败，请重试");
      }

      const text = parseDashscopeText(result.payload);
      if (!text) {
        throw new ProviderError("LLM_FAILED", "摘要结果为空，请重试");
      }
      return { text };
    },
  };
}

module.exports = { createSummaryProvider };
