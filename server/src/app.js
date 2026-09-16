"use strict";

const express = require("express");
const cors = require("cors");

function createApp() {
  const app = express();
  app.use(cors());
  app.use(express.json());

  app.get("/health", (_req, res) => {
    res.status(200).json({ ok: true, service: "echonote-server" });
  });

  app.use((req, res) => {
    res.status(404).json({
      errorCode: "NOT_FOUND",
      message: `No route for ${req.method} ${req.path}`,
    });
  });

  return app;
}

module.exports = { createApp };
