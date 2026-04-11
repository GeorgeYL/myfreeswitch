# PTT Java 版通话事件监控 + PostgreSQL 落库 + JNI 查询下载

## 1. 目标与范围

本实现位于 `java/ptt-monitor`，提供以下能力：

1. 通过 FreeSWITCH ESL (`127.0.0.1:8021`) 监听通话事件。
2. 处理 `CHANNEL_ANSWER` / `CHANNEL_HANGUP_COMPLETE` 并聚合通话日志。
3. 通话日志落地 PostgreSQL 表 `ptt_call_logs`。
4. 提供 Java 查询服务（按分页查询、按 `call_id` 查询、录音下载）。
5. 提供 JNI Native API（`queryLogsJson`、`getLogByCallIdJson`、`downloadRecording`）。
6. 提供 Java HTTP API（`/health`、`/api/logs`、`/api/logs/{call_id}`、`/api/recordings/{call_id}`）。

## 2. 目录结构

- `java/ptt-monitor/pom.xml`: Maven 构建定义。
- `java/ptt-monitor/sql/init.sql`: PostgreSQL 表结构。
- `java/ptt-monitor/src/main/java/com/rocktech/ptt/Main.java`: 监控服务入口。
- `java/ptt-monitor/src/main/java/com/rocktech/ptt/HttpApiServer.java`: HTTP API 服务。
- `java/ptt-monitor/src/main/java/com/rocktech/ptt/PttEventMonitor.java`: ESL 事件监听与状态聚合。
- `java/ptt-monitor/src/main/java/com/rocktech/ptt/PostgresRepository.java`: 落库与查询。
- `java/ptt-monitor/src/main/java/com/rocktech/ptt/QueryService.java`: Java 查询与录音下载。
- `java/ptt-monitor/src/main/java/com/rocktech/ptt/jni/PttJniApi.java`: JNI Java 声明。
- `java/ptt-monitor/src/main/native/ptt_jni_bridge.cpp`: JNI C++ 实现（libpq 直连 PG）。
- `java/ptt-monitor/src/main/native/CMakeLists.txt`: JNI 动态库构建。
- `java/ptt-monitor/run-monitor.ps1`: 一键启动监控服务。
- `java/ptt-monitor/run-all.ps1`: 一键检查环境并启动监控 + HTTP API。
- `java/ptt-monitor/smoke-http.ps1`: HTTP 接口冒烟测试。
- `java/ptt-monitor/switch-api-mode.ps1`: Java/Python API 启动模式切换。
- `java/ptt-monitor/test-query.ps1`: 快速查询测试。

## 3. 实现方案

### 3.1 事件采集

1. `EslClient` 使用 TCP 连接 ESL。
2. 完成 `auth ClueCon` 认证。
3. 订阅：`event plain CHANNEL_ANSWER CHANNEL_HANGUP_COMPLETE`。
4. 解析 `text/event-plain` 帧，转为键值对。

### 3.2 日志聚合规则

1. 在 `CHANNEL_ANSWER` 时缓存活动通话（`call_id`、设备、IP、房间、开始时间、录音文件）。
2. 在 `CHANNEL_HANGUP_COMPLETE` 时完成闭环计算：
   - `duration_seconds`
   - `status`（`NORMAL_CLEARING` => `NORMAL_END`）
   - `file_size_bytes`
3. 生成完整记录并写入 PostgreSQL（按 `call_id` upsert）。

### 3.3 PostgreSQL 落库

DDL 见 `sql/init.sql`。

关键点：

1. `call_id` 唯一约束，防重复。
2. `end_time` 索引用于最新日志分页查询。
3. `room` 索引用于后续按组检索扩展。

### 3.4 Java 查询与下载接口

`QueryService` 提供：

1. `queryLogsJson(limit, offset)`
2. `getLogByCallIdJson(callId)`
3. `downloadRecording(callId, targetFile)`

`QueryCli` 可直接命令行调用。

### 3.5 JNI API 设计

`PttJniApi` 声明：

1. `String queryLogsJson(int limit, int offset)`
2. `String getLogByCallIdJson(String callId)`
3. `int downloadRecording(String callId, String targetPath)`

`ptt_jni_bridge.cpp` 通过 `libpq` 直接查询 PostgreSQL，并执行录音文件复制。

返回码约定（`downloadRecording`）：

1. `0`: 成功
2. `2`: 未找到 `call_id`
3. `3`: 录音文件不存在
4. `1`: 其他异常（同时抛出 Java `RuntimeException`）

