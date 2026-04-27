# FreeSWITCH 机器人实时语音：技术路线分析与实现

## 1. 你的需求拆解

现状：A 能呼叫 B，内网 SIP 通话已稳定。

新增目标：

1. A 呼叫“机器人 B”时，持续获取 A 的实时音频流。
2. 把实时音频送到服务器 S 做识别/对话/合成。
3. 把 S 返回的实时音频流播放给 A。
4. 全链路尽量低延迟、可生产。

这本质是双向实时媒体桥接问题：

- 上行：A -> FreeSWITCH -> S
- 下行：S -> FreeSWITCH -> A

## 2. 所有可行技术路线

按“实用性、延迟、开发难度、稳定性”综合排序如下。

### 路线 1：S 做 SIP 机器人终端（当前仓库最易落地）

方法：

- FreeSWITCH 把机器人号码路由到 SIP 网关（bot_s）。
- S 作为 SIP UA/B2BUA，直接收发 RTP。

优点：

- 完全原生，FreeSWITCH 无需媒体二开。
- 双向实时天然成立。
- 生产稳定性最好。
- 与现有 A 呼 B 模型最一致。

缺点：

- S 需要 SIP/RTP 栈能力。
- 需要处理编解码协商、抖动缓冲。

典型时延：

- 端到端首包通常 250-600ms（取决于 S 的 ASR/LLM/TTS 首包速度）。

---

### 路线 2：mod_audio_fork（第三方模块）+ WS/gRPC 媒体桥

方法：

- 在通话通道上分叉实时音频到 S。
- S 处理后回推音频，再注入给 A。

优点：

- S 不必支持 SIP，适配 AI 流式接口更直接。
- 可做精细控制（barge-in、打断、VAD）。
- 理论时延可做到很低。

缺点：

- 你当前仓库没有该模块源码，需要额外引入并维护。
- 不同 fork 实现命令/事件格式差异大。
- Windows/跨版本维护成本偏高。

典型时延：

- 设计得当可接近 SIP 路线，甚至更低；但工程风险更高。

---

### 路线 3：自研 C 模块（media bug）

方法：

- 用 switch_core_media_bug_add 直接读写帧。
- 自己实现与 S 的协议桥。

优点：

- 可控性最高，性能可做到极致。

缺点：

- 开发与维护成本最高。
- FreeSWITCH 升级兼容风险大。

适用：

- 团队有 C/媒体内核长期维护能力。

---

### 路线 4：ESL + 分段录音/分段回放（伪实时）

方法：

- 录短段音频上传 S。
- 生成短段回复后 playback/conference play。

优点：

- 快速验证业务。

缺点：

- 非严格实时，对话体验明显卡顿。

适用：

- PoC 或低实时性业务。

---

### 路线 5：MRCP（mod_unimrcp）

方法：

- ASR/TTS 走 MRCP 协议，业务编排另做。

优点：

- 企业语音体系常见，标准化较好。

缺点：

- 栈复杂，搭建成本高。
- 对“自由双向媒体流”不如 SIP/媒体分叉直观。

## 3. 最优方案建议

分两层给结论：

1. 当前工程最优（立即可落地）：路线 1，SIP 机器人。
2. 长期低延迟与 AI 深度控制最优：路线 2，mod_audio_fork（前提是你引入并稳定维护该模块）。

原因：

- 你当前仓库已有机器人 SIP 网关和拨号模板，可直接上线验证。
- mod_audio_fork 在当前仓库中还不存在源码，短期上线风险更高。

## 4. 路线 1（SIP 机器人）代码实现

你仓库已有模板可直接改：

- 机器人路由：[conf/vanilla/dialplan/default/30_ai_bot_realtime.xml](conf/vanilla/dialplan/default/30_ai_bot_realtime.xml)
- 机器人网关：[conf/vanilla/sip_profiles/external/bot_s.xml](conf/vanilla/sip_profiles/external/bot_s.xml)

### 4.1 拨号计划示例（机器人号段 75xx）

```xml
<include>
  <extension name="ai-bot-router">
    <condition field="destination_number" expression="^(75\d\d)$">
      <action application="set" data="bot_ext=$1"/>
      <action application="set" data="hangup_after_bridge=true"/>
      <action application="set" data="absolute_codec_string=PCMU,PCMA"/>
      <action application="bridge" data="sofia/gateway/bot_s/${bot_ext}"/>
    </condition>
  </extension>
</include>
```

### 4.2 SIP 网关示例（指向 S）

```xml
<include>
  <gateway name="bot_s">
    <param name="register" value="false"/>
    <param name="proxy" value="10.10.10.88:5060"/>
    <param name="from-domain" value="$${domain}"/>
    <param name="caller-id-in-from" value="true"/>
    <param name="codec-prefs" value="PCMU,PCMA"/>
    <param name="ping" value="15"/>
  </gateway>
</include>
```

### 4.3 服务器 S 最小实现要点

S 需完成：

1. 接收 INVITE 并建立 RTP。
2. 把上行 RTP 送 ASR/LLM/TTS。
3. 把生成语音以 RTP 连续回送。
4. 处理中断与 BYE 清理。

建议先固定：

- 编解码：PCMU (G.711u)
- 帧长：20ms
- 抖动缓冲：60-120ms

## 5. 路线 2（mod_audio_fork）代码实现骨架

说明：当前仓库未包含 mod_audio_fork 源码；下面是通用实施骨架。

### 5.1 FreeSWITCH 侧

- 编译并加载 mod_audio_fork。
- 在机器人呼叫建立后，启动音频分叉到 S（WebSocket/gRPC）。
- 通话结束时停止分叉并清理会话。

示例控制流程（ESL 伪代码）：

```python
# 事件：CHANNEL_ANSWER
uuid = event["Unique-ID"]
ws_url = "ws://10.10.10.88:8765/audio"

# 注意：不同 mod_audio_fork 实现命令名和参数格式会不同
esl.api(f"uuid_audio_fork {uuid} start {ws_url} mono 16000")

# 事件：CHANNEL_HANGUP_COMPLETE
esl.api(f"uuid_audio_fork {uuid} stop")
```

### 5.2 服务器 S（WebSocket）最小骨架

```python
import asyncio
import websockets

async def handle(ws):
    # 约定：上行下行均为 20ms PCM16LE 16k 单声道
    async for frame in ws:
        # frame: bytes, A 的实时音频
        # TODO: ASR -> LLM -> TTS(流式)
        # 这里先示例回环：直接回放给 A
        await ws.send(frame)

async def main():
    async with websockets.serve(handle, "0.0.0.0", 8765, max_size=None):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
```

上线前必做：

1. 抖动缓冲。
2. 重采样与格式统一。
3. 断线重连与会话清理。
4. 限流与并发隔离。

## 6. 推荐上线路径

1. 先走路线 1，上线 SIP 机器人版本（最快且稳）。
2. 在旁路环境并行验证路线 2（mod_audio_fork + WS）。
3. 路线 2 稳定后，再切主链路。

## 7. 验证清单

1. A 呼叫机器人号后，S 是否持续收到音频。
2. S 首包语音回送时间是否达到目标。
3. A 是否可连续听到机器人回复，无断裂/卡顿。
4. 挂机后，FreeSWITCH 与 S 资源是否全部释放。
5. 10/50/100 并发时 CPU、内存、时延是否稳定。
