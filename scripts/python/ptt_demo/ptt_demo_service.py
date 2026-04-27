import datetime as dt
import os
import re
import socket
import threading
import time
from pathlib import Path
from typing import Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field


DEST_RE = re.compile(r"^7([1-4])([1-4])$")


class BotReplyRequest(BaseModel):
    site: int = Field(ge=1, le=4)
    channel: int = Field(ge=1, le=4)
    question: str = ""


class EslClient:
    def __init__(self, host: str, port: int, password: str):
        self.host = host
        self.port = port
        self.password = password
        self.sock: Optional[socket.socket] = None
        self.lock = threading.Lock()
        self.running = False
        self.buffer = b""

    def connect(self) -> None:
        self.sock = socket.create_connection((self.host, self.port), timeout=8)
        self.sock.settimeout(2)
        self._read_until_auth_request()
        self._send_command(f"auth {self.password}")
        self._read_command_reply(expect_ok=True)
        self._send_command("event plain CHANNEL_ANSWER CHANNEL_HANGUP_COMPLETE DTMF CUSTOM")
        self._read_command_reply(expect_ok=True)

    def _read_until_auth_request(self) -> None:
        deadline = time.time() + 8
        while time.time() < deadline:
            frame = self._recv_frame()
            if not frame:
                continue
            headers = frame[0]
            if headers.get("Content-Type") == "auth/request":
                return
        raise RuntimeError("Timeout waiting for ESL auth/request")

    def _send_command(self, command: str) -> None:
        assert self.sock is not None
        payload = f"{command}\n\n".encode("utf-8")
        self.sock.sendall(payload)

    def _read_command_reply(self, expect_ok: bool = True) -> str:
        deadline = time.time() + 8
        while time.time() < deadline:
            frame = self._recv_frame()
            if not frame:
                continue
            headers, body = frame
            ctype = headers.get("Content-Type", "")
            if ctype == "command/reply":
                reply = headers.get("Reply-Text", body.strip())
                if expect_ok and not str(reply).startswith("+OK"):
                    raise RuntimeError(f"Unexpected ESL reply: {reply}")
                return str(reply)
        raise RuntimeError("Timeout waiting command/reply")

    def api(self, command: str) -> str:
        with self.lock:
            self._send_command(f"api {command}")
            deadline = time.time() + 10
            while time.time() < deadline:
                frame = self._recv_frame()
                if not frame:
                    continue
                headers, body = frame
                ctype = headers.get("Content-Type", "")
                if ctype == "api/response":
                    return body.strip()
                if ctype == "command/reply":
                    continue
            raise RuntimeError("Timeout waiting api/response")

    def read_event(self) -> Optional[Dict[str, str]]:
        frame = self._recv_frame()
        if not frame:
            return None
        headers, body = frame
        ctype = headers.get("Content-Type", "")
        if ctype != "text/event-plain":
            return None
        return self._parse_key_values(body)

    def _recv_frame(self) -> Optional[tuple]:
        assert self.sock is not None
        while True:
            parsed = self._try_parse_frame_from_buffer()
            if parsed is not None:
                return parsed
            try:
                chunk = self.sock.recv(65535)
            except socket.timeout:
                return None
            if not chunk:
                raise RuntimeError("ESL socket closed")
            self.buffer += chunk

    def _try_parse_frame_from_buffer(self) -> Optional[tuple]:
        for sep in (b"\n\n", b"\r\n\r\n"):
            pos = self.buffer.find(sep)
            if pos == -1:
                continue
            raw_header = self.buffer[:pos].decode("utf-8", errors="replace")
            headers = self._parse_key_values(raw_header)
            body_start = pos + len(sep)
            content_length = int(headers.get("Content-Length", "0") or "0")
            total_len = body_start + content_length
            if len(self.buffer) < total_len:
                return None
            body = self.buffer[body_start:total_len].decode("utf-8", errors="replace")
            self.buffer = self.buffer[total_len:]
            return headers, body
        return None

    @staticmethod
    def _parse_key_values(data: str) -> Dict[str, str]:
        result: Dict[str, str] = {}
        for line in data.splitlines():
            if not line or ":" not in line:
                continue
            k, v = line.split(":", 1)
            result[k.strip()] = v.strip()
        return result