### 3.6 Java HTTP API 设计

默认监听：`0.0.0.0:8091`。

提供接口：

1. `GET /health`
2. `GET /health/db`
3. `GET /api/logs?limit=100&offset=0`
4. `GET /api/logs/{call_id}`
5. `GET /api/recordings/{call_id}`

返回语义与 Python 版保持一致：

1. 不存在日志时返回 404。
2. 录音文件不存在时返回 404。
3. 数据库异常返回 500。
4. `GET /health/db` 在数据库不可达时返回 503。

## 4. 适配方式

### 4.1 环境变量

监控服务与查询/JNI共用以下配置：

- `ESL_HOST` 默认 `127.0.0.1`
- `ESL_PORT` 默认 `8021`
- `ESL_PASSWORD` 默认 `ClueCon`
- `FS_DOMAIN` 默认 `127.0.0.1`
- `RECORDINGS_DIR` 默认 `D:/03_rocktech/source/freeswitch/x64/Release/recordings`
- `PG_URL` 默认 `jdbc:postgresql://127.0.0.1:5432/ptt_demo`
- `PG_USER` 默认 `postgres`
- `PG_PASSWORD` 默认 `postgres`
- `HTTP_ENABLE` 默认 `true`
- `HTTP_HOST` 默认 `0.0.0.0`
- `HTTP_PORT` 默认 `8091`

JNI C++ 连接 PG 可用：

- `PG_CONNINFO`，例如：
  `host=127.0.0.1 port=5432 dbname=ptt_demo user=postgres password=postgres`

### 4.2 Windows 构建适配

1. JDK 17+
2. Maven 3.9+
3. PostgreSQL 客户端（需 `libpq`）
4. CMake 3.16+
5. `JAVA_HOME` 正确设置

### 4.3 运行适配

1. 先启动 `FreeSwitchConsole.exe`。
2. 确认 `127.0.0.1:8021` 通。
3. 确认 PostgreSQL 可连接且库已创建。
4. 运行 `run-all.ps1`。

首次可用性初始化（仅需一次）：

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
$env:PGPASSWORD='postgres'
& 'C:\Program Files\PostgreSQL\18\bin\createdb.exe' -h 127.0.0.1 -U postgres ptt_demo
```

## 5. 测试方法

### 5.1 服务启动测试

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
.\run-all.ps1
```

若出现 PowerShell 执行策略限制，可用：

```powershell
powershell -ExecutionPolicy Bypass -File .\run-all.ps1
```

预期：

1. 输出 PostgreSQL ready。
2. 输出 ESL connected。
3. 输出 HTTP API listening。
4. 呼叫后出现 persisted call log。

### 5.2 HTTP 接口冒烟

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
.\smoke-http.ps1 -BaseUrl http://127.0.0.1:8091
```

预期：

1. `health` 返回 `status=ok`。
2. `/api/logs` 返回 JSON 数组。

浏览器可直接访问：

1. `http://127.0.0.1:8091/health`
2. `http://127.0.0.1:8091/health/db`
3. `http://127.0.0.1:8091/api/logs`

### 5.3 Java/Python API 模式切换

使用同一个脚本切换 API 运行模式（默认 Java）：

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
.\switch-api-mode.ps1 -Mode java
```

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
.\switch-api-mode.ps1 -Mode python
```

说明：

1. Java 模式走 `run-all.ps1`（默认端口 `8091`）。
2. Python 模式走 `scripts/python/ptt_demo/run_demo.ps1`（默认端口 `8090`）。
3. 脚本会先检查目标端口占用，避免误起冲突进程。

### 5.4 通话事件落库测试

1. 两个软电话注册 `1000/1001`。
2. 同时拨 `711`，通话后挂断。
3. 执行：

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
.\test-query.ps1
```

预期：

1. 返回 JSON 数组。
2. 包含 `call_id/start_time/end_time/record_file`。

### 5.5 JNI API 测试

1. 先构建 `ptt_jni_bridge` 动态库。
2. 设置：
   - `PTT_JNI_ENABLE=1`
   - `java.library.path` 包含动态库目录。
3. 执行 JNI 演示：

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
mvn -q -DskipTests package
java -DPTT_JNI_ENABLE=1 -Djava.library.path=".\build\native" -cp ".\target\ptt-monitor-1.0.0.jar" com.rocktech.ptt.jni.PttJniDemo <call_id>
```

预期：

