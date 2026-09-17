"use strict";

const path = require("node:path");

// qwen3-asr-flash 编码后上限约 10MB，Base64 膨胀约 4/3，所以原始文件要更小。
const MAX_AUDIO_BYTES = Math.floor((10 * 1024 * 1024 * 3) / 4);
const MAX_CLIENT_RECORDING_ID_LENGTH = 128;

const MIME_BY_EXT = {
  ".m4a": "audio/mp4",
  ".mp4": "audio/mp4",
  ".aac": "audio/aac",
  ".mp3": "audio/mpeg",
  ".wav": "audio/wav",
  ".flac": "audio/flac",
  ".ogg": "audio/ogg",
  ".webm": "audio/webm",
};

function extnameOf(fileName) {
  return path.extname(String(fileName || "")).toLowerCase();
}

function audioMime(fileName) {
  return MIME_BY_EXT[extnameOf(fileName)] || null;
}

function isAllowedAudioName(fileName) {
  return audioMime(fileName) !== null;
}

module.exports = {
  MAX_AUDIO_BYTES,
  MAX_CLIENT_RECORDING_ID_LENGTH,
  audioMime,
  extnameOf,
  isAllowedAudioName,
};
