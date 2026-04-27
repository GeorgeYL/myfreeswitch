# PTT Demo 软电话快速配置（Windows）

## 1. 前置条件

1. FreeSwitchConsole 已启动。
2. `127.0.0.1:8021` 连通。
3. 内部 SIP 默认监听 `UDP 5060`，但通常绑定在实际网卡 IP（`$${local_ip_v4}`），不一定是 `127.0.0.1`。
4. 测试分机：
   - 1000 / 1234
   - 1001 / 1234

推荐先查实际 SIP 绑定地址：

```powershell
Get-NetUDPEndpoint -LocalPort 5060 | Select-Object LocalAddress, LocalPort
```

将查到的 IPv4 地址记为 `FS_IP`（例如 `192.168.2.18`）。

---

## 2. 拨号规则（PTT）

- 拨号范围：`711` 到 `744`
- 规则含义：`7xy`
  - `x` = 场地（1-4）
  - `y` = 信道（1-4）

示例：

- `711` = 场地1信道1
- `721` = 场地2信道1

同号在同一组内互通，不同号组间隔离。

半双工话权按键（默认）：

- DTMF `9`：申请/续租话权
- DTMF `0`：释放话权
- DTMF `1` / `2` / `3`：机器人播报触发

---

## 3. MicroSIP 配置（推荐）

### 3.1 账号 A（分机 1000）

- SIP Server: `FS_IP`（例如 `192.168.2.18`）
- Username: `1000`
- Domain: `FS_IP`（例如 `192.168.2.18`）
- Login: `1000`
- Password: `1234`
- Transport: `UDP`
- Port: `5060`

### 3.2 账号 B（分机 1001）

- SIP Server: `FS_IP`（例如 `192.168.2.18`）
- Username: `1001`
- Domain: `FS_IP`（例如 `192.168.2.18`）
- Login: `1001`
- Password: `1234`
- Transport: `UDP`
- Port: `5060`

### 3.3 建议设置

- 关闭 STUN / ICE（本机测试不需要）。
- 注册间隔可保持默认。
- 音频优先使用 PCMU/PCMA/OPUS 任一可用编解码。

### 3.4 MicroSIP 逐字段填写（按界面）

以下按 MicroSIP 常见版本的 `Add account` / `Edit account` 窗口字段说明。

先假设：

- `FS_IP = 192.168.2.18`（请替换为你机器实际 UDP 5060 绑定地址）

账号 A（1000）字段：

1. `Account name`: `FS-1000`
2. `SIP server`: `192.168.2.18`
3. `Username`: `1000`
4. `Domain`: `192.168.2.18`
5. `Login`: `1000`
6. `Password`: `1234`
7. `Display name`（有则填）: `1000`
8. `Transport`（在 Advanced）: `UDP`
9. `Port`（在 Advanced）: `5060`
10. `SRTP`（若有）: `Disabled`
11. `Publish presence`（若有）: `Off`

账号 B（1001）字段：

1. `Account name`: `FS-1001`
2. `SIP server`: `192.168.2.18`
3. `Username`: `1001`
4. `Domain`: `192.168.2.18`
5. `Login`: `1001`
6. `Password`: `1234`
7. `Display name`（有则填）: `1001`
8. `Transport`（在 Advanced）: `UDP`
9. `Port`（在 Advanced）: `5060`
10. `SRTP`（若有）: `Disabled`
11. `Publish presence`（若有）: `Off`

两账号并行方法（同一台电脑）：

1. 准备两份 MicroSIP 目录（如 `MicroSIP-A`、`MicroSIP-B`）。
2. 分别启动两份程序，各自保存一个账号配置。
3. A 使用 `FS-1000`，B 使用 `FS-1001`。

注册成功判定：

1. 状态栏显示 `Online` / `Registered`。
2. 若显示 `408/403/Timeout`，优先检查 `FS_IP`、`UDP`、`5060`、账号密码。

---

## 4. Linphone 配置

### 4.1 Identity

- A: `sip:1000@FS_IP`
- B: `sip:1001@FS_IP`

### 4.2 SIP Proxy / Server

- Server address: `sip:FS_IP:5060;transport=udp`
- Register: `enabled`

### 4.3 Authentication

- Username: `1000` 或 `1001`
- User ID: 与 Username 一致
- Password: `1234`
- Realm: 可留空（由服务器挑战）

### 4.4 建议设置

- 关闭 ICE/STUN/TURN（本机测试）。
- DTMF 方式优先 RFC2833（默认一般可用）。

---

## 5. 最短联调步骤

1. A 注册成功（显示在线）。
2. B 注册成功（显示在线）。
3. A 拨 `711`。
4. B 也拨 `711`。
5. 双方互相讲话，确认组内互通。
6. B 挂断后改拨 `721`。
7. 此时 A(711) 与 B(721) 互不可听，确认组间隔离。

半双工验证（同一房间）：

1. A 与 B 都拨 `711`。
2. A 按 `9`，A 说话时 B 只听。
3. B 按 `9`，若 A 未释放，应保持 `busy` 状态。
4. A 按 `0` 释放后，B 按 `9` 可成为当前发言方。

---

## 6. API 联动验证

### 6.1 启动日志服务（PTT Demo API）

在 `scripts/python/ptt_demo` 目录执行：

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
2. `127.0.0.1:8021` 可连通（见第 1 节）。

### 6.2 测试日志接口

另开一个 PowerShell 窗口执行：

```powershell
# 健康检查
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/health" | ConvertTo-Json

# 查看全部日志
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/logs" | ConvertTo-Json -Depth 6
```

预期：

1. `health` 返回 `{"status":"ok"}`。
2. 初始 `logs` 可能为空数组；完成一次通话后应出现记录。

补充：查看半双工状态

```powershell
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/ptt/state" | ConvertTo-Json -Depth 6
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/ptt/state/1/1" | ConvertTo-Json -Depth 6
```

按 `call_id` 查询与下载录音：

```powershell
# 先取最近一条日志的 call_id
$all = Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/logs"
$callId = $all[-1].call_id

# 查单条日志
Invoke-RestMethod -Method Get -Uri "http://127.0.0.1:8090/api/logs/$callId" | ConvertTo-Json -Depth 6

# 下载录音
Invoke-WebRequest -Uri "http://127.0.0.1:8090/api/recordings/$callId" -OutFile ".\\demo.wav"
```

浏览器查看（可选）：

- `http://127.0.0.1:8090/api/logs`

在 `scripts/python/ptt_demo` 下执行：

```powershell
.\api_smoke_test.ps1
```

预期：

1. `health` 返回 ok。
2. `log_count` 大于 0（通话后）。
3. `bot/reply` 返回成功（当目标 conference 已存在时）。

---

## 7. 常见问题

### 7.1 无法注册

- 检查 FreeSwitchConsole 是否仍在运行。
- 检查软电话是否填了 `FS_IP:5060/UDP`（`FS_IP` 为实际绑定地址）。
- 检查账号密码是否为 `1000/1234`、`1001/1234`。

### 7.2 能注册但拨号没声音

- 先用同号测试（都拨 `711`）。
- 检查系统默认输入输出设备是否正确。
- 关闭独占音频模式后重试。

### 7.3 API 机器人返回 conference not found

- 先确保至少有一台终端已经拨入目标房间（如 `711`）。
- 再调用 `api_smoke_test.ps1`。

### 7.4 录音看不到文件

- 检查 `run_demo.ps1` 启动参数中的 `-RecordingsDir`。
- 推荐设置为：`D:/03_rocktech/source/freeswitch/x64/Release/recordings`
