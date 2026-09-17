# EchoNote（随身录音笔记）

Android 录音笔记：本地录音、列表试听，上传到自建后端后完成语音转写和智能摘要。

当前 App 版本 **1.5.2+7**。API 密钥只放在服务端 `server/.env`，不会打进 APK。

## 功能

- 录音：开始 / 暂停 / 继续 / 停止；实时时长和音量
- 列表：名称、时长、创建时间、处理状态；本地播放、删除
- 上传转写：待上传 → 上传中 → 转写处理中 / 生成摘要中 → 已完成或失败
- 详情：转写全文、智能摘要、分别复制；失败可重试
- 杀进程后列表、全文和摘要仍在；未完成任务回到前台会继续查询

不包含登录、多端同步、iOS、后台持续录音、BLE、边录边转。

## 技术栈

| 端 | 技术 |
| --- | --- |
| 客户端 | Flutter 3.x / Dart 3.x，Android |
| 录音 / 播放 | `record`、`just_audio` |
| 本地数据 | `sqflite` + 应用文档目录中的音频文件 |
| 网络 | `http`（multipart 上传） |
| 后端 | Node.js ≥ 22，Express，SQLite |
| 转写 | 阿里云百炼 `qwen3-asr-flash`（同步 HTTP + Base64） |
| 摘要 | 阿里云百炼 `qwen-plus`（文本生成 HTTP） |

本仓库开发环境示例（Windows）：Flutter 在 `E:\dev\flutter`，Node 在 `E:\dev\nodejs`，JDK 17、Android SDK 在 `E:\dev`。换机器时把下面命令里的路径改成你本机的即可。

## 目录结构

```text
EchoNote/
├── lib/                      Flutter 客户端
│   ├── features/             录音页、列表、详情
│   ├── repositories/         协调文件、数据库、HTTP
│   ├── data/                 SQLite、转写 API
│   └── services/             录音、播放、轮询
├── server/                   Node 后端
│   ├── src/                  路由、任务管线、百炼调用
│   ├── .env.example          环境变量模板
│   └── .env                  真实密钥
├── android/                  Android 工程
└── README.md
```

页面不直接访问 SQLite、本地文件或 HTTP，一律走 `RecordingRepository`。

## 环境要求

- Flutter SDK（3.5+），`flutter doctor` 能看到 Android toolchain
- JDK 17、Android SDK
- Node.js 22+
- 一台 Android 真机（需麦克风权限）
- 阿里云百炼北京地域 API Key（真转写 / 真摘要时需要）

```bash
flutter --version
node -v
```

## 安装依赖

在仓库根目录：

```bash
flutter pub get
```

后端：

```bash
cd server
copy .env.example .env
npm install
```

编辑 `server/.env`：

```env
PORT=3000
ASR_PROVIDER=dashscope
LLM_PROVIDER=dashscope
DASHSCOPE_API_KEY=你的百炼Key
DASHSCOPE_BASE_URL=https://dashscope.aliyuncs.com/api/v1
DASHSCOPE_ASR_MODEL=qwen3-asr-flash
DASHSCOPE_LLM_MODEL=qwen-plus
```

`ASR_PROVIDER=none` 时任务会失败并提示「未配置转写服务」，**不会编造全文**。本地只测录音、不测云端时可以保持 `none`。

不要把 `.env`、`android/key.properties`、keystore 提交进 Git。

## 启动顺序（必须先后端）

上传、转写、摘要都打电脑上的 Node。先起后端，再装 / 跑 App。

### 1. 启动后端

```bash
cd server
npm start
```

进程监听 `0.0.0.0:3000`。本机检查：

```bash
curl http://127.0.0.1:3000/health
```

应返回：

```json
{"ok":true,"service":"echonote-server"}
```

不要对同一份 `server/data/echonote.sqlite` 同时开两个 `npm start`。测试时这个窗口保持开着。

查电脑当前 IPv4（Windows）：

```bash
ipconfig
```

看 **WLAN** 的 IPv4（例如 `192.168.1.9`）。真机走 Wi-Fi 时，优先用这个地址，不要用网线适配器上的另一个 IP，否则手机经常连不上。

### 2. 跑客户端（开发）

另开一个终端，在仓库根目录。把下面的 IP 换成上一步的 WLAN 地址：

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.9:3000
```

不要省略 `--dart-define`。默认值 `http://10.0.2.2:3000` 只给 Android 模拟器访问电脑，**真机无效**。

首次录音会申请麦克风。永久拒绝时可在录音页点「前往系统设置」。

## 打包 APK

局域网用手机文件管理器安装时，打 **debug** 包（允许明文 HTTP）。把 IP 换成你的 WLAN 地址：

```bash
flutter build apk --debug --split-per-abi --dart-define=API_BASE_URL=http://192.168.1.9:3000
```

