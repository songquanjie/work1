"use strict";

const path = require("node:path");
const express = require("express");
const cors = require("cors");

const { HttpError } = require("./errors");
const { isFileTooLarge, logWarn } = require("./log");
const { TaskRepository } = require("./repositories/task_repository");
const { createAsrProvider } = require("./providers/asr_provider");
const { createSummaryProvider } = require("./providers/summary_provider");
const { TranscriptionPipeline } = require("./services/transcription_pipeline");
const { createTranscriptionRouter } = require("./routes/transcriptions");

/** 供应商只从环境变量读。none 时任务失败并给出可读原因，绝不编造全文。 */
function providersFromEnv(env = process.env) {
  return {
    asrProvider: createAsrProvider({
      name: env.ASR_PROVIDER,
      apiKey: env.DASHSCOPE_API_KEY,
      baseUrl: env.DASHSCOPE_BASE_URL,
      model: env.DASHSCOPE_ASR_MODEL,
    }),
    summaryProvider: createSummaryProvider({
      name: env.LLM_PROVIDER,
      apiKey: env.DASHSCOPE_API_KEY,
      baseUrl: env.DASHSCOPE_BASE_URL,
      model: env.DASHSCOPE_LLM_MODEL,
    }),
  };
}

/** 组装 Express 应用。测试可注入 repository / provider，避免打真实百炼。 */
function createApp(options = {}) {
  const dataDir = options.dataDir || path.join(__dirname, "..", "data");
  const dbPath = options.dbPath || path.join(dataDir, "echonote.sqlite");
  const audioDir = options.audioDir || path.join(dataDir, "audio");
  const tmpDir = options.tmpDir || path.join(dataDir, "tmp");
  const envProviders = providersFromEnv(options.env || process.env);

  const repository = options.repository || new TaskRepository(dbPath);
  const asrProvider = options.asrProvider || envProviders.asrProvider;
  const summaryProvider =
    options.summaryProvider || envProviders.summaryProvider;
  const pipeline =
    options.pipeline ||
    new TranscriptionPipeline({
      repository,
      asrProvider,
      summaryProvider,
    });

  // 进程内执行器重启后，内存里的进行中任务已经没了，落库改成可重试失败。
  if (options.markInterrupted !== false) {
    repository.markInterrupted(Date.now());
  }

  const app = express();
  app.use(cors());
  app.use(express.json());

  app.locals.repository = repository;
  app.locals.pipeline = pipeline;

  app.get("/health", (_req, res) => {
    res.status(200).json({ ok: true, service: "echonote-server" });
  });

  app.use(
    "/api/transcriptions",
    createTranscriptionRouter({
      repository,
      pipeline,
      audioDir,
      tmpDir,
    }),
  );

  app.use((req, res) => {
    res.status(404).json({
      errorCode: "NOT_FOUND",
      message: `No route for ${req.method} ${req.path}`,
    });
  });

  app.use((err, _req, res, next) => {
    if (res.headersSent) {
      next(err);
      return;
    }
    if (err instanceof HttpError) {
      res.status(err.status).json({
        errorCode: err.code,
        message: err.message,
      });
      return;
    }
    if (isFileTooLarge(err)) {
      res.status(400).json({
        errorCode: "FILE_TOO_LARGE",
        message: "音频过大，请改用较短录音。",
      });
      return;
    }
    if (err && err.name === "MulterError") {
      res.status(400).json({
        errorCode: "INVALID_REQUEST",
        message: "上传内容无效。",
      });
      return;
    }
    logWarn("http", err);
    res.status(500).json({
      errorCode: "INTERNAL_ERROR",
      message: "服务暂时不可用，请稍后重试。",
    });
  });

  return app;
}

module.exports = { createApp };
