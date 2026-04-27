# PTT 严格半双工设计（最小可运行版）

## 1. 目标

在现有 conference 型 PTT Demo 基础上，实现“同一房间同一时刻只允许一人发言”的最小可运行半双工能力。

## 2. 范围

本设计面向当前仓库已有组件：

- FreeSWITCH `mod_conference`
- FreeSWITCH `mod_event_socket`
- `scripts/python/ptt_demo/ptt_demo_service.py`

不引入新中间件，不修改 SIP 终端注册方式。

## 3. 话权规则

### 3.1 基本规则

1. 每个房间最多一个持有者（holder）。
2. 仅持有者可发言，其它成员保持静音（只听）。
3. 话权有超时（默认 10 秒），超时自动释放。
4. 持有者可主动释放话权。

### 3.2 输入动作

1. DTMF `9`：申请话权（或续租）。
2. DTMF `0`：释放话权。

### 3.3 冲突处理

1. 若房间已有持有者，新的申请返回 `busy`。
2. 若申请者即当前持有者，返回 `renewed` 并刷新超时。

## 4. 控制策略

服务端按房间执行策略同步：

1. 读取房间成员列表（call_id -> member_id）。
2. 找到当前 holder_call_id。
3. holder 对应 member `unmute`。
4. 其他 members 全部 `mute`。
5. 若房间无 holder，则全员 `mute`。

相关命令：

```text
conference <room> mute <member_id>
conference <room> unmute <member_id>
```

## 5. 状态模型

每个房间维护：

- `holder_call_id`
- `expires_at_ts`
- `members`（call_id -> member_id）

每个 call 维护：

- `call_id`
- `room`
- `member_id`

## 6. 生命周期

### 6.1 成员加入

1. 收到 `conference::maintenance add-member`。
2. 建立 call 与 member 的映射。
3. 执行一次房间策略同步。

### 6.2 申请话权

1. 收到 DTMF `9` 或 API 申请。
2. 状态机判定 `granted` / `renewed` / `busy`。
3. 若 `granted` 或 `renewed`，执行房间策略同步。

### 6.3 释放话权

1. 收到 DTMF `0` 或 API 释放。
2. 仅 holder 可释放成功。
3. 释放后执行房间策略同步。

### 6.4 挂机或离会

1. 挂机：若是 holder，自动释放。
2. 离会事件：移除 member 映射。
3. 若离会者是 holder，释放并同步策略。

### 6.5 超时

1. watchdog 周期扫描过期 holder。
2. 释放后同步策略。

## 7. API 建议与现状

当前最小可运行接口：

1. `GET /api/ptt/state`：查看所有房间状态。
2. `GET /api/ptt/state/{site}/{channel}`：查看指定房间状态。
3. `POST /api/ptt/floor/request`：按 `call_id` 申请话权。
4. `POST /api/ptt/floor/release`：按 `call_id` 释放话权。

请求体示例：

```json
{
  "call_id": "9de258e8-baf5-4cf9-9119-cd4f8f0e9123"
}
```

## 8. 联调步骤（最短路径）

1. 启动 FreeSWITCH，并 `reloadxml`。
2. 启动 `ptt_demo_service.py`。
3. 两个终端拨入同一房间（例如 `711`）。
4. 两端先都不按 `9`，确认双方均无法发声。
5. 终端 A 按 `9`，A 可发声、B 只听。
6. 终端 B 按 `9`，应返回 `busy`（保持 A 发言）。
7. A 按 `0` 释放后，B 再按 `9`，B 可发声。

## 9. 已知限制

1. 使用 DTMF 作为 PTT 键，不等价于真实按下/松开物理键。
2. 不含优先级、抢占级别、队列公平策略。
3. 房间空闲时全员静音，符合严格半双工但不适合开放会议。

## 10. 后续增强建议

1. 增加按键按下/松开事件通道（SIP INFO 或 WebSocket）。
2. 增加房间等待队列与优先级抢占。
3. 增加话权审计日志（grant/release/timeout/busy）。
4. 增加 Prometheus 指标（当前 holder、抢话失败次数、超时次数）。