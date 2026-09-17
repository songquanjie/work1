"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const { test } = require("node:test");
const { createApp } = require("../src/app");
const { ProviderError } = require("../src/errors");
const { MAX_AUDIO_BYTES } = require("../src/audio_format");
const { TaskRepository } = require("../src/repositories/task_repository");
const { audioForm, tempDataDir, withServer } = require("./helpers");

function deferred() {
  let resolve;
  const promise = new Promise((done) => {
    resolve = done;
  });
  return { promise, resolve };
}

test("POST is idempotent for the same clientRecordingId", async () => {
  const asrCalls = [];
  const app = createApp({
    dataDir: tempDataDir(),
    markInterrupted: false,
    asrProvider: {
      transcribe: async () => {
        asrCalls.push(1);
        return { text: "全文" };
      },
    },
    summaryProvider: {
      summarize: async () => ({ text: "摘要" }),
    },
  });

  await withServer(app, async (base) => {
    const first = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: audioForm("rec-1"),
    });
    const second = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: audioForm("rec-1"),
    });
    assert.equal(first.status, 200);
    assert.equal(second.status, 200);
    const a = await first.json();
    const b = await second.json();
    assert.equal(a.id, b.id);
    await app.locals.pipeline.wait(a.id);
    const done = await (await fetch(`${base}/api/transcriptions/${a.id}`)).json();
    assert.equal(done.status, "completed");
    assert.equal(done.transcript, "全文");
    assert.equal(done.summary, "摘要");
    assert.equal(asrCalls.length, 1);
  });
});

test("GET does not start transcription", async () => {
  const gate = deferred();
  let transcribeCount = 0;
  const app = createApp({
    dataDir: tempDataDir(),
    markInterrupted: false,
    asrProvider: {
      transcribe: async () => {
        transcribeCount += 1;
        await gate.promise;
        return { text: "全文" };
      },
    },
    summaryProvider: {
      summarize: async () => ({ text: "摘要" }),
    },
  });

  await withServer(app, async (base) => {
    const created = await (
      await fetch(`${base}/api/transcriptions`, {
        method: "POST",
        body: audioForm("rec-get"),
      })
    ).json();
    const before = transcribeCount;
    const firstGet = await fetch(`${base}/api/transcriptions/${created.id}`);
    const secondGet = await fetch(`${base}/api/transcriptions/${created.id}`);
    assert.equal(firstGet.status, 200);
    assert.equal(secondGet.status, 200);
    assert.equal(transcribeCount, before);
    const retryWhileBusy = await fetch(
      `${base}/api/transcriptions/${created.id}/retry`,
      { method: "POST" },
    );
    assert.equal(retryWhileBusy.status, 409);
    const busy = await retryWhileBusy.json();
    assert.equal(busy.errorCode, "TASK_IN_PROGRESS");
    gate.resolve();
    await app.locals.pipeline.wait(created.id);
  });
});

test("POST same clientRecordingId restarts a failed task", async () => {
  let asrCalls = 0;
  const app = createApp({
    dataDir: tempDataDir(),
    markInterrupted: false,
    asrProvider: {
      transcribe: async () => {
        asrCalls += 1;
        if (asrCalls === 1) {
          throw new ProviderError("ASR_FAILED", "转写失败，请重试");
        }
        return { text: "全文" };
      },
    },
    summaryProvider: {
      summarize: async () => ({ text: "摘要" }),
    },
  });

  await withServer(app, async (base) => {
    const first = await (
      await fetch(`${base}/api/transcriptions`, {
        method: "POST",
        body: audioForm("rec-restart"),
      })
    ).json();
    await app.locals.pipeline.wait(first.id);
    const failed = await (
      await fetch(`${base}/api/transcriptions/${first.id}`)
    ).json();
    assert.equal(failed.status, "failed");

    const second = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: audioForm("rec-restart"),
    });
    assert.equal(second.status, 200);
    const revived = await second.json();
    assert.equal(revived.id, first.id);
    assert.equal(revived.status, "queued");
    await app.locals.pipeline.wait(first.id);
    const done = await (
      await fetch(`${base}/api/transcriptions/${first.id}`)
    ).json();
    assert.equal(done.status, "completed");
    assert.equal(done.transcript, "全文");
    assert.equal(done.summary, "摘要");
    assert.equal(asrCalls, 2);
  });
});

test("none provider fails without fake transcript and can retry", async () => {
  const app = createApp({
    dataDir: tempDataDir(),
    env: { ASR_PROVIDER: "none", LLM_PROVIDER: "none" },
    markInterrupted: false,
  });

  await withServer(app, async (base) => {
    const created = await (
      await fetch(`${base}/api/transcriptions`, {
        method: "POST",
        body: audioForm("rec-none"),
      })
    ).json();
    await app.locals.pipeline.wait(created.id);
    const failed = await (
      await fetch(`${base}/api/transcriptions/${created.id}`)
    ).json();
    assert.equal(failed.status, "failed");
    assert.equal(failed.errorCode, "ASR_NOT_CONFIGURED");
    assert.equal(failed.message, "未配置转写服务");
    assert.equal(failed.transcript, null);

    const retried = await fetch(
      `${base}/api/transcriptions/${created.id}/retry`,
      { method: "POST" },
    );
    assert.equal(retried.status, 200);
    await app.locals.pipeline.wait(created.id);
    const failedAgain = await (
      await fetch(`${base}/api/transcriptions/${created.id}`)
    ).json();
    assert.equal(failedAgain.status, "failed");
    assert.equal(failedAgain.errorCode, "ASR_NOT_CONFIGURED");
    assert.equal(app.locals.repository.findById(created.id).retryCount, 1);
  });
});

