# EchoNote（随身录音笔记）

Android 端录音笔记客户端（Flutter）和配套的 Node.js 接口。

当前版本：App 支持本地录音、列表、试听和删除。后端已提供上传转写任务接口；App 尚未接入上传、轮询和详情（下一阶段）。

## 目录

```text
lib/                 Flutter 客户端
server/src/          Express 接口
```

界面层不要直接访问 SQLite、本地文件或 HTTP。录音文件由 `RecordingFileStore` 落盘，元数据由 `RecordingRepository` 写入 SQLite，所以杀进程后列表还在。API 密钥只放在 `server/.env`，不要打进 APK。

## 客户端

```bash
flutter pub get
flutter test
flutter run
```

真机需要麦克风权限。首页是录音列表，右下角「新建录音」。

操作：开始 / 暂停 / 继续 / 停止。暂停时计时停止。停止后回到列表，可播放或删除。扩展名以真机实际产出为准，不要假设一定是 `.m4a`。

App 进入后台时会自动停止并尝试保存，不支持后台持续录音。

连点开始不会开出两段录音：异步操作完成前按钮不可用，而不是靠短时间防抖。

本阶段 App 不需要 `--dart-define=API_BASE_URL`。Debug 包仍允许明文 HTTP，供后续上传使用。

## 后端

```bash
cd server
copy .env.example .env
npm install
npm start
npm test
```

默认监听 `3000` 端口（可用 `PORT` 覆盖）。进程绑定 `0.0.0.0`，同一局域网内的手机才能访问。不要对同一份 `server/data/echonote.sqlite` 同时启动两个进程。

`GET /health` 应返回：

```json
{"ok":true,"service":"echonote-server"}
```

转写任务：

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `POST` | `/api/transcriptions` | `clientRecordingId` + 音频文件；同一 id 返回已有任务 |
| `GET` | `/api/transcriptions/:id` | 只读查询，不会触发转写 |
| `POST` | `/api/transcriptions/:id/retry` | 只重跑失败阶段 |

上传为 multipart，音频按原始文件落盘。后端调用百炼时再编成 Base64。同步模型 `qwen3-asr-flash` 约 5 分钟 / 编码后 10MB；任务音频文件暂不自动清理。

`ASR_PROVIDER=none`（默认）时任务失败并返回「未配置转写服务」，不会编造全文。真转写把 `server/.env` 里的 `ASR_PROVIDER` / `LLM_PROVIDER` 改为 `dashscope`。

### 环境变量

| 名称 | 作用 |
| --- | --- |
| `PORT` | 监听端口 |
| `ASR_PROVIDER` | `none` 或 `dashscope` |
| `LLM_PROVIDER` | `none` 或 `dashscope` |
| `DASHSCOPE_API_KEY` | 百炼北京地域 Key，不要提交 |
| `DASHSCOPE_BASE_URL` | 默认 `https://dashscope.aliyuncs.com/api/v1` |
| `DASHSCOPE_ASR_MODEL` | 默认 `qwen3-asr-flash` |
| `DASHSCOPE_LLM_MODEL` | 默认 `qwen-plus` |

## 密钥与签名

不要提交 `server/.env`、`android/key.properties` 和 keystore 文件。
