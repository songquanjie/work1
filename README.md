# EchoNote（随身录音笔记）

Android 端录音笔记客户端（Flutter）和配套的 Node.js 接口。

当前版本支持本地录音、列表、试听和删除。上传、转写和摘要会在后续提交中加入。本阶段不调用后端。

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

本阶段不需要 `--dart-define=API_BASE_URL`。Debug 包仍允许明文 HTTP，供后续上传使用。

## 后端

本阶段可以不启动。接口仍只有健康检查：

```bash
cd server
copy .env.example .env
npm install
npm start
npm test
```

默认监听 `3000` 端口（可用 `PORT` 覆盖）。`GET /health` 应返回：

```json
{"ok":true,"service":"echonote-server"}
```

进程绑定 `0.0.0.0`，同一局域网内的手机才能访问。

### 环境变量

| 名称 | 作用 |
| --- | --- |
| `PORT` | 监听端口 |
| `ASR_PROVIDER` | 语音转写供应商；接入转写前不会使用 |
| `LLM_PROVIDER` | 摘要供应商；接入摘要前不会使用 |

## 密钥与签名

不要提交 `server/.env`、`android/key.properties` 和 keystore 文件。
