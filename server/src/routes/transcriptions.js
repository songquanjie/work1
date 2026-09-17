"use strict";

const fs = require("node:fs");
const fsp = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const express = require("express");
const multer = require("multer");

const { HttpError } = require("../errors");
const {
  MAX_AUDIO_BYTES,
  MAX_CLIENT_RECORDING_ID_LENGTH,
  extnameOf,
  isAllowedAudioName,
} = require("../audio_format");

function toPublicTask(task) {
  const terminal = task.status === "completed" || task.status === "failed";
  return {
    id: task.id,
    status: task.status,
    stage: terminal ? null : task.stage || "transcribing",
    transcript: task.transcript,
    summary: task.summary,
    errorCode: task.errorCode,
    message: task.errorMessage,
    updatedAt: new Date(task.updatedAt).toISOString(),
  };
}

function asyncHandler(handler) {
  return (req, res, next) => {
    Promise.resolve(handler(req, res, next)).catch(next);
  };
}

function moveUploadedFile(src, dest) {
  try {
    fs.renameSync(src, dest);
  } catch (error) {
    if (error && error.code === "EXDEV") {
      fs.copyFileSync(src, dest);
      fs.unlinkSync(src);
      return;
    }
    throw error;
  }
}

function safeUnlink(filePath) {
  if (!filePath) {
    return;
  }
  try {
    fs.unlinkSync(filePath);
  } catch {
    // Temp files are best-effort; leftover names are unique.
  }
}

function createTranscriptionRouter({
  repository,
  pipeline,
  audioDir,
  tmpDir,
}) {
  fs.mkdirSync(audioDir, { recursive: true });
  fs.mkdirSync(tmpDir, { recursive: true });

  const upload = multer({
    storage: multer.diskStorage({
      destination: (_req, _file, cb) => cb(null, tmpDir),
      filename: (_req, file, cb) => {
        const ext = extnameOf(file.originalname);
        cb(null, `${Date.now()}_${crypto.randomUUID()}${ext}`);
      },
    }),
    fileFilter: (_req, file, cb) => {
      if (!isAllowedAudioName(file.originalname)) {
        cb(new HttpError(400, "UNSUPPORTED_AUDIO", "不支持的音频格式"));
        return;
      }
      cb(null, true);
    },
    limits: { fileSize: MAX_AUDIO_BYTES, files: 1 },
  });

  const router = express.Router();

  router.post(
    "/",
    upload.single("audio"),
    asyncHandler(async (req, res) => {
      const clientRecordingId = String(req.body?.clientRecordingId || "").trim();
      const uploaded = req.file;
      try {
        if (!clientRecordingId) {
          throw new HttpError(
            400,
            "INVALID_REQUEST",
            "缺少 clientRecordingId",
          );
        }
        if (clientRecordingId.length > MAX_CLIENT_RECORDING_ID_LENGTH) {
          throw new HttpError(400, "INVALID_REQUEST", "clientRecordingId 无效");
        }
        if (!uploaded) {
          throw new HttpError(400, "INVALID_REQUEST", "缺少音频文件");
        }
        if (!uploaded.size) {
          throw new HttpError(400, "INVALID_REQUEST", "音频文件为空");
        }
        if (!isAllowedAudioName(uploaded.originalname)) {
          throw new HttpError(
            400,
            "UNSUPPORTED_AUDIO",
            "不支持的音频格式",
          );
        }

        const existing = repository.findByClientRecordingId(clientRecordingId);
        if (existing) {
          return res.status(200).json(toPublicTask(existing));
        }

        const id = crypto.randomUUID();
        const ext = extnameOf(uploaded.originalname) || extnameOf(uploaded.path) || ".m4a";
        const audioLocation = path.join(audioDir, `${id}${ext}`);
        moveUploadedFile(uploaded.path, audioLocation);
        uploaded.path = null;

        const now = Date.now();
        let task;
        try {
          task = repository.create({
            id,
            clientRecordingId,
            audioLocation,
            status: "queued",
            stage: "transcribing",
            createdAt: now,
            updatedAt: now,
          });
        } catch (error) {
          safeUnlink(audioLocation);
          const raced = repository.findByClientRecordingId(clientRecordingId);
          if (raced) {
            return res.status(200).json(toPublicTask(raced));
          }
          throw error;
        }

        pipeline.start(task.id);
        return res.status(200).json(toPublicTask(task));
      } finally {
        if (uploaded?.path) {
          safeUnlink(uploaded.path);
        }
      }
    }),
  );

  router.get(
    "/:id",
    asyncHandler(async (req, res) => {
      const task = repository.findById(req.params.id);
      if (!task) {
        throw new HttpError(404, "TASK_NOT_FOUND", "任务不存在");
      }
      return res.status(200).json(toPublicTask(task));
    }),
  );

  router.post(
    "/:id/retry",
    asyncHandler(async (req, res) => {
      const task = repository.findById(req.params.id);
      if (!task) {
        throw new HttpError(404, "TASK_NOT_FOUND", "任务不存在");
      }
      if (
        pipeline.isBusy(task.id) ||
        task.status === "queued" ||
        task.status === "transcribing" ||
        task.status === "summarizing"
      ) {
        throw new HttpError(
          409,
          "TASK_IN_PROGRESS",
          "任务正在处理中，请稍后再试",
        );
      }
      if (task.status !== "failed") {
        throw new HttpError(409, "TASK_NOT_FAILED", "只有失败任务可以重试");
      }
      if (!task.audioLocation) {
        throw new HttpError(400, "INVALID_REQUEST", "找不到原始音频，无法重试");
      }
      try {
        await fsp.access(task.audioLocation);
      } catch {
        throw new HttpError(400, "INVALID_REQUEST", "找不到原始音频，无法重试");
      }

      const updated = repository.update(task.id, {
        status: "queued",
        stage:
          task.failedStage === "summarizing"
            ? "summarizing"
            : "transcribing",
        errorCode: null,
        errorMessage: null,
        retryCount: (task.retryCount || 0) + 1,
        updatedAt: Date.now(),
        failedStage: task.failedStage,
      });
      pipeline.start(updated.id);
      return res.status(200).json(toPublicTask(updated));
    }),
  );

  return router;
}

module.exports = { createTranscriptionRouter, toPublicTask };
