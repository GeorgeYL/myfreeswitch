# FreeSWITCH 对讲培训 Demo（4 场地 x 4 信道）

## 1. 需求可行性结论

可以通过 FreeSWITCH 实现，推荐能力映射如下：

- 场地与信道隔离：使用 `mod_conference`，每个信道对应独立 conference 房间。
- 实时对讲：终端通过 SIP over WiFi 注册到 FreeSWITCH，拨号进入对应 conference。
- 通话日志与录音：拨号计划自动 `record_session`，并通过 ESL 事件实时聚合日志。
- 第三方接口：通过独立 HTTP 服务对外提供日志查询、录音读取接口。
- 机器人自动回复：通过 DTMF/接口触发，机器人向指定信道播报预置语音。

## 2. Demo 文件清单

本 demo 已新增以下文件：

- `conf/vanilla/dialplan/default/20_ptt_training_demo.xml`
- `scripts/python/ptt_demo/ptt_demo_service.py`
- `scripts/python/ptt_demo/requirements.txt`
- `scripts/python/ptt_demo/generate_bot_audio.ps1`
- `scripts/python/ptt_demo/run_demo.ps1`
- `scripts/python/ptt_demo/api_smoke_test.ps1`

## 3. 对讲拨号规则

### 3.1 拨号映射

拨号规则：`7xy`

- `x` = 场地编号（1-4）
- `y` = 信道编号（1-4）

示例：

- `711` -> 场地1 信道1 -> 房间 `ptt_s1_c1`
- `734` -> 场地3 信道4 -> 房间 `ptt_s3_c4`
- `744` -> 场地4 信道4 -> 房间 `ptt_s4_c4`

### 3.2 通话与隔离逻辑

- 同信道同场地用户进入同一 conference，可双向实时通话。
- 不同 `7xy` 对应不同 conference，自然互不干扰。

## 4. 日志字段与需求字段对应

HTTP 接口 `/api/logs` 返回单条记录示例字段：

- `seq`: 序号
- `device_id`: 对讲机编号（默认取 caller_id_number）
- `ip`: 设备 IP（事件中的网络地址）
- `site`: 场地
- `channel`: 信道
- `start_time`: 通话开始时间
- `end_time`: 通话结束时间
- `duration_seconds`: 通话时长（秒）
- `status`: 通话状态（`NORMAL_END` 或 Hangup Cause）
- `record_file`: 录音路径
- `file_size_bytes`: 文件大小（字节）
- `call_id`: FreeSWITCH UUID（便于追踪）

## 5. 启动步骤

> 以下步骤以 Windows + 你当前源码目录为例。

### 5.1 启动 FreeSWITCH

如果你已经有安装好的 FreeSWITCH，可直接启动并使用 `conf/vanilla` 配置。

关键要求：

- `mod_conference` 已加载（vanilla 默认已加载）
- `mod_event_socket` 已加载（vanilla 默认已加载）
- ESL 参数默认：`127.0.0.1:8021` / 密码 `ClueCon`

建议在 FS CLI 执行：

```bash
reloadxml
```

### 5.2 准备机器人播报语音

在 PowerShell 执行：

```powershell
cd d:\03_rocktech\source\freeswitch\scripts\python\ptt_demo
.\generate_bot_audio.ps1
```

生成目录：

- `scripts/python/ptt_demo/bot_audio/qa_schedule.wav`
- `scripts/python/ptt_demo/bot_audio/qa_safety.wav`
- `scripts/python/ptt_demo/bot_audio/qa_help.wav`
- `scripts/python/ptt_demo/bot_audio/qa_default.wav`

### 5.3 启动日志/API/机器人服务

```powershell
cd d:\03_rocktech\source\freeswitch\scripts\python\ptt_demo
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn ptt_demo_service:app --host 0.0.0.0 --port 8090
```

### 5.4 一键启动（推荐）

```powershell
cd d:\03_rocktech\source\freeswitch\scripts\python\ptt_demo
.\run_demo.ps1 -FsDomain 127.0.0.1
```

如需跳过 ESL 预检查（不推荐，仅排障时使用）：

```powershell
.\run_demo.ps1 -FsDomain 127.0.0.1 -SkipEslCheck
```

该脚本会自动完成：

- 创建虚拟环境（若不存在）
- 安装依赖
- 生成机器人音频
- 启动 API 服务

可选环境变量（按需）：

