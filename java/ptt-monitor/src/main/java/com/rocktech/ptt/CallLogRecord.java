package com.rocktech.ptt;

import java.time.LocalDateTime;

public record CallLogRecord(
        String callId,
        String deviceId,
        String ip,
        int site,
        int channel,
        String room,
        LocalDateTime startTime,
        LocalDateTime endTime,
        int durationSeconds,
        String status,
        String recordFile,
        long fileSizeBytes) {}
