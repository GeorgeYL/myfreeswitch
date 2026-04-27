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
CONF_SUBCLASS = "conference::maintenance"
PTT_FLOOR_REQUEST_DIGIT = "9"
PTT_FLOOR_RELEASE_DIGIT = "0"


class BotReplyRequest(BaseModel):
    site: int = Field(ge=1, le=4)
    channel: int = Field(ge=1, le=4)
    question: str = ""


class FloorControlRequest(BaseModel):
    call_id: str = Field(min_length=8)


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
        self.room_members: Dict[str, Dict[str, str]] = {}
        self.member_to_call: Dict[str, Dict[str, str]] = {}
        self.room_floor: Dict[str, Dict[str, str]] = {}
        self.logs: List[Dict[str, str]] = []
        self.max_logs = 5000
        self.floor_timeout_seconds = max(3, int(os.getenv("PTT_FLOOR_TIMEOUT_SECONDS", "10")))
        self.lock = threading.Lock()

        self.bot_answers = {
            "1": "qa_schedule.wav",
            "2": "qa_safety.wav",
            "3": "qa_help.wav",
            "default": "qa_default.wav",
        }

    @staticmethod
    def _floor_expires_at(now_ts: float, timeout_seconds: int) -> str:
        return str(int(now_ts + timeout_seconds))

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

    def room_and_member_by_call(self, call_id: str) -> tuple:
        with self.lock:
            m = self.member_to_call.get(call_id)
            if not m:
                return "", ""
            return m.get("room", ""), m.get("member_id", "")

    def room_from_active_call(self, call_id: str) -> Optional[str]:
        with self.lock:
            active = self.active_calls.get(call_id)
            if not active:
                return None
            return active.get("room")

    def add_conference_member(self, room: str, call_id: str, member_id: str) -> None:
        if not room or not call_id or not member_id:
            return
        with self.lock:
            members = self.room_members.setdefault(room, {})
            members[call_id] = member_id
            self.member_to_call[call_id] = {"room": room, "member_id": member_id}

    def remove_conference_member(self, room: str, call_id: str, member_id: str) -> bool:
        if not room:
            return False
        floor_released = False
        with self.lock:
            if call_id:
                self.member_to_call.pop(call_id, None)
            members = self.room_members.get(room, {})
            if call_id in members:
                members.pop(call_id, None)
            elif member_id:
                for cid, mid in list(members.items()):
                    if mid == member_id:
                        members.pop(cid, None)
                        self.member_to_call.pop(cid, None)
                        call_id = cid
                        break

            if not members:
                self.room_members.pop(room, None)

            active_floor = self.room_floor.get(room)
            if active_floor and call_id and active_floor.get("call_id") == call_id:
                self.room_floor.pop(room, None)
                floor_released = True

        return floor_released

    def release_floor_for_call(self, call_id: str, reason: str = "manual") -> Dict[str, str]:
        with self.lock:
            active = self.active_calls.get(call_id, {})
            room = active.get("room", "") or self.member_to_call.get(call_id, {}).get("room", "")
            if not room:
                return {"result": "not_found", "call_id": call_id}

            active_floor = self.room_floor.get(room)
            if not active_floor:
                return {"result": "idle", "room": room, "call_id": call_id}

            if active_floor.get("call_id") != call_id:
                return {
                    "result": "not_holder",
                    "room": room,
                    "call_id": call_id,
                    "holder_call_id": active_floor.get("call_id", ""),
                }

            self.room_floor.pop(room, None)
            return {"result": "released", "room": room, "call_id": call_id, "reason": reason}

    def request_floor_for_call(self, call_id: str, now_ts: Optional[float] = None) -> Dict[str, str]:
        now_ts = now_ts or time.time()
        with self.lock:
            active = self.active_calls.get(call_id)
            if not active:
                return {"result": "call_not_found", "call_id": call_id}

            room = active.get("room", "")
            if not room:
                return {"result": "room_not_found", "call_id": call_id}

            current = self.room_floor.get(room)
            if current:
                expires_at = int(current.get("expires_at_ts", "0") or "0")
                if expires_at <= int(now_ts):
                    self.room_floor.pop(room, None)
                    current = None

            if current:
                if current.get("call_id") == call_id:
                    current["expires_at_ts"] = self._floor_expires_at(now_ts, self.floor_timeout_seconds)
                    return {
                        "result": "renewed",
                        "room": room,
                        "call_id": call_id,
                        "expires_at_ts": current["expires_at_ts"],
                    }
                return {
                    "result": "busy",
                    "room": room,
                    "call_id": call_id,
                    "holder_call_id": current.get("call_id", ""),
                    "expires_at_ts": current.get("expires_at_ts", ""),
                }

            self.room_floor[room] = {
                "call_id": call_id,
                "expires_at_ts": self._floor_expires_at(now_ts, self.floor_timeout_seconds),
            }
            return {
                "result": "granted",
                "room": room,
                "call_id": call_id,
                "expires_at_ts": self.room_floor[room]["expires_at_ts"],
            }

    def expire_floors(self, now_ts: Optional[float] = None) -> List[str]:
        now_ts = now_ts or time.time()
        changed_rooms: List[str] = []
        with self.lock:
            for room, state in list(self.room_floor.items()):
                expires_at = int(state.get("expires_at_ts", "0") or "0")
                if expires_at <= int(now_ts):
                    self.room_floor.pop(room, None)
                    changed_rooms.append(room)
        return changed_rooms

    def room_floor_holder(self, room: str) -> str:
        with self.lock:
            floor = self.room_floor.get(room)
            if not floor:
                return ""
            return floor.get("call_id", "")

    def room_member_ids(self, room: str) -> Dict[str, str]:
        with self.lock:
            return dict(self.room_members.get(room, {}))

    def ptt_state_by_room(self, room: str) -> Dict[str, str]:
        with self.lock:
            floor = self.room_floor.get(room, {})
            members = self.room_members.get(room, {})
            return {
                "room": room,
                "holder_call_id": floor.get("call_id", ""),
                "expires_at_ts": floor.get("expires_at_ts", ""),
                "member_count": str(len(members)),
            }

    def ptt_state_all(self) -> List[Dict[str, str]]:
        with self.lock:
            rooms = sorted(set(self.room_members.keys()) | set(self.room_floor.keys()))
        return [self.ptt_state_by_room(room) for room in rooms]

    def find_recent_by_call(self, call_id: str) -> Optional[Dict[str, str]]:
        with self.lock:
            for item in reversed(self.logs):
                if item["call_id"] == call_id:
                    return dict(item)
        return None

    def all_logs(self) -> List[Dict[str, str]]:
        with self.lock:
            return [dict(item) for item in self.logs]

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
        t_events = threading.Thread(target=self._event_loop, daemon=True)
        t_events.start()
        t_floor = threading.Thread(target=self._floor_watchdog_loop, daemon=True)
        t_floor.start()

    def _esl_api(self, command: str) -> str:
        try:
            return self.esl_api.api(command)
        except Exception:
            self.esl_api.connect()
            return self.esl_api.api(command)

    def _conference_member_mute(self, room: str, member_id: str, mute: bool) -> str:
        action = "mute" if mute else "unmute"
        cmd = f"conference {room} {action} {member_id}"
        return self._esl_api(cmd)

    def _sync_room_floor_policy(self, room: str) -> None:
        members = self.state.room_member_ids(room)
        holder_call_id = self.state.room_floor_holder(room)
        for call_id, member_id in members.items():
            should_mute = call_id != holder_call_id
            try:
                self._conference_member_mute(room=room, member_id=member_id, mute=should_mute)
            except Exception:
                continue

    def _floor_watchdog_loop(self) -> None:
        while not self.stop_event.is_set():
            changed_rooms = self.state.expire_floors()
            for room in changed_rooms:
                self._sync_room_floor_policy(room)
            time.sleep(1)

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
                    call_id = event.get("Unique-ID", "")
                    self.state.on_hangup(event)
                    if call_id:
                        release = self.state.release_floor_for_call(call_id=call_id, reason="hangup")
                        room = release.get("room", "")
                        if room:
                            self._sync_room_floor_policy(room)
                elif name == "DTMF":
                    self._on_dtmf(event)
                elif name == "CUSTOM":
                    self._on_custom(event)
            except Exception:
                time.sleep(1)
                try:
                    self.esl_events.connect()
                except Exception:
                    time.sleep(2)

    def _on_custom(self, event: Dict[str, str]) -> None:
        if event.get("Event-Subclass", "") != CONF_SUBCLASS:
            return
        action = (event.get("Action", "") or "").lower()
        room = event.get("Conference-Name", "")
        call_id = event.get("Unique-ID", "") or event.get("Caller-Unique-ID", "")
        member_id = event.get("Member-ID", "")
        if action == "add-member":
            self.state.add_conference_member(room=room, call_id=call_id, member_id=member_id)
            self._sync_room_floor_policy(room)
        elif action in ("del-member", "remove-member"):
            released = self.state.remove_conference_member(room=room, call_id=call_id, member_id=member_id)
            if released or room:
                self._sync_room_floor_policy(room)

    def _request_floor(self, call_id: str) -> Dict[str, str]:
        result = self.state.request_floor_for_call(call_id=call_id)
        room = result.get("room", "")
        if room and result.get("result") in ("granted", "renewed"):
            self._sync_room_floor_policy(room)
        return result

    def _release_floor(self, call_id: str, reason: str = "manual") -> Dict[str, str]:
        result = self.state.release_floor_for_call(call_id=call_id, reason=reason)
        room = result.get("room", "")
        if room and result.get("result") == "released":
            self._sync_room_floor_policy(room)
        return result

    def _on_dtmf(self, event: Dict[str, str]) -> None:
        digit = event.get("DTMF-Digit", "")
        call_id = event.get("Unique-ID", "")

        if digit == PTT_FLOOR_REQUEST_DIGIT and call_id:
            self._request_floor(call_id=call_id)
            return

        if digit == PTT_FLOOR_RELEASE_DIGIT and call_id:
            self._release_floor(call_id=call_id, reason="dtmf")
            return

        if digit not in ("1", "2", "3"):
            return
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
        return self._esl_api(cmd)


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


@app.get("/api/ptt/state")
def ptt_state() -> List[Dict[str, str]]:
    return service.state.ptt_state_all()


@app.get("/api/ptt/state/{site}/{channel}")
def ptt_state_by_room(site: int, channel: int) -> Dict[str, str]:
    if site < 1 or site > 4 or channel < 1 or channel > 4:
        raise HTTPException(status_code=400, detail="site/channel out of range")
    room = service.room_name(site=site, channel=channel)
    return service.state.ptt_state_by_room(room=room)


@app.post("/api/ptt/floor/request")
def ptt_floor_request(req: FloorControlRequest) -> Dict[str, str]:
    result = service._request_floor(call_id=req.call_id)
    if result.get("result") in ("call_not_found", "room_not_found"):
        raise HTTPException(status_code=404, detail=result)
    return result


@app.post("/api/ptt/floor/release")
def ptt_floor_release(req: FloorControlRequest) -> Dict[str, str]:
    result = service._release_floor(call_id=req.call_id, reason="api")
    if result.get("result") == "not_found":
        raise HTTPException(status_code=404, detail=result)
    return result