test("summary failure keeps transcript and retry skips ASR", async () => {
  let transcribeCount = 0;
  let summarizeCount = 0;
  const app = createApp({
    dataDir: tempDataDir(),
    markInterrupted: false,
    asrProvider: {
      transcribe: async () => {
        transcribeCount += 1;
        return { text: "保留这篇全文" };
      },
    },
    summaryProvider: {
      summarize: async () => {
        summarizeCount += 1;
        throw new ProviderError("LLM_NOT_CONFIGURED", "未配置摘要服务");
      },
    },
  });

  await withServer(app, async (base) => {
    const created = await (
      await fetch(`${base}/api/transcriptions`, {
        method: "POST",
        body: audioForm("rec-summary"),
      })
    ).json();
    await app.locals.pipeline.wait(created.id);
    const failed = await (
      await fetch(`${base}/api/transcriptions/${created.id}`)
    ).json();
    assert.equal(failed.status, "failed");
    assert.equal(failed.transcript, "保留这篇全文");
    assert.equal(failed.errorCode, "LLM_NOT_CONFIGURED");
    assert.equal(transcribeCount, 1);

    await fetch(`${base}/api/transcriptions/${created.id}/retry`, {
      method: "POST",
    });
    await app.locals.pipeline.wait(created.id);
    assert.equal(transcribeCount, 1);
    assert.equal(summarizeCount, 2);
    const again = await (
      await fetch(`${base}/api/transcriptions/${created.id}`)
    ).json();
    assert.equal(again.transcript, "保留这篇全文");
  });
});

test("missing fields and unknown task return 4xx", async () => {
  const app = createApp({
    dataDir: tempDataDir(),
    markInterrupted: false,
    asrProvider: { transcribe: async () => ({ text: "x" }) },
    summaryProvider: { summarize: async () => ({ text: "y" }) },
  });

  await withServer(app, async (base) => {
    const missingAudio = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: audioForm("rec-x"),
    });
    assert.equal(missingAudio.status, 200);

    const empty = new FormData();
    empty.append("audio", new Blob([Buffer.from("x")]), "clip.m4a");
    const missingId = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: empty,
    });
    assert.equal(missingId.status, 400);

    const missing = await fetch(`${base}/api/transcriptions/does-not-exist`);
    assert.equal(missing.status, 404);
    const body = await missing.json();
    assert.equal(body.errorCode, "TASK_NOT_FOUND");

    const badName = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: audioForm("rec-txt", Buffer.from("not-audio"), "notes.txt"),
    });
    assert.equal(badName.status, 400);
    assert.equal((await badName.json()).errorCode, "UNSUPPORTED_AUDIO");

    const tooLongId = "r".repeat(129);
    const longId = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: audioForm(tooLongId),
    });
    assert.equal(longId.status, 400);
    assert.equal((await longId.json()).errorCode, "INVALID_REQUEST");
  });
});

test("oversized audio is rejected", async () => {
  const app = createApp({
    dataDir: tempDataDir(),
    markInterrupted: false,
    asrProvider: { transcribe: async () => ({ text: "x" }) },
    summaryProvider: { summarize: async () => ({ text: "y" }) },
  });

  await withServer(app, async (base) => {
    const res = await fetch(`${base}/api/transcriptions`, {
      method: "POST",
      body: audioForm("rec-huge", Buffer.alloc(MAX_AUDIO_BYTES + 1)),
    });
    assert.equal(res.status, 400);
    assert.equal((await res.json()).errorCode, "FILE_TOO_LARGE");
  });
});

test("startup marks in-flight tasks as retryable failures", () => {
  const dataDir = tempDataDir();
  const dbPath = path.join(dataDir, "echonote.sqlite");
  const repo = new TaskRepository(dbPath);
  const now = Date.now();
  repo.create({
    id: "task-stuck",
    clientRecordingId: "rec-stuck",
    audioLocation: `${dataDir}/audio/task-stuck.m4a`,
    status: "transcribing",
    stage: "transcribing",
    createdAt: now,
    updatedAt: now,
  });
  repo.close();

  const app = createApp({
    dataDir,
    dbPath,
    markInterrupted: true,
    asrProvider: { transcribe: async () => ({ text: "x" }) },
    summaryProvider: { summarize: async () => ({ text: "y" }) },
  });
  try {
    const task = app.locals.repository.findById("task-stuck");
    assert.equal(task.status, "failed");
    assert.equal(task.errorCode, "SERVER_INTERRUPTED");
    assert.equal(task.failedStage, "transcribing");
  } finally {
    app.locals.repository.close();
  }
});