1. `queryLogsJson` 返回日志 JSON。
2. `getLogByCallIdJson` 返回单条 JSON。
3. `download rc=0` 且输出文件 `jni-demo.wav` 存在。

## 6. 与现有 Python 版关系

1. Java 版与 Python 版可并行存在，建议同一时刻仅启用一个事件落库服务，避免重复写入。
2. 现有 `/api/logs` HTTP 接口仍可继续用于演示。
3. 若后续需要统一，可在 Java 版上补 REST 层，替代 Python API。

## 7. 本次排查记录（实测）

以下问题来自本机 Windows 实测，已完成修复或给出稳定处理方式。

### 7.1 `run-all.ps1` 变量插值报错

现象：

- `Variable reference is not valid. ':' was not followed by a valid variable name character`

原因：

- PowerShell 中字符串 `"$EslHost:$EslPort"` 会把 `:` 误判为变量语法边界。

处理：

- 脚本改为 `"${EslHost}:$EslPort"`。

### 7.2 `Missing command: java`

现象：

- 执行 `run-all.ps1` 时提示找不到 `java`/`javac`。

原因：

- 当前 PowerShell 会话未配置 `PATH`，但 JDK 已安装。

处理：

1. 临时设置：

```powershell
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-25.0.2.10-hotspot'
```

2. 脚本增强：

- `run-all.ps1` 现在会在 `PATH` 缺失时自动从 `JAVA_HOME\\bin` 解析 `java.exe/javac.exe`。

### 7.3 JDBC 驱动缺失（`No suitable driver`）

现象：

- 直接运行普通 JAR 时，连接 PostgreSQL 报 `No suitable driver found`。

原因：

- 普通 JAR 不包含运行时依赖（PostgreSQL JDBC）。

处理：

- 使用 Maven shade 产出可执行 fat JAR（`ptt-monitor-1.0.0-all.jar`）。
- `run-all.ps1` 统一走 Maven `package` 后启动 fat JAR。

### 7.4 数据库不存在（`ptt_demo`）

现象：

- PostgreSQL 服务正常，但目标库不存在导致启动失败。

处理（一次性）：

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
$env:PGPASSWORD='postgres'
& 'C:\Program Files\PostgreSQL\18\bin\createdb.exe' -h 127.0.0.1 -U postgres ptt_demo
```

### 7.5 HTTP 端口占用（`Address already in use: bind`）

现象：

- Java 启动时报 `BindException`，端口 `8091` 被旧进程占用。

处理：

```powershell
Get-NetTCPConnection -LocalPort 8091 -State Listen | Select-Object LocalAddress,LocalPort,OwningProcess
Stop-Process -Id <PID> -Force
```

### 7.6 ESL 超时提示

现象：

- 控制台出现 `ESL loop error: Timeout waiting ESL auth/request`。

说明：

- 该日志表示 ESL 事件循环连接异常，不影响 HTTP 进程存活判断；`/health` 仍可返回 `{"status":"ok"}`。
- 若需恢复事件监听，优先检查 FreeSWITCH ESL 服务与 `8021` 连通性后重启 `run-all.ps1`。

### 7.7 快速恢复命令（建议）

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
$env:JAVA_HOME='C:\Program Files\Microsoft\jdk-25.0.2.10-hotspot'

# 如端口冲突先释放（可选）
$tcp = Get-NetTCPConnection -LocalPort 8091 -State Listen -ErrorAction SilentlyContinue
if ($tcp) { Stop-Process -Id $tcp.OwningProcess -Force }

.\run-all.ps1
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8091/health | Select-Object -ExpandProperty Content
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8091/health/db | Select-Object -ExpandProperty Content
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8091/api/logs | Select-Object -ExpandProperty Content
```

## 8. 本次冒烟结果（通过）

执行命令：

```powershell
cd d:\03_rocktech\source\freeswitch\java\ptt-monitor
.\smoke-http.ps1 -BaseUrl http://127.0.0.1:8091
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8091/health | Select-Object -ExpandProperty Content
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8091/health/db | Select-Object -ExpandProperty Content
Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8091/api/logs | Select-Object -ExpandProperty Content
```

输出摘要：

1. `health`:

```json
{"status":"ok"}
```

2. `health/db`:

```json
{"status":"ok","database":"ready"}
```

3. `api/logs`:

```json
[]
```

结论：

1. Java HTTP API 已可访问。
2. PostgreSQL 连接正常。
3. 当前无通话记录时，`/api/logs` 返回空数组，行为符合预期。
