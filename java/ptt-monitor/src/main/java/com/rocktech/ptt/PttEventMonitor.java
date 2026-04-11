package com.rocktech.ptt;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

public final class PttEventMonitor {
    private static final String DEST_PATTERN = "^7([1-4])([1-4])$";

    private final Config config;
    private final PostgresRepository repository;
    private final EslClient eslClient;
    private final ConcurrentHashMap<String, ActiveCall> activeCalls = new ConcurrentHashMap<>();

    public PttEventMonitor(Config config, PostgresRepository repository) {
        this.config = config;
        this.repository = repository;
        this.eslClient = new EslClient(config.eslHost, config.eslPort, config.eslPassword);
    }

    public void runForever() {
        while (true) {
            try {
                eslClient.connect();
                System.out.println("[ptt-java] ESL connected: " + config.eslHost + ":" + config.eslPort);
                eventLoop();
            } catch (Exception e) {
                System.err.println("[ptt-java] ESL loop error: " + e.getMessage());
                eslClient.close();
                sleep(2000);
            }
        }
    }

    private void eventLoop() throws IOException {
        while (true) {
            Map<String, String> event = eslClient.readEvent();
            if (event == null || event.isEmpty()) {
                continue;
            }
            String name = event.getOrDefault("Event-Name", "");
            if ("CHANNEL_ANSWER".equals(name)) {
                onAnswer(event);
            } else if ("CHANNEL_HANGUP_COMPLETE".equals(name)) {
                onHangup(event);
            }
        }
    }

    private void onAnswer(Map<String, String> event) {
        String callId = value(event, "Unique-ID");
        if (callId.isBlank()) {
            return;
        }

        String destination = fallback(event, "Caller-Destination-Number", "variable_destination_number");
        String pttRoom = value(event, "variable_ptt_room");

        int site = parseSite(event, destination);
        int channel = parseChannel(event, destination);
        if ((site <= 0 || channel <= 0) && pttRoom.isBlank()) {
            return;
        }

        String room = !pttRoom.isBlank() ? pttRoom : "ptt_s" + site + "_c" + channel + "@" + config.fsDomain;
        String deviceId = fallback(event, "Caller-Caller-ID-Number", "variable_sip_from_user");
        String ip = fallback(event, "Caller-Network-Addr", "variable_sip_network_ip");
        String recordFile = value(event, "variable_ptt_record_file");
        LocalDateTime startTime = parseEventTime(event.get("Event-Date-Timestamp"));

        activeCalls.put(callId, new ActiveCall(callId, blankAs(deviceId, "unknown"), ip, site, channel, room, startTime, recordFile));
    }

    private void onHangup(Map<String, String> event) {
        String callId = value(event, "Unique-ID");
        if (callId.isBlank()) {
            return;
        }

        ActiveCall active = activeCalls.remove(callId);
        if (active == null) {
            return;
        }

        LocalDateTime end = parseEventTime(event.get("Event-Date-Timestamp"));
        int duration = (int) Math.max(0, ChronoUnit.SECONDS.between(active.startTime(), end));
        String cause = value(event, "Hangup-Cause");
        String status = "NORMAL_CLEARING".equals(cause) ? "NORMAL_END" : blankAs(cause, "NORMAL_END");

        String recordFile = resolveRecordingFile(active.recordFile());
        long fileSize = 0;
        if (!recordFile.isBlank()) {
            try {
                fileSize = Files.size(Path.of(recordFile));
            } catch (Exception ignored) {
            }
        }

        CallLogRecord record = new CallLogRecord(
                callId,
                active.deviceId(),
                active.ip(),
                active.site(),
                active.channel(),
                active.room(),
                active.startTime(),
                end,
                duration,
                status,
                recordFile,
                fileSize);

        try {
            repository.upsert(record);
            System.out.println("[ptt-java] persisted call log: " + callId);
        } catch (Exception e) {
            System.err.println("[ptt-java] persist failed for " + callId + ": " + e.getMessage());
        }
    }

    private String resolveRecordingFile(String path) {
        if (path == null || path.isBlank()) {
            return "";
        }
        Path p = Path.of(path);
        if (p.isAbsolute()) {
            return p.toString();
        }
        return config.recordingsDir.resolve(path).normalize().toString();
    }

    private static int parseSite(Map<String, String> event, String destination) {
        String v = value(event, "variable_ptt_site");
        if (!v.isBlank()) {
            return parseIntSafe(v, 0);
        }
        if (destination != null && destination.matches(DEST_PATTERN)) {
            return Character.digit(destination.charAt(1), 10);
        }
        return 0;
    }

    private static int parseChannel(Map<String, String> event, String destination) {
        String v = value(event, "variable_ptt_channel");
        if (!v.isBlank()) {
            return parseIntSafe(v, 0);
        }
        if (destination != null && destination.matches(DEST_PATTERN)) {
            return Character.digit(destination.charAt(2), 10);
        }
        return 0;
    }

    private static LocalDateTime parseEventTime(String microTs) {
        if (microTs == null || microTs.isBlank()) {
            return LocalDateTime.now();
        }
        try {
            long us = Long.parseLong(microTs);
            Instant instant = Instant.ofEpochMilli(us / 1000);
            return LocalDateTime.ofInstant(instant, ZoneId.systemDefault());
        } catch (Exception e) {
            return LocalDateTime.now();
        }
    }

    private static String fallback(Map<String, String> event, String first, String second) {
        String a = value(event, first);
        return a.isBlank() ? value(event, second) : a;
    }

    private static String value(Map<String, String> event, String key) {
        String v = event.get(key);
        return v == null ? "" : v.trim();
    }

    private static String blankAs(String input, String fallback) {
        return input == null || input.isBlank() ? fallback : input;
    }

    private static int parseIntSafe(String input, int fallback) {
        try {
            return Integer.parseInt(input);
        } catch (Exception e) {
            return fallback;
        }
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException ignored) {
            Thread.currentThread().interrupt();
        }
    }

    private record ActiveCall(
            String callId,
            String deviceId,
            String ip,
            int site,
            int channel,
            String room,
            LocalDateTime startTime,
            String recordFile) {}
}
