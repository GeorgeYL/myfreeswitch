package com.rocktech.ptt;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.sql.SQLException;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Optional;

public final class QueryService {
    private static final DateTimeFormatter TS_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");

    private final PostgresRepository repository;

    public QueryService(PostgresRepository repository) {
        this.repository = repository;
    }

    public String queryLogsJson(int limit, int offset) throws SQLException {
        List<CallLogRecord> records = repository.queryLatest(limit, offset);
        StringBuilder sb = new StringBuilder();
        sb.append("[");
        for (int i = 0; i < records.size(); i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(toJson(records.get(i)));
        }
        sb.append("]");
        return sb.toString();
    }

    public String getLogByCallIdJson(String callId) throws SQLException {
        Optional<CallLogRecord> record = repository.findByCallId(callId);
        return record.map(this::toJson).orElse("{}");
    }

    public Optional<CallLogRecord> findByCallId(String callId) throws SQLException {
        return repository.findByCallId(callId);
    }

    public boolean isDatabaseReady() {
        return repository.ping();
    }

    public Path downloadRecording(String callId, Path targetFile) throws SQLException, IOException {
        Optional<CallLogRecord> record = repository.findByCallId(callId);
        if (record.isEmpty()) {
            throw new IllegalArgumentException("call_id not found: " + callId);
        }
        Path source = Path.of(record.get().recordFile());
        if (!Files.exists(source)) {
            throw new IllegalArgumentException("record file not found: " + source);
        }
        Files.copy(source, targetFile, StandardCopyOption.REPLACE_EXISTING);
        return targetFile;
    }

    private String toJson(CallLogRecord r) {
        return "{" +
                quote("call_id") + ":" + quote(r.callId()) + "," +
                quote("device_id") + ":" + quote(r.deviceId()) + "," +
                quote("ip") + ":" + quote(r.ip()) + "," +
                quote("site") + ":" + r.site() + "," +
                quote("channel") + ":" + r.channel() + "," +
                quote("room") + ":" + quote(r.room()) + "," +
                quote("start_time") + ":" + quote(TS_FMT.format(r.startTime())) + "," +
                quote("end_time") + ":" + quote(TS_FMT.format(r.endTime())) + "," +
                quote("duration_seconds") + ":" + r.durationSeconds() + "," +
                quote("status") + ":" + quote(r.status()) + "," +
                quote("record_file") + ":" + quote(r.recordFile()) + "," +
                quote("file_size_bytes") + ":" + r.fileSizeBytes() +
                "}";
    }

    private static String quote(String s) {
        String escaped = s
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r");
        return "\"" + escaped + "\"";
    }
}
