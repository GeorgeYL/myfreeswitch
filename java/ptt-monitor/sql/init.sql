CREATE TABLE IF NOT EXISTS ptt_call_logs (
    id BIGSERIAL PRIMARY KEY,
    call_id VARCHAR(64) NOT NULL UNIQUE,
    device_id VARCHAR(64) NOT NULL,
    ip VARCHAR(64) NOT NULL,
    site SMALLINT NOT NULL,
    channel SMALLINT NOT NULL,
    room VARCHAR(128) NOT NULL,
    start_time TIMESTAMP NOT NULL,
    end_time TIMESTAMP NOT NULL,
    duration_seconds INTEGER NOT NULL,
    status VARCHAR(64) NOT NULL,
    record_file TEXT NOT NULL,
    file_size_bytes BIGINT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ptt_call_logs_end_time ON ptt_call_logs (end_time DESC);
CREATE INDEX IF NOT EXISTS idx_ptt_call_logs_room ON ptt_call_logs (room);