class PttState:
    def __init__(self, recordings_root: str, bot_audio_dir: str):
        self.recordings_root = recordings_root
        self.bot_audio_dir = Path(bot_audio_dir)
        self.active_calls: Dict[str, Dict[str, str]] = {}
        self.logs: List[Dict[str, str]] = []
        self.max_logs = 5000
        self.lock = threading.Lock()

        self.bot_answers = {
            "1": "qa_schedule.wav",
            "2": "qa_safety.wav",
            "3": "qa_help.wav",
            "default": "qa_default.wav",
        }

    def _fmt_time(self, ts_micro: Optional[str]) -> str:
        if not ts_micro:
            return dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        try:
            ts = int(ts_micro) / 1_000_000
            return dt.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M:%S")
        except Exception:
            return dt.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def on_answer(self, event: Dict[str, str]) -> None:
        destination = event.get("Caller-Destination-Number") or event.get("variable_destination_number", "")
        match = DEST_RE.match(destination)
        ptt_room = event.get("variable_ptt_room", "")

        if not match and not ptt_room:
            return

        site = event.get("variable_ptt_site") or (match.group(1) if match else "")
        channel = event.get("variable_ptt_channel") or (match.group(2) if match else "")
        room = ptt_room or f"ptt_s{site}_c{channel}@{event.get('variable_domain_name', '127.0.0.1')}"
        call_id = event.get("Unique-ID", "")
        if not call_id:
            return

        started_at = self._fmt_time(event.get("Event-Date-Timestamp"))
        caller_num = event.get("Caller-Caller-ID-Number") or event.get("variable_sip_from_user") or "unknown"
        ip_addr = event.get("Caller-Network-Addr") or event.get("variable_sip_network_ip") or ""
        record_file = event.get("variable_ptt_record_file") or ""

        with self.lock:
            self.active_calls[call_id] = {
                "call_id": call_id,
                "device_id": caller_num,
                "ip": ip_addr,
                "site": str(site),
                "channel": str(channel),
                "room": room,
                "start_time": started_at,
                "record_file": record_file,
            }

    def on_hangup(self, event: Dict[str, str]) -> None:
        call_id = event.get("Unique-ID", "")
        if not call_id:
            return

        with self.lock:
            active = self.active_calls.pop(call_id, None)
        if not active:
            return

        end_time = self._fmt_time(event.get("Event-Date-Timestamp"))
        start_dt = dt.datetime.strptime(active["start_time"], "%Y-%m-%d %H:%M:%S")
        end_dt = dt.datetime.strptime(end_time, "%Y-%m-%d %H:%M:%S")
        duration = max(0, int((end_dt - start_dt).total_seconds()))

        record_file = active.get("record_file", "")
        file_size = 0
        if record_file and os.path.exists(record_file):
            file_size = os.path.getsize(record_file)

        cause = event.get("Hangup-Cause", "NORMAL_CLEARING")
        status = "NORMAL_END" if cause == "NORMAL_CLEARING" else cause

        item = {
            "seq": "",
            "call_id": call_id,
            "device_id": active.get("device_id", ""),
            "ip": active.get("ip", ""),
            "site": active.get("site", ""),
            "channel": active.get("channel", ""),
            "start_time": active.get("start_time", ""),
            "end_time": end_time,
            "duration_seconds": str(duration),
            "status": status,
            "record_file": record_file,
            "file_size_bytes": str(file_size),
            "room": active.get("room", ""),
        }

        with self.lock:
            self.logs.append(item)
            if len(self.logs) > self.max_logs:
                self.logs = self.logs[-self.max_logs :]
            for i, log in enumerate(self.logs, start=1):
                log["seq"] = str(i)

    def find_recent_by_call(self, call_id: str) -> Optional[Dict[str, str]]:
        with self.lock:
            for item in reversed(self.logs):
                if item["call_id"] == call_id:
                    return dict(item)
        return None

    def all_logs(self) -> List[Dict[str, str]]:
        with self.lock:
            return [dict(item) for item in self.logs]

    def room_from_active_call(self, call_id: str) -> Optional[str]:
        with self.lock:
            active = self.active_calls.get(call_id)
            if not active:
                return None
            return active.get("room")

    def answer_file_for_question(self, question: str) -> str:
        q = (question or "").lower()
        if "schedule" in q or "arrange" in q or "plan" in q:
            return self.bot_answers["1"]
        if "safe" in q or "security" in q or "risk" in q:
            return self.bot_answers["2"]
        if "help" in q or "support" in q or "assist" in q:
            return self.bot_answers["3"]
        return self.bot_answers["default"]