- `ESL_HOST`（默认 `127.0.0.1`）
- `ESL_PORT`（默认 `8021`）
- `ESL_PASSWORD`（默认 `ClueCon`）
- `FS_DOMAIN`（默认 `127.0.0.1`，应与拨号计划中的 `${domain_name}` 一致）
- `RECORDINGS_DIR`（默认 `C:/freeswitch/recordings`）
- `BOT_AUDIO_DIR`（默认 `scripts/python/ptt_demo/bot_audio`）
- `PTT_FLOOR_TIMEOUT_SECONDS`（默认 `10`，半双工话权超时秒数）

## 6. 测试步骤

### 6.0 本地联调最短路径（建议先跑）

```powershell
# 1) 先确认 FreeSWITCH 的 ESL 端口是否可达
Test-NetConnection 127.0.0.1 -Port 8021

# 2) 在 FreeSWITCH CLI 执行
reloadxml

# 3) 启动 Demo API
cd d:\03_rocktech\source\freeswitch\scripts\python\ptt_demo
.\run_demo.ps1 -FsDomain 127.0.0.1

# 4) 另开窗口做接口冒烟
.\api_smoke_test.ps1 -BaseUrl http://127.0.0.1:8090
```

如果第 1 步失败（TcpTestSucceeded=False），说明 FreeSWITCH 或 event socket 未就绪：

- 检查 `conf/vanilla/autoload_configs/event_socket.conf.xml` 的监听端口是否为 8021。
- 检查 `conf/vanilla/autoload_configs/modules.conf.xml` 是否已加载 `mod_event_socket`。
- 重启 FreeSWITCH 后再次验证 8021 端口。

### 6.1 终端注册

用 2 台及以上 SIP 软终端（同一 WiFi）注册到 FreeSWITCH。

### 6.2 同组互通测试

- 终端A拨 `711`
- 终端B拨 `711`

预期：

- A/B 可双向清晰通话
- 录音文件在挂机后落盘

### 6.3 组间隔离测试

- 终端C拨 `712`

预期：

- C 与 A/B 互不可听（不同 conference）

### 6.4 日志接口测试

若 API 未启动，可先在 `scripts/python/ptt_demo` 启动服务：

```powershell
cd d:\03_rocktech\source\freeswitch\scripts\python\ptt_demo

# 首次使用（仅一次）
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# 启动 API（默认 8090）
uvicorn ptt_demo_service:app --host 0.0.0.0 --port 8090
```

启动成功标志：

- 控制台出现 `Application startup complete`。
- 控制台出现 `Uvicorn running on http://0.0.0.0:8090`。

若启动时报 ESL 连接失败（如 8021 refused），先确认：

1. FreeSwitchConsole 正在运行。
2. `127.0.0.1:8021` 可连通。

查询健康状态与全部日志：

```powershell
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/health" | ConvertTo-Json
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/logs" | ConvertTo-Json -Depth 6
```

也可使用 curl 查询全部日志：

```bash
curl http://127.0.0.1:8090/api/logs
```

按 `call_id` 查询单条日志：

```bash
curl http://127.0.0.1:8090/api/logs/{call_id}
```

按 `call_id` 获取录音：

```bash
curl -OJ http://127.0.0.1:8090/api/recordings/{call_id}
```

也可直接执行冒烟脚本：

```powershell
cd d:\03_rocktech\source\freeswitch\scripts\python\ptt_demo
.\api_smoke_test.ps1 -BaseUrl http://127.0.0.1:8090
```

### 6.5 机器人自动回复测试

#### 方式A：信道内按键触发

- 在 `7xy` 通话中任意成员按 `1`、`2` 或 `3`
- 服务会将对应 `qa_*.wav` 播报到当前信道

#### 方式B：接口触发

```bash
curl -X POST http://127.0.0.1:8090/api/bot/reply \
  -H "Content-Type: application/json" \
  -d "{\"site\":1,\"channel\":1,\"question\":\"need safety reminder\"}"
```

预期：

- 场地1信道1 (`ptt_s1_c1`) 内成员听到机器人播报语音。

### 6.6 半双工话权测试（新增）

当前 Demo 已支持最小半双工控制，默认规则如下：

- DTMF `9`：申请话权（若当前空闲则授予，若已占用则返回 busy）
- DTMF `0`：释放话权
- DTMF `1`/`2`/`3`：保留机器人播报触发

