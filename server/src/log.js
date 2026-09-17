"use strict";

function logWarn(scope, error) {
  const name = error && error.name ? error.name : "Error";
  const code = error && error.code ? String(error.code) : "";
  process.stderr.write(`${scope}: ${name}${code ? ` ${code}` : ""}\n`);
}

function isFileTooLarge(err) {
  if (!err) {
    return false;
  }
  const code = String(err.code || "").toUpperCase();
  return code === "LIMIT_FILE_SIZE" || code.includes("FILE_SIZE");
}

module.exports = { isFileTooLarge, logWarn };
