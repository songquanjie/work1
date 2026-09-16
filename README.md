# EchoNote（随身录音笔记）

Android 端录音笔记客户端（Flutter）和配套的 Node.js 接口。

当前仓库是空客户端骨架：编译期注入 API 地址，后端只提供健康检查。录音、转写和摘要会在后续提交中加入。

## 目录

```text
lib/                 Flutter 客户端
server/src/          Express 接口
```

界面层不要直接访问 SQLite、本地文件或 HTTP；这些能力落地后必须走独立分层。API 密钥只放在 `server/.env`，不要打进 APK。

## 后端

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

## 客户端

```bash
flutter pub get
flutter test
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:3000
```

`10.0.2.2` 是 Android 模拟器访问宿主机的地址。真机必须使用电脑的局域网 IP，或已部署的 HTTPS 地址。Debug 包允许明文 HTTP；Release 应使用 HTTPS。

## 密钥与签名

不要提交 `server/.env`、`android/key.properties` 和 keystore 文件。