测试步骤：

1. 终端A、终端B都拨 `711`。
2. A 按 `9` 申请话权，A 讲话时 B 仅监听。
3. B 按 `9`，若 A 未释放则应保持占线状态（busy）。
4. A 按 `0` 释放。
5. B 再按 `9`，B 成为当前发言方。

查询当前房间话权状态：

```powershell
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/ptt/state" | ConvertTo-Json -Depth 6
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/ptt/state/1/1" | ConvertTo-Json -Depth 6
```

按 `call_id` 申请/释放话权（用于接口联调）：

```powershell
# 取最近通话 call_id
$all = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/logs"
$callId = $all[-1].call_id

# 申请话权
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8090/api/ptt/floor/request" -ContentType "application/json" -Body (@{call_id=$callId} | ConvertTo-Json)

# 释放话权
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:8090/api/ptt/floor/release" -ContentType "application/json" -Body (@{call_id=$callId} | ConvertTo-Json)
```

## 7. 演示脚本（建议）

1. 展示 3 台终端分别进入 `711`、`711`、`712`。  
2. 证明 `711` 内互通、`712` 与 `711` 隔离。  
3. 在 `711` 内按 `2`，现场听到安全提示语音。  
4. 访问 `/api/logs` 展示日志实时新增。  
5. 用 `/api/recordings/{call_id}` 下载并播放录音文件。  

## 7.1 本次实机验收结果（Windows 本机）

以下项目已在本机实测通过：

- SIP 基础互拨：`1000 <-> 1001` 可正常呼叫与接听。
- 挂断联动：任一侧挂断后，对端在服务端日志中于同秒级被释放（毫秒级时间差）。
- 同组互通：`1000` 与 `1001` 均拨 `711`，均进入 `ptt_s1_c1@192.168.2.18`，可同组通话。
- 组间隔离：`1001` 拨 `711` 时进入 `ptt_s1_c1`；`1000` 拨 `721` 时进入 `ptt_s2_c1`；两者房间不同，隔离成立。
- 录音落盘：`recordings/ptt` 目录已生成对应 `711` 与 `721` 录音文件。

本次关键样例（文件名示例）：

- `20260410-233549_1001_711_63c6ab00-c0fb-4952-a5a4-d3bfa17902f7.wav`
- `20260410-233600_1000_721_6c555551-03b5-493d-93db-57ba3a1ff0e5.wav`

说明：

- `default_password=1234` 的系统告警日志仍会出现，但当前配置已不再人为延迟呼叫流程。
- 极个别软电话界面可能存在视觉刷新延迟；以 FreeSWITCH 日志中的 `Hangup`/`BYE` 时序为准。

## 8. 与原始需求的差异说明（Demo 范围）

- 机器人“内容分析模块”在本 demo 中用两种方式替代演示：
  - DTMF 触发（`1/2/3`）
  - 外部系统 POST `/api/bot/reply`（可视为分析模块输出后的调用）
- 如果要做到“语音自然语言识别 -> 自动匹配答案 -> TTS 回播”，可在此框架上接入 ASR/NLP/TTS 服务（如 MRCP/云 ASR + 业务知识库 + TTS）。

## 9. 生产化建议

- 使用 VLAN + QoS（WMM）保障 WiFi 语音优先级。
- 终端与 FS 之间启用 SRTP/TLS。
- 日志落地到 PostgreSQL/ClickHouse，并加对象存储保存录音。
- API 增加鉴权（JWT/API Key）和审计。
- 机器人模块改造为“流式 ASR + 语义检索 + TTS”。

## 10. 现场演示稿

- 按分钟口播稿与操作清单见：`docs/ptt-training-live-script.md`
- 领导汇报风格 5 分钟超短演示见：`docs/ptt-training-exec-5min.md`
- Visual Studio 最小必编清单见：`docs/ptt-vs-minimal-build.md`
- Linux 最小构建方案见：`docs/ptt-linux-minimal-build.md`
- Linux 一键总控脚本见：`scripts/python/ptt_demo/run_demo_linux.sh`
- Linux systemd 安装脚本见：`scripts/python/ptt_demo/install_systemd_service.sh`
- 软电话快速配置见：`docs/ptt-softphone-quickstart.md`
- Java 版通话监控 + PostgreSQL + JNI 实现见：`docs/ptt-java-monitor-jni.md`
