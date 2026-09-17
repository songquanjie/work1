"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { test } = require("node:test");
const { createAsrProvider } = require("../src/providers/asr_provider");
const { parseDashscopeText } = require("../src/providers/dashscope_http");

test("dashscope asr posts Base64 audio and reads output text", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "echonote-asr-"));
  const audioPath = path.join(dir, "clip.m4a");
  fs.writeFileSync(audioPath, Buffer.from("abc"));
  const calls = [];
  const provider = createAsrProvider({
    name: "dashscope",
    apiKey: "sk-test",
    baseUrl: "https://dashscope.aliyuncs.com/api/v1",
    fetchImpl: async (url, init) => {
      calls.push({ url, init });
      return {
        ok: true,
        status: 200,
        text: async () =>
          JSON.stringify({
            output: {
              choices: [
                {
                  message: {
                    content: [{ text: "欢迎使用阿里云。" }],
                  },
                },
              ],
            },
          }),
      };
    },
  });

  const result = await provider.transcribe({ audioPath });
  assert.equal(result.text, "欢迎使用阿里云。");
  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
  );
  assert.equal(calls[0].init.headers.Authorization, "Bearer sk-test");
  const body = JSON.parse(calls[0].init.body);
  assert.equal(body.model, "qwen3-asr-flash");
  assert.equal(body.parameters.asr_options.enable_itn, false);
  assert.match(body.input.messages[0].content[0].audio, /^data:audio\/mp4;base64,/);
});

test("dashscope asr without key is treated as not configured", async () => {
  const provider = createAsrProvider({ name: "dashscope", apiKey: "  " });
  await assert.rejects(
    () => provider.transcribe({ audioPath: "missing.m4a" }),
    (error) =>
      error.code === "ASR_NOT_CONFIGURED" &&
      error.message === "未配置转写服务",
  );
});

test("none asr does not invent transcript text", async () => {
  const provider = createAsrProvider({ name: "none" });
  await assert.rejects(
    () => provider.transcribe({ audioPath: "clip.m4a" }),
    (error) => error.code === "ASR_NOT_CONFIGURED",
  );
});

test("parseDashscopeText accepts output.text and choices content", () => {
  assert.equal(parseDashscopeText({ output: { text: "全文" } }), "全文");
  assert.equal(
    parseDashscopeText({
      output: { choices: [{ message: { content: [{ text: "段落" }] } }] },
    }),
    "段落",
  );
});

test("dashscope HTTP 200 with business error is not treated as transcript", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "echonote-asr-"));
  const audioPath = path.join(dir, "clip.m4a");
  fs.writeFileSync(audioPath, Buffer.from("abc"));
  const provider = createAsrProvider({
    name: "dashscope",
    apiKey: "sk-test",
    fetchImpl: async () => ({
      ok: true,
      status: 200,
      text: async () =>
        JSON.stringify({
          code: "InvalidParameter",
          message: "vendor-secret-detail",
        }),
    }),
  });

  await assert.rejects(
    () => provider.transcribe({ audioPath }),
    (error) =>
      error.code === "ASR_FAILED" &&
      error.message === "转写失败，请重试" &&
      !String(error.message).includes("vendor-secret"),
  );
});
