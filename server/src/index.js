"use strict";

const path = require("node:path");
require("dotenv").config({ path: path.join(__dirname, "..", ".env") });

const { createApp } = require("./app");

const port = Number(process.env.PORT || 3000);
if (!Number.isInteger(port) || port <= 0) {
  throw new Error(`Invalid PORT: ${process.env.PORT}`);
}

// 绑 0.0.0.0，同一局域网的手机才能访问，不只是本机 127.0.0.1。
const app = createApp();
app.listen(port, "0.0.0.0", () => {
  process.stdout.write(`EchoNote server listening on 0.0.0.0:${port}\n`);
});
