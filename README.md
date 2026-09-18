# EchoNote（随身录音笔记）

Android 录音笔记：本地录音、列表试听，上传到后端后完成语音转写和智能摘要。

当前 App 版本 **1.6.2+18**。API 密钥只放在已部署的服务端，不会打进 APK。

## 运行方式

后端已部署，App 默认请求 `http://39.96.17.209:3000`。`server/` 仅作源码对照，**复现客户端不必在本地启动 Node**。

环境：Flutter 3.5+、JDK 17、Android SDK。探活：`http://39.96.17.209:3000/health` 应返回 `{"ok":true,"service":"echonote-server"}`。

```bash
git clone https://github.com/songquanjie/work1.git
cd work1
flutter pub get
flutter build apk --debug --split-per-abi
```

安装 `build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk`。当前后端为 HTTP，请使用 debug 包。手机能上网即可，无需与电脑同一 Wi-Fi。

本地自建后端时：`cd server && cp .env.example .env && npm install && npm start`，打包增加 `--dart-define=API_BASE_URL=http://本机WLAN的IP:3000`，且手机需与电脑同一局域网。

## 功能

- 录音：开始 / 暂停 / 继续 / 停止；实时时长和音量
- 列表：名称、时长、创建时间、处理状态；本地播放、删除；长按可改展示名（中文不影响上传）
- 上传转写：待上传 → 上传中 → 转写处理中 / 生成摘要中 → 已完成或失败
- 详情：试听、重命名、转写全文和智能摘要（可分别复制）；失败可重试
- 启动：白屏等待数据库打开后再进列表
- 杀进程后列表、全文和摘要仍在；未完成任务回到前台会继续查询
- 设备：底栏第二页扫描附近蓝牙设备，显示名称和信号强度，点进去连接并列出 GATT 服务

不包含登录、多端同步、iOS、后台持续录音、边录边转。

## 技术栈

| 端 | 技术 |
| --- | --- |
| 客户端 | Flutter 3.x / Dart 3.x，Android |
| 录音 / 播放 | `record`、`just_audio` |
| 本地数据 | `sqflite` + 应用文档目录中的音频文件 |
| 网络 | `http`（multipart 上传） |
| 蓝牙 | `flutter_blue_plus`（扫描 / 连接 / GATT 服务列表） |
| 后端 | Node.js ≥ 22，Express，SQLite |
| 转写 | 阿里云百炼 `qwen3-asr-flash`（同步 HTTP + Base64） |
| 摘要 | 阿里云百炼 `qwen-plus`（文本生成 HTTP） |

## 目录结构

```text
EchoNote/
├── lib/                      Flutter 客户端（打包运行用这个）
│   ├── features/             启动页、底栏、录音、列表、详情、播放条、设备页
│   ├── repositories/         协调文件、数据库、HTTP
│   ├── data/                 SQLite、转写 API
│   └── services/             录音、播放、轮询、BLE 扫描连接
├── server/                   Node 后端源码（展示与对照，体验 App 不必本地启动）
│   ├── src/                  路由、任务管线、百炼调用
│   ├── .env.example          环境变量模板
│   └── .env                  真实密钥（不入库，只在服务器上）
├── android/                  Android 工程
└── README.md
```

录音相关页面不直接访问 SQLite、本地文件或 HTTP，一律走 `RecordingRepository`。设备页走 `BleController` / `BleScanner`，不直接调用 `flutter_blue_plus`。

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

云上与本地 `server/` 是同一套。根地址默认为 `http://39.96.17.209:3000`。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/health` | 探活 |
| `POST` | `/api/transcriptions` | `clientRecordingId` + 音频；同一 id 返回已有任务 |
| `GET` | `/api/transcriptions/:id` | 只读查询，不触发转写 |
| `POST` | `/api/transcriptions/:id/retry` | 只重跑失败阶段（摘要失败不重传音频） |

上传为 multipart。后端把音频落盘后，调用百炼时再编成 Base64。同步识别大约 5 分钟 / 编码后约 10MB。

### 环境变量（仅自己跑 `server/` 时需要）

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
     ↓ 用户点上传（公网 http://39.96.17.209:3000）
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

`server` 测试不依赖云上的进程，在有 Node 的机器上即可跑。

## 技术取舍

- 密钥只在服务端，避免 APK 被反编译拿走
- HTTP 客户端用 `http` 而不是 Dio，上传能力足够
- 转写用同步 Base64，不依赖 OSS 公网 URL
- 摘要用任意 LLM 即可，这里和转写共用一把百炼 Key
- 客户端五个主状态对齐产品口径；「生成摘要中」是处理中的子阶段
- 查询失败保持处理中，避免把还在跑的任务误判失败
- 设备页只做扫描、连接和列出 GATT 服务；一次扫描约 15 秒，避免列表跟着信号强度不停跳动

## 已知问题

- 默认云地址是明文 HTTP，请用 debug 包；Release 需要 HTTPS 域名
- 云服务器停机或换公网 IP 后，要改 `AppConfig` 默认值或 `--dart-define` 再打包
- Debug 包体积较大（含调试信息）；正式分发应使用 release + HTTPS
- 超长录音受百炼 Base64 体积限制，P0 未做分段上传
- 任务音频文件暂不自动清理
- 未做边录边流转写与实时摘要（录音结束后再上传、整段转写再摘要）
- BLE 不读写特征值、不配对、不保活；扫完后列表会停住，要再更新需再点扫描
- 关闭定位后，部分 Android 设备扫不到 BLE

## 设备页

对应加分项（选做）：增加设备页，用 `flutter_blue_plus` 扫描周边 BLE 设备，展示名称 / RSSI，能连接任一设备并读取其 GATT 服务列表；可用另一台手机或 nRF Connect 模拟外设。核心录音、转写链路未为此让路。

底栏第二项即该页。扫描结果列出广播名和信号强度；点任意一行会连接该设备，并展示 GATT 服务 UUID。另一台手机打开 nRF Connect Advertiser 即可当作外设来验收。不读写特征值、不配对。

**核心实现**

- 协议：BLE + GATT。本机扫周边广播、连接后 `discoverServices` 列出服务 UUID。
- 库：`flutter_blue_plus`。扫描用 `startScan` / `onScanResults`（名称、`rssi`）；连接用 `connect`，读服务用 `discoverServices`。
- 结构：页面只走 `BleController` → `BleScanner`，不直接调插件。
- 系统：Android 12+ 申请 `BLUETOOTH_SCAN`、`BLUETOOTH_CONNECT`；扫描 BLE 还需要定位权限。
- 一次扫描约 15 秒；连接前先停扫，离开详情页 `disconnect`。
