"use strict";

const http = require("node:http");
const assert = require("node:assert/strict");
const { test } = require("node:test");
const { createApp } = require("../src/app");

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve(server.address().port));
  });
}

test("GET /health returns 200", async () => {
  const server = http.createServer(createApp());
  const port = await listen(server);
  try {
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.service, "echonote-server");
  } finally {
    server.close();
  }
});
