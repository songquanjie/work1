"use strict";

const { ProviderError } = require("../errors");
const { logWarn } = require("../log");

/** 转写完成后自动调 LLM 摘要。同一 taskId 同时只跑一条，防止 retry 叠加。 */
class TranscriptionPipeline {
  constructor({ repository, asrProvider, summaryProvider }) {
    this.repository = repository;
    this.asrProvider = asrProvider;
    this.summaryProvider = summaryProvider;
    this._inflight = new Map();
  }

  isBusy(taskId) {
    return this._inflight.has(taskId);
  }

  start(taskId) {
    const existing = this._inflight.get(taskId);
    if (existing) {
      return existing;
    }
    const running = this._process(taskId).finally(() => {
      if (this._inflight.get(taskId) === running) {
        this._inflight.delete(taskId);
      }
    });
    this._inflight.set(taskId, running);
    return running;
  }

  wait(taskId) {
    return this._inflight.get(taskId) || Promise.resolve();
  }

  waitAll() {
    return Promise.all([...this._inflight.values()]);
  }

  async _process(taskId) {
    const current = this.repository.findById(taskId);
    if (!current) {
      return;
    }
    if (current.status === "completed") {
      return;
    }

    // 摘要失败重试时跳过 ASR，避免重复转写。
    const skipAsr =
      current.failedStage === "summarizing" &&
      typeof current.transcript === "string" &&
      current.transcript.length > 0;

    let phase = skipAsr ? "summarizing" : "transcribing";
    try {
      let transcript = current.transcript;
      if (!skipAsr) {
        this.repository.update(taskId, {
          status: "transcribing",
          stage: "transcribing",
          transcript: null,
          summary: null,
          errorCode: null,
          errorMessage: null,
          failedStage: null,
          updatedAt: Date.now(),
        });
        const asrResult = await this.asrProvider.transcribe({
          audioPath: current.audioLocation,
        });
        transcript = asrResult.text;
        this.repository.update(taskId, {
          status: "summarizing",
          stage: "summarizing",
          transcript,
          updatedAt: Date.now(),
        });
      } else {
        this.repository.update(taskId, {
          status: "summarizing",
          stage: "summarizing",
          errorCode: null,
          errorMessage: null,
          failedStage: null,
          updatedAt: Date.now(),
        });
      }

      phase = "summarizing";
      const summaryResult = await this.summaryProvider.summarize({
        transcript,
      });
      this.repository.update(taskId, {
        status: "completed",
        stage: null,
        summary: summaryResult.text,
        errorCode: null,
        errorMessage: null,
        failedStage: null,
        updatedAt: Date.now(),
      });
    } catch (error) {
      const mapped = mapProviderError(error, phase);
      try {
        const latest = this.repository.findById(taskId);
        const keepTranscript = mapped.failedStage === "summarizing";
        this.repository.update(taskId, {
          status: "failed",
          stage: null,
          transcript: keepTranscript ? latest?.transcript ?? null : null,
          summary: keepTranscript ? latest?.summary ?? null : null,
          errorCode: mapped.code,
          errorMessage: mapped.message,
          failedStage: mapped.failedStage,
          updatedAt: Date.now(),
        });
      } catch (persistError) {
        logWarn("transcription-pipeline", persistError);
      }
    }
  }
}

function mapProviderError(error, phase) {
  if (error instanceof ProviderError) {
    const failedStage = error.code.startsWith("LLM_")
      ? "summarizing"
      : error.code.startsWith("ASR_")
        ? "transcribing"
        : phase;
    return {
      code: error.code,
      message: error.message,
      failedStage,
    };
  }
  return {
    code: phase === "summarizing" ? "LLM_FAILED" : "ASR_FAILED",
    message: phase === "summarizing" ? "摘要失败，请重试" : "转写失败，请重试",
    failedStage: phase,
  };
}

module.exports = { TranscriptionPipeline };
