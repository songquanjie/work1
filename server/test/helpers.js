"use strict";

const fs = require("node:fs");
const http = require("node:http");
const os = require("node:os");
const path = require("node:path");

function tempDataDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "echonote-server-"));
}

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve(server.address().port));
  });
}

async function withServer(app, fn) {
  const server = http.createServer(app);
  const port = await listen(server);
  const base = `http://127.0.0.1:${port}`;
  try {
    return await fn(base);
  } finally {
    await app.locals.pipeline.waitAll();
    server.close();
    app.locals.repository.close();
  }
}

function audioForm(clientRecordingId, bytes = Buffer.from("fake-m4a"), fileName = "clip.m4a") {
  const form = new FormData();
  form.append("clientRecordingId", clientRecordingId);
  form.append("audio", new Blob([bytes]), fileName);
  return form;
}

module.exports = { audioForm, tempDataDir, withServer };
