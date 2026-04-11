# FreeSWITCH Windows 最小必编清单（面向 PTT Demo）

## 1. 目标

目标是先跑通以下能力，再做全量编译：

- SIP 注册与呼叫
- conference 分组对讲
- event socket 日志采集
- dialplan 路由与录音

适用场景：当前对讲培训 Demo（7xy 路由、日志 API、机器人播报）。

---

## 2. Visual Studio 配置

建议配置：

- Configuration: Release
- Platform: x64

启动项目建议：

- FreeSwitchConsole（控制台启动 FreeSWITCH）

路径：

- [w32/Console/FreeSwitchConsole.2017.vcxproj](w32/Console/FreeSwitchConsole.2017.vcxproj)

---

## 3. 最小必编模块（先编这些）

### 3.1 核心启动

- FreeSwitchCore
- FreeSwitchConsole

路径：

- [w32/Library/FreeSwitchCore.2017.vcxproj](w32/Library/FreeSwitchCore.2017.vcxproj)
- [w32/Console/FreeSwitchConsole.2017.vcxproj](w32/Console/FreeSwitchConsole.2017.vcxproj)

### 3.2 PTT Demo 必需模块

- mod_sofia（SIP 终端接入）
- mod_conference（信道隔离与组内混音）
- mod_event_socket（ESL 实时事件）
- mod_dialplan_xml（XML 路由）
- mod_dptools（record_session 等常用应用）
- mod_commands（基础命令能力）
- mod_native_file（本地文件读写）
- mod_sndfile（录音/音频文件处理）
- mod_loopback（建议保留，兼容性好）
- mod_opus（建议保留，终端常用）

路径：

- [src/mod/endpoints/mod_sofia/mod_sofia.2017.vcxproj](src/mod/endpoints/mod_sofia/mod_sofia.2017.vcxproj)
- [src/mod/applications/mod_conference/mod_conference.2017.vcxproj](src/mod/applications/mod_conference/mod_conference.2017.vcxproj)
- [src/mod/event_handlers/mod_event_socket/mod_event_socket.2017.vcxproj](src/mod/event_handlers/mod_event_socket/mod_event_socket.2017.vcxproj)
- [src/mod/dialplans/mod_dialplan_xml/mod_dialplan_xml.2017.vcxproj](src/mod/dialplans/mod_dialplan_xml/mod_dialplan_xml.2017.vcxproj)
- [src/mod/applications/mod_dptools/mod_dptools.2017.vcxproj](src/mod/applications/mod_dptools/mod_dptools.2017.vcxproj)
- [src/mod/applications/mod_commands/mod_commands.2017.vcxproj](src/mod/applications/mod_commands/mod_commands.2017.vcxproj)
- [src/mod/formats/mod_native_file/mod_native_file.2017.vcxproj](src/mod/formats/mod_native_file/mod_native_file.2017.vcxproj)
- [src/mod/formats/mod_sndfile/mod_sndfile.2017.vcxproj](src/mod/formats/mod_sndfile/mod_sndfile.2017.vcxproj)
- [src/mod/endpoints/mod_loopback/mod_loopback.2017.vcxproj](src/mod/endpoints/mod_loopback/mod_loopback.2017.vcxproj)
- [src/mod/codecs/mod_opus/mod_opus.2017.vcxproj](src/mod/codecs/mod_opus/mod_opus.2017.vcxproj)

---

## 4. 建议先禁用的模块（加速首编）

这批模块与当前 PTT Demo 无直接关系，可先不编：

- ASR/TTS：mod_unimrcp、mod_pocketsphinx、mod_flite、mod_cepstral
- 视频相关：mod_av、mod_h26x、mod_v8
- 非本次协议：mod_rtmp、mod_h323、mod_skinny、mod_dingaling
- 外部集成类：mod_xml_curl、mod_xml_cdr、mod_amqp

说明：后续需要相关能力时再逐个启用即可。

---

## 5. 最短编译路径（命令行）

在仓库根目录执行：

```powershell
.\Freeswitch.2017.sln.bat Release x64
```

该脚本会调用：

- [msbuild.cmd](msbuild.cmd)

## 5.1 推荐使用最小解决方案筛选文件

已提供仅包含 PTT 必需项目的筛选文件：

- [Freeswitch.PTT.Minimal.2017.slnf](Freeswitch.PTT.Minimal.2017.slnf)

使用方式：

1. 在 Visual Studio 直接打开该 `.slnf`。
2. 选择 `Release | x64`。
3. 执行 Build Solution。

说明：

- 该 `.slnf` 适合快速验证 PTT Demo。
- 若后续要打完整安装包或验证其他模块，请切回完整 [Freeswitch.2017.sln](Freeswitch.2017.sln)。

### 5.2 命令行一键构建（新增）

已提供脚本：

- [build-ptt-minimal.cmd](build-ptt-minimal.cmd)

用法：

```cmd
build-ptt-minimal.cmd
build-ptt-minimal.cmd Debug x64
build-ptt-minimal.cmd Release Win32
```

构建日志输出示例：

- `ptt-minimal-x64-Release.log`

---

## 6. 首次启动与验证

### 6.1 启动 FreeSWITCH

- 在 VS 中将 FreeSwitchConsole 设为启动项目并运行。

### 6.2 验证 ESL 端口

```powershell
Test-NetConnection 127.0.0.1 -Port 8021
```

预期：

- TcpTestSucceeded = True

### 6.3 验证 Demo 服务

在目录 scripts/python/ptt_demo 执行：

```powershell
.\run_demo.ps1 -FsDomain 127.0.0.1
```

---

## 7. 常见耗时点与建议

- 首次依赖下载会慢：属于正常现象。
- 防病毒软件会拖慢链接阶段：可将构建输出目录加入白名单。
- 若你只做 Demo，不要一开始编所有模块。

---

## 8. 何时切回全量编译

满足任一条件时建议全量：

- 进入交付测试阶段
- 需要验证更多编解码或协议
- 需要打完整安装包