class DemoService:
    def __init__(self):
        self.esl_host = os.getenv("ESL_HOST", "127.0.0.1")
        self.esl_port = int(os.getenv("ESL_PORT", "8021"))
        self.esl_password = os.getenv("ESL_PASSWORD", "ClueCon")
        self.fs_domain = os.getenv("FS_DOMAIN", "127.0.0.1")

        recordings_root = os.getenv("RECORDINGS_DIR", "C:/freeswitch/recordings")
        bot_audio_dir = os.getenv("BOT_AUDIO_DIR", str(Path(__file__).with_name("bot_audio")))

        self.state = PttState(recordings_root=recordings_root, bot_audio_dir=bot_audio_dir)
        self.esl_events = EslClient(self.esl_host, self.esl_port, self.esl_password)
        self.esl_api = EslClient(self.esl_host, self.esl_port, self.esl_password)
        self.stop_event = threading.Event()

    def start(self) -> None:
        self.esl_events.connect()
        self.esl_api.connect()
        t = threading.Thread(target=self._event_loop, daemon=True)
        t.start()

    def _event_loop(self) -> None:
        while not self.stop_event.is_set():
            try:
                event = self.esl_events.read_event()
                if not event:
                    continue
                name = event.get("Event-Name", "")
                if name == "CHANNEL_ANSWER":
                    self.state.on_answer(event)
                elif name == "CHANNEL_HANGUP_COMPLETE":
                    self.state.on_hangup(event)
                elif name == "DTMF":
                    self._on_dtmf(event)
            except Exception:
                time.sleep(1)
                try:
                    self.esl_events.connect()
                except Exception:
                    time.sleep(2)

    def _on_dtmf(self, event: Dict[str, str]) -> None:
        digit = event.get("DTMF-Digit", "")
        if digit not in ("1", "2", "3"):
            return
        call_id = event.get("Unique-ID", "")
        room = self.state.room_from_active_call(call_id)
        if not room:
            return
        answer_file = self.state.bot_audio_dir / self.state.bot_answers[digit]
        if answer_file.exists():
            self.broadcast_file(room=room, file_path=str(answer_file))

    def room_name(self, site: int, channel: int, domain: Optional[str] = None) -> str:
        target_domain = domain or self.fs_domain
        return f"ptt_s{site}_c{channel}@{target_domain}"

    def broadcast_file(self, room: str, file_path: str) -> str:
        cmd = f"conference {room} play {file_path}"
        try:
            return self.esl_api.api(cmd)
        except Exception:
            self.esl_api.connect()
            return self.esl_api.api(cmd)


service = DemoService()
app = FastAPI(title="PTT Training Demo API", version="1.0.0")


@app.on_event("startup")
def _startup() -> None:
    service.start()


@app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@app.get("/api/logs")
def logs() -> List[Dict[str, str]]:
    return service.state.all_logs()


@app.get("/api/logs/{call_id}")
def log_by_call_id(call_id: str) -> Dict[str, str]:
    item = service.state.find_recent_by_call(call_id)
    if not item:
        raise HTTPException(status_code=404, detail="call log not found")
    return item


@app.get("/api/recordings/{call_id}")
def get_recording(call_id: str):
    item = service.state.find_recent_by_call(call_id)
    if not item:
        raise HTTPException(status_code=404, detail="call log not found")

    path = item.get("record_file", "")
    if not path or not os.path.exists(path):
        raise HTTPException(status_code=404, detail="record file not found")

    filename = os.path.basename(path)
    return FileResponse(path=path, filename=filename, media_type="audio/wav")


@app.post("/api/bot/reply")
def bot_reply(req: BotReplyRequest) -> Dict[str, str]:
    answer_name = service.state.answer_file_for_question(req.question)
    answer_file = service.state.bot_audio_dir / answer_name
    if not answer_file.exists():
        raise HTTPException(status_code=400, detail=f"missing bot audio file: {answer_file}")

    room = service.room_name(req.site, req.channel)
    result = service.broadcast_file(room=room, file_path=str(answer_file))

    return {
        "room": room,
        "question": req.question,
        "answer_file": str(answer_file),
        "freeswitch_result": result,
    }
