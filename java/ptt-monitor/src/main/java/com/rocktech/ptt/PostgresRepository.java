package com.rocktech.ptt;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

public final class PostgresRepository {
    private final Config config;

    public PostgresRepository(Config config) {
        this.config = config;
    }

    public void initSchema() throws SQLException {
        try (Connection conn = open(); Statement st = conn.createStatement()) {
            st.executeUpdate("""
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
                    )
                    """);
            st.executeUpdate("CREATE INDEX IF NOT EXISTS idx_ptt_call_logs_end_time ON ptt_call_logs (end_time DESC)");
            st.executeUpdate("CREATE INDEX IF NOT EXISTS idx_ptt_call_logs_room ON ptt_call_logs (room)");
        }
    }

    public void upsert(CallLogRecord record) throws SQLException {
        String sql = """
                INSERT INTO ptt_call_logs (
                    call_id, device_id, ip, site, channel, room,
                    start_time, end_time, duration_seconds, status,
                    record_file, file_size_bytes
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT (call_id) DO UPDATE SET
                    device_id = EXCLUDED.device_id,
                    ip = EXCLUDED.ip,
                    site = EXCLUDED.site,
                    channel = EXCLUDED.channel,
                    room = EXCLUDED.room,
                    start_time = EXCLUDED.start_time,
                    end_time = EXCLUDED.end_time,
                    duration_seconds = EXCLUDED.duration_seconds,
                    status = EXCLUDED.status,
                    record_file = EXCLUDED.record_file,
                    file_size_bytes = EXCLUDED.file_size_bytes
                """;

        try (Connection conn = open(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, record.callId());
            ps.setString(2, record.deviceId());
            ps.setString(3, record.ip());
            ps.setInt(4, record.site());
            ps.setInt(5, record.channel());
            ps.setString(6, record.room());
            ps.setTimestamp(7, Timestamp.valueOf(record.startTime()));
            ps.setTimestamp(8, Timestamp.valueOf(record.endTime()));
            ps.setInt(9, record.durationSeconds());
            ps.setString(10, record.status());
            ps.setString(11, record.recordFile());
            ps.setLong(12, record.fileSizeBytes());
            ps.executeUpdate();
        }
    }

    public List<CallLogRecord> queryLatest(int limit, int offset) throws SQLException {
        String sql = """
                SELECT call_id, device_id, ip, site, channel, room,
                       start_time, end_time, duration_seconds, status,
                       record_file, file_size_bytes
                FROM ptt_call_logs
                ORDER BY end_time DESC
                LIMIT ? OFFSET ?
                """;
        try (Connection conn = open(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setInt(1, limit);
            ps.setInt(2, offset);
            try (ResultSet rs = ps.executeQuery()) {
                List<CallLogRecord> list = new ArrayList<>();
                while (rs.next()) {
                    list.add(fromResultSet(rs));
                }
                return list;
            }
        }
    }

    public Optional<CallLogRecord> findByCallId(String callId) throws SQLException {
        String sql = """
                SELECT call_id, device_id, ip, site, channel, room,
                       start_time, end_time, duration_seconds, status,
                       record_file, file_size_bytes
                FROM ptt_call_logs
                WHERE call_id = ?
                """;
        try (Connection conn = open(); PreparedStatement ps = conn.prepareStatement(sql)) {
            ps.setString(1, callId);
            try (ResultSet rs = ps.executeQuery()) {
                if (rs.next()) {
                    return Optional.of(fromResultSet(rs));
                }
                return Optional.empty();
            }
        }
    }

    public boolean ping() {
        try (Connection conn = open(); Statement st = conn.createStatement()) {
            st.execute("SELECT 1");
            return true;
        } catch (SQLException e) {
            return false;
        }
    }

    private Connection open() throws SQLException {
        return DriverManager.getConnection(config.pgUrl, config.pgUser, config.pgPassword);
    }

    private static CallLogRecord fromResultSet(ResultSet rs) throws SQLException {
        return new CallLogRecord(
                rs.getString("call_id"),
                rs.getString("device_id"),
                rs.getString("ip"),
                rs.getInt("site"),
                rs.getInt("channel"),
                rs.getString("room"),
                rs.getTimestamp("start_time").toLocalDateTime(),
                rs.getTimestamp("end_time").toLocalDateTime(),
                rs.getInt("duration_seconds"),
                rs.getString("status"),
                rs.getString("record_file"),
                rs.getLong("file_size_bytes"));
    }
}
