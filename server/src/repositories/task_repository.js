"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { DatabaseSync } = require("node:sqlite");

const CREATE_SQL = `
CREATE TABLE IF NOT EXISTS transcription_tasks (
  id TEXT PRIMARY KEY,
  client_recording_id TEXT NOT NULL UNIQUE,
  provider_task_id TEXT,
  audio_location TEXT,
  status TEXT NOT NULL,
  stage TEXT,
  transcript TEXT,
  summary TEXT,
  error_code TEXT,
  error_message TEXT,
  failed_stage TEXT,
  retry_count INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
`;

class TaskRepository {
  constructor(dbPath) {
    if (dbPath !== ":memory:") {
      fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    }
    this.db = new DatabaseSync(dbPath);
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.db.exec(CREATE_SQL);
  }

  close() {
    this.db.close();
  }

  create(task) {
    this.db
      .prepare(
        `INSERT INTO transcription_tasks (
          id, client_recording_id, provider_task_id, audio_location,
          status, stage, transcript, summary, error_code, error_message,
          failed_stage, retry_count, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        task.id,
        task.clientRecordingId,
        task.providerTaskId ?? null,
        task.audioLocation ?? null,
        task.status,
        task.stage ?? null,
        task.transcript ?? null,
        task.summary ?? null,
        task.errorCode ?? null,
        task.errorMessage ?? null,
        task.failedStage ?? null,
        task.retryCount ?? 0,
        task.createdAt,
        task.updatedAt,
      );
    return this.findById(task.id);
  }

  findById(id) {
    return mapRow(
      this.db
        .prepare("SELECT * FROM transcription_tasks WHERE id = ?")
        .get(id),
    );
  }

  findByClientRecordingId(clientRecordingId) {
    return mapRow(
      this.db
        .prepare(
          "SELECT * FROM transcription_tasks WHERE client_recording_id = ?",
        )
        .get(clientRecordingId),
    );
  }

  update(id, fields) {
    const allowed = {
      providerTaskId: "provider_task_id",
      audioLocation: "audio_location",
      status: "status",
      stage: "stage",
      transcript: "transcript",
      summary: "summary",
      errorCode: "error_code",
      errorMessage: "error_message",
      failedStage: "failed_stage",
      retryCount: "retry_count",
      updatedAt: "updated_at",
    };
    const assignments = [];
    const values = [];
    for (const [key, column] of Object.entries(allowed)) {
      if (Object.prototype.hasOwnProperty.call(fields, key)) {
        assignments.push(`${column} = ?`);
        values.push(fields[key]);
      }
    }
    if (assignments.length === 0) {
      return this.findById(id);
    }
    values.push(id);
    this.db
      .prepare(
        `UPDATE transcription_tasks SET ${assignments.join(", ")} WHERE id = ?`,
      )
      .run(...values);
    return this.findById(id);
  }

  markInterrupted(now) {
    this.db
      .prepare(
        `UPDATE transcription_tasks
         SET status = 'failed',
             error_code = 'SERVER_INTERRUPTED',
             error_message = '服务重启，任务未完成，请重试。',
             failed_stage = CASE
               WHEN stage = 'summarizing' THEN 'summarizing'
               ELSE 'transcribing'
             END,
             updated_at = ?
         WHERE status IN ('queued', 'transcribing', 'summarizing')`,
      )
      .run(now);
  }
}

function mapRow(row) {
  if (!row) {
    return null;
  }
  return {
    id: row.id,
    clientRecordingId: row.client_recording_id,
    providerTaskId: row.provider_task_id,
    audioLocation: row.audio_location,
    status: row.status,
    stage: row.stage,
    transcript: row.transcript,
    summary: row.summary,
    errorCode: row.error_code,
    errorMessage: row.error_message,
    failedStage: row.failed_stage,
    retryCount: row.retry_count,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

module.exports = { TaskRepository };
