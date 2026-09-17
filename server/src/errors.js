"use strict";

class HttpError extends Error {
  constructor(status, code, message) {
    super(message);
    this.name = "HttpError";
    this.status = status;
    this.code = code;
  }
}

class ProviderError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "ProviderError";
    this.code = code;
  }
}

module.exports = { HttpError, ProviderError };
