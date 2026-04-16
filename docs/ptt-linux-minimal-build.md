# Linux 最小构建方案（PTT Demo）

## 1. 适用目标

该方案用于快速构建可支撑 PTT Demo 的最小 FreeSWITCH 运行集：

- SIP 接入（mod_sofia）
- 对讲混音（mod_conference）
- ESL 事件（mod_event_socket）
- XML 路由与基础音频文件能力

---

## 2. 新增文件

- `build/modules.conf.ptt.minimal`
- `build-ptt-minimal-linux.sh`
- `scripts/python/ptt_demo/run_demo_linux.sh`
- `scripts/python/ptt_demo/api_smoke_test_linux.sh`
- `scripts/python/ptt_demo/generate_bot_audio_linux.sh`

---

## 3. 依赖准备（Ubuntu/Debian 示例）

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential autoconf automake libtool pkg-config git \
  libssl-dev libcurl4-openssl-dev libpcre3-dev libspeexdsp-dev \
  libsndfile1-dev libsqlite3-dev libedit-dev libtiff-dev yasm
```

centOS 7/8 示例：

```bash
sudo yum groupinstall -y "Development Tools"

sudo yum install -y \
  autoconf automake libtool pkgconfig m4 which \
  gcc gcc-c++ make \
  openssl-devel libcurl-devel pcre-devel speexdsp-devel \
  libsndfile-devel sqlite-devel libedit-devel libtiff-devel yasm
```
CentOS 9
```bash
sudo dnf groupinstall -y "Development Tools"

sudo dnf install -y \
  autoconf automake libtool pkgconf-pkg-config m4 which \
  gcc gcc-c++ make \
  openssl-devel libcurl-devel pcre-devel speexdsp-devel \
  libsndfile-devel sqlite-devel libedit-devel libtiff-devel yasm
```

说明：不同发行版包名略有差异，可按 `./configure` 报错补齐。

---

## 4. 一键最小构建

在 FreeSWITCH 源码根目录执行：

```bash
chmod +x ./build-ptt-minimal-linux.sh
./build-ptt-minimal-linux.sh
```

常用参数：

```bash
# 指定安装目录 + 指定并行数
./build-ptt-minimal-linux.sh --prefix /usr/local/freeswitch --jobs 8

# 仅编译不安装
./build-ptt-minimal-linux.sh --skip-install

# 需要保留最小 modules.conf 供后续复用
./build-ptt-minimal-linux.sh --keep-modules-conf
```

---

## 5. 脚本行为说明

脚本会自动：

1. 备份当前 `modules.conf`（若存在）
2. 替换为 `build/modules.conf.ptt.minimal`
3. 执行 `bootstrap -> configure -> make -> make install`
4. 构建结束后自动恢复原 `modules.conf`（除非 `--keep-modules-conf`）

---

## 6. 启动与验证

### 6.1 启动 FreeSWITCH

```bash
/usr/local/freeswitch/bin/freeswitch -nc -nonat
```

### 6.2 验证 ESL 端口

```bash
ss -ltnp | grep 8021
```

预期：看到 8021 监听。

### 6.3 在 Demo 目录启动 API

```bash
cd scripts/python/ptt_demo
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
ESL_HOST=127.0.0.1 ESL_PORT=8021 ESL_PASSWORD=ClueCon FS_DOMAIN=127.0.0.1 \
  uvicorn ptt_demo_service:app --host 0.0.0.0 --port 8090
```

---

## 7. 一键总控（启动 + 8021 自检 + 冒烟测试）

在 FreeSWITCH 源码根目录执行：

```bash
chmod +x ./scripts/python/ptt_demo/run_demo_linux.sh
chmod +x ./scripts/python/ptt_demo/api_smoke_test_linux.sh
chmod +x ./scripts/python/ptt_demo/generate_bot_audio_linux.sh

./scripts/python/ptt_demo/run_demo_linux.sh
```

默认行为：

1. 检查 ESL (`127.0.0.1:8021`) 是否可达
2. 若不可达，尝试自动启动 FreeSWITCH（默认 `/usr/local/freeswitch/bin/freeswitch`）
3. 创建 Python venv 并安装依赖
4. 生成机器人语音 WAV
5. 启动 API
6. 执行 API 冒烟测试

常用参数：

```bash
# 指定 freeswitch 可执行路径
./scripts/python/ptt_demo/run_demo_linux.sh --fs-bin /opt/fs/bin/freeswitch

# 只跑一次验证，结束后退出
./scripts/python/ptt_demo/run_demo_linux.sh --once

# 仅启动 API，不自动拉起 freeswitch
./scripts/python/ptt_demo/run_demo_linux.sh --no-auto-start-fs

# 跳过冒烟测试
./scripts/python/ptt_demo/run_demo_linux.sh --no-smoke-test
```

---

## 8. 切回全量构建

如果需要完整能力（视频、ASR/TTS、更多模块），请改回默认 `modules.conf` 并使用常规全量构建流程。

---

## 9. systemd 开机自启与可管控服务

已提供文件：

- `scripts/python/ptt_demo/ptt-demo-api.service`
- `scripts/python/ptt_demo/ptt-demo-api.env.example`
- `scripts/python/ptt_demo/install_systemd_service.sh`

### 9.1 一键安装并启用

先确保已完成一次 API 启动（用于创建 `.venv`）：

```bash
./scripts/python/ptt_demo/run_demo_linux.sh --once
```

然后安装 systemd 服务：

```bash
chmod +x ./scripts/python/ptt_demo/install_systemd_service.sh
sudo ./scripts/python/ptt_demo/install_systemd_service.sh
```

脚本会自动：

1. 安装 unit 到 `/etc/systemd/system/ptt-demo-api.service`
2. 首次创建环境变量文件 `/etc/default/ptt-demo-api`
3. 执行 `systemctl daemon-reload`
4. 执行 `systemctl enable --now ptt-demo-api.service`

### 9.2 日常运维命令

```bash
sudo systemctl status ptt-demo-api.service
sudo systemctl restart ptt-demo-api.service
sudo systemctl stop ptt-demo-api.service
sudo journalctl -u ptt-demo-api.service -f
```

### 9.3 常见自定义

1. 修改运行用户/组：
  `sudo ./scripts/python/ptt_demo/install_systemd_service.sh --user <user> --group <group>`
2. 指定工作目录（非默认源码路径）：
  `sudo ./scripts/python/ptt_demo/install_systemd_service.sh --workdir /path/to/scripts/python/ptt_demo`
3. 仅安装不立即启用：
  `sudo ./scripts/python/ptt_demo/install_systemd_service.sh --no-enable`