小米 12 等 arm64 真机用：

`build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`

可复制到桌面后改名，例如 `echonote-1.5.2.apk`。不要把 APK 提交进 Git。

Release 包默认禁止明文 HTTP，局域网 `http://192.168.x.x:3000` 会失败。外网演示需要先把 Node 部署到公网 HTTPS，再用那个地址打 release：

```bash
flutter build apk --release --dart-define=API_BASE_URL=https://你的后端域名
```

覆盖安装时内部版本号需递增。当前是 `1.5.2+7`。

## 真机怎么测

### 网络要求

- 手机和电脑连 **同一个 Wi-Fi**，不要用手机流量，不要开 VPN
- 不要用路由器「访客网络」（通常隔离局域网设备）
- 电脑防火墙放行入站 TCP `3000`（本机若已加过「EchoNote 3000」规则即可）
- 后端窗口必须一直开着

手机访问的是打包时写死的 `API_BASE_URL`。电脑换了 Wi-Fi、IP 变了，要重新打包或 `flutter run`。

### 建议测试路径

1. 新建录音：开始 → 暂停（计时停）→ 继续 → 停止，回到列表
2. 播放、暂停、拖进度、删除（有确认框）
3. 完全杀掉 App 再打开，列表还在
4. 点「上传」，状态经过上传中、转写处理中 / 生成摘要中，最后已完成
5. 进详情，能看到转写全文和智能摘要，可分别复制
6. （可选）断网点上传，应提示失败且可重试；摘要失败时全文仍在，详情为「重新生成摘要」

「已完成」表示转写和摘要都成功。只有转写成功、摘要失败时，列表显示「处理失败」，详情里能看到原因和已有全文。

## 处理状态

| 页面文案 | 含义 |
| --- | --- |
| 待上传 | 本地已保存，未提交后端 |
| 上传中 | 正在传音频 |
| 转写处理中 | 后端在跑语音识别 |
| 生成摘要中 | 识别已有全文，正在调大模型 |
| 已完成 | 转写和摘要都成功 |
| 处理失败 | 任一步失败，详情里有原因 |
| 状态暂时无法更新 | 查询超时或后端瞬时错误，任务本身未必失败 |

上传中、转写处理中不能删除。查询不会触发转写，避免轮询重复计费。

## 后端接口

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/health` | 探活 |
| `POST` | `/api/transcriptions` | `clientRecordingId` + 音频；同一 id 返回已有任务 |
| `GET` | `/api/transcriptions/:id` | 只读查询，不触发转写 |
| `POST` | `/api/transcriptions/:id/retry` | 只重跑失败阶段（摘要失败不重传音频） |

上传为 multipart。后端把音频落盘后，调用百炼时再编成 Base64。同步识别大约 5 分钟 / 编码后约 10MB。

### 环境变量

| 名称 | 作用 |
| --- | --- |
| `PORT` | 监听端口，默认 3000 |
| `ASR_PROVIDER` | `none` 或 `dashscope` |
| `LLM_PROVIDER` | `none` 或 `dashscope` |
| `DASHSCOPE_API_KEY` | 百炼北京地域 Key |
| `DASHSCOPE_BASE_URL` | 默认 `https://dashscope.aliyuncs.com/api/v1` |
| `DASHSCOPE_ASR_MODEL` | 默认 `qwen3-asr-flash` |
| `DASHSCOPE_LLM_MODEL` | 默认 `qwen-plus` |

## 架构

```text
Flutter 录音 → 本地文件 + SQLite
     ↓ 用户点上传（同一 Wi-Fi）
Node POST /api/transcriptions（幂等 clientRecordingId）
     ↓
百炼 qwen3-asr-flash → 全文
     ↓ 自动
百炼 qwen-plus → 摘要
     ↓
Flutter 每 5 秒 GET 一次（仅前台），详情展示全文和摘要
```

App 不直连百炼。

## 测试

```bash
flutter test
flutter analyze
cd server && npm test
```

## 技术取舍

- 密钥只在服务端，避免 APK 被反编译拿走
- HTTP 客户端用 `http` 而不是 Dio，上传能力足够
- 转写用同步 Base64，不依赖 OSS 公网 URL
- 摘要用任意 LLM 即可，这里和转写共用一把百炼 Key
- 客户端五个主状态对齐产品口径；「生成摘要中」是处理中的子阶段
- 查询失败保持处理中，避免把还在跑的任务误判失败

## 已知问题

- 局域网演示依赖电脑 IP；换网络必须改 `API_BASE_URL` 重新编译
- 别人不在同一 Wi-Fi 无法上传，需要把后端部署到公网 HTTPS
- Debug 包体积较大（含调试信息）；正式分发应使用 release + HTTPS
- 超长录音受百炼 Base64 体积限制，P0 未做分段上传
- 任务音频文件暂不自动清理


