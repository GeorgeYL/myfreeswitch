# FreeSWITCH 机器人实时语音链路方案（A 呼叫 B=机器人）

## 1. 目标

你现在已有能力：

- A 可以呼叫 B（普通 SIP 分机）
- 内网环境稳定

新增目标：

- 当 A 呼叫机器人 B 时，把 A 的实时上行音频送到服务器 S
- 服务器 S 实时处理（ASR/LLM/TTS 或其他）
- 服务器 S 把实时下行音频回送，A 可以实时听到

本质是一个双向实时媒体问题：

- 上行：A -> FreeSWITCH -> S
- 下行：S -> FreeSWITCH -> A

## 2. 技术路线总览

### 路线 1：S 作为 SIP 机器人终端（推荐）

实现方式：

- FreeSWITCH 侧把机器人号码路由到一个 SIP Gateway（目标是服务器 S）
- S 作为 SIP UA/B2BUA/媒体服务，直接收 RTP（A 的语音）并回 RTP（机器人语音）

优点：

- 最贴合 FreeSWITCH 原生模型，改动最小
- 双向实时天然成立（同一 SIP 会话中的双向 RTP）
- 时延低、稳定性高、便于生产运维
- 不需要在 FreeSWITCH 内做复杂媒体二次开发

缺点：

- 服务器 S 需要具备 SIP/RTP 能力（或加一个 SIP 适配层）
- 需要处理编解码协商（PCMU/PCMA/OPUS 等）

适用场景：

- 你可以控制服务器 S，愿意让它支持 SIP
- 目标是尽快上线且长期稳定

### 路线 2：FreeSWITCH 媒体分叉（Media Bug/Fork）到 S（WebSocket/TCP/UDP）

实现方式：

- 在通话通道上挂 media bug，把入向音频帧实时推送给 S
- 将 S 返回的音频帧再注入通话（或替换播放）

优点：

- S 可以只暴露 WebSocket/gRPC，不必支持 SIP
- 可深度定制（VAD、降噪、打断、Barge-in）

缺点：

- 需要依赖额外模块（例如第三方 mod_audio_fork）或自研 C 模块
- 在 Windows 构建和维护成本高
- 时钟抖动、重采样、回声路径处理复杂

适用场景：

- S 明确不支持 SIP
- 团队能承担 FreeSWITCH 媒体开发/维护

### 路线 3：ESL 控制 + 分段播放（非严格实时）

实现方式：

- A 语音录制分段上传到 S
- S 生成分段音频，FreeSWITCH 用 playback/conference play 播放

优点：

- 现有 ESL 服务可以快速改造
- 实现难度低

缺点：

- 不是严格实时对话，交互迟滞明显
- 用户体验接近“按句问答”，不是自然通话

适用场景：

- 先做 PoC，验证业务逻辑
- 对实时性要求不高

### 路线 4：MRCP（ASR/TTS）能力接入

实现方式：

- 使用 mod_unimrcp 与 MRCP Server 对接 ASR/TTS
- 由外部对话服务编排识别结果与合成结果

优点：

- 语音能力标准化，企业语音平台常见

缺点：

- 需要搭建 MRCP 体系，工程复杂度较高
- 适合 ASR/TTS，不是最直接的“自由双向媒体流”接口

适用场景：

- 已有 MRCP 能力栈
- 组织内已有语音中台

## 3. 选型结论（最佳方案）

最佳方案：路线 1（S 作为 SIP 机器人终端）。

理由：

- 你的现状已经是 FreeSWITCH SIP 通话系统，直接扩展最顺滑
- 不必动 FreeSWITCH 底层媒体代码，风险最小
- 双向实时媒体天然满足需求，时延和稳定性最好

仅当 S 无法支持 SIP 时，才建议走路线 2。

## 4. 参考时延预算

以内网为例，一个可接受预算：

- A 到 FreeSWITCH RTP：10-30 ms
- FreeSWITCH 到 S RTP：10-30 ms
- S 处理（VAD+ASR+LLM+TTS 首包）：150-400 ms
- S 回 FreeSWITCH RTP：10-30 ms
- FreeSWITCH 到 A RTP：10-30 ms

首包可听时间通常在 250-600 ms 区间，优化目标是小于 400 ms。

## 5. 路线 1 实施步骤（可落地）

### 5.1 FreeSWITCH 侧

1. 新增一个外部网关（指向服务器 S 的 SIP 服务）。
2. 新增一个机器人拨号规则（例如 75xx），命中后 bridge 到该网关。
3. 设置编解码优先级，建议先用 PCMU/PCMA 起步。
4. 开启 RTP 抓包与日志观察，验证双向流。

### 5.2 服务器 S 侧

1. 提供 SIP 监听（UDP/TCP/TLS 按需）。
2. 接收 INVITE，建立 RTP 会话。
3. 上行 RTP 送入识别与对话引擎。
4. 生成的 TTS 音频打包 RTP 回送。
5. 支持会话中断、重入、超时与 BYE 清理。

## 6. 仓库内已给出的配置模板

已新增以下文件：

- conf/vanilla/sip_profiles/external/bot_s.xml
- conf/vanilla/dialplan/default/30_ai_bot_realtime.xml

含义：

- 号码 75xx 进入机器人路由
- 默认把呼叫桥接到网关 bot_s，对端目标形如 sip:75xx@10.10.10.88:5060

请按你的环境修改：

- 服务器 S 地址
- 用户名密码（若 S 要注册鉴权）
- 编解码策略

## 7. 路线 2 的工程建议（当 S 不能做 SIP）

建议做一个独立媒体桥接服务：

- FreeSWITCH 通道 media fork -> Bridge Service（PCM16 16k，20ms 帧）
- Bridge Service <-> S（WebSocket/gRPC）
- Bridge Service -> FreeSWITCH（回注音频）

关键点：

- 统一帧长（20ms）
- 抖动缓冲（60-120ms）
- 双向重采样（8k/16k/48k）
- 回声抑制与打断策略

## 8. 验证清单

- A 拨机器人号码后，S 是否收到持续 RTP 上行
- S 生成首包音频后，A 是否在目标时延内听到
- 双方静音和打断是否符合预期
- BYE 后资源是否完全释放
- 并发 10/50/100 路时是否稳定

## 9. 风险与规避

- 编解码不一致：先固定 PCMU，再扩展 OPUS
- NAT/对称 RTP 问题：内网先跑通，再引入 SBC
- 回声与啸叫：优先耳机终端，启用 AEC/VAD
- 机器人首包慢：做流式 TTS 与分片回放

## 10. 推荐推进顺序

1. 先用路线 1 跑通端到端最小链路（S 先回固定语音）。
2. 接入流式 ASR/LLM/TTS，优化首包。
3. 加入打断、并发控制、观测指标。
4. 视需要再评估路线 2 的深度定制。