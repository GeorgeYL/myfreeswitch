package com.rocktech.ptt;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.file.Files;
import java.nio.file.Path;
import java.sql.SQLException;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.Executors;

public final class HttpApiServer {
    private final QueryService queryService;
    private final String host;
    private final int port;

    private HttpServer server;

    public HttpApiServer(QueryService queryService, String host, int port) {
        this.queryService = queryService;
        this.host = host;
        this.port = port;
    }

    public void start() throws IOException {
        server = HttpServer.create(new InetSocketAddress(host, port), 0);
        server.createContext("/health", this::handleHealth);
        server.createContext("/health/db", this::handleDbHealth);
        server.createContext("/api/logs", this::handleLogs);
        server.createContext("/api/recordings", this::handleRecordings);
        server.setExecutor(Executors.newFixedThreadPool(8));
        server.start();
        System.out.println("[ptt-java] HTTP API listening on http://" + host + ":" + port);
    }

    public void stop() {
        if (server != null) {
            server.stop(0);
        }
    }

    private void handleHealth(HttpExchange ex) throws IOException {
        if (!"GET".equalsIgnoreCase(ex.getRequestMethod())) {
            writeJson(ex, 405, "{\"detail\":\"method not allowed\"}");
            return;
        }
        writeJson(ex, 200, "{\"status\":\"ok\"}");
    }

    private void handleDbHealth(HttpExchange ex) throws IOException {
        if (!"GET".equalsIgnoreCase(ex.getRequestMethod())) {
            writeJson(ex, 405, "{\"detail\":\"method not allowed\"}");
            return;
        }

        if (queryService.isDatabaseReady()) {
            writeJson(ex, 200, "{\"status\":\"ok\",\"database\":\"ready\"}");
            return;
        }

        writeJson(ex, 503, "{\"status\":\"degraded\",\"database\":\"unreachable\"}");
    }

    private void handleLogs(HttpExchange ex) throws IOException {
        if (!"GET".equalsIgnoreCase(ex.getRequestMethod())) {
            writeJson(ex, 405, "{\"detail\":\"method not allowed\"}");
            return;
        }

        String path = ex.getRequestURI().getPath();
        if ("/api/logs".equals(path) || "/api/logs/".equals(path)) {
            Map<String, String> q = parseQuery(ex.getRequestURI());
            int limit = parseInt(q.get("limit"), 100);
            int offset = parseInt(q.get("offset"), 0);
            try {
                String json = queryService.queryLogsJson(limit, offset);
                writeJson(ex, 200, json);
            } catch (SQLException e) {
                writeJson(ex, 500, "{\"detail\":\"" + esc(e.getMessage()) + "\"}");
            }
            return;
        }

        String prefix = "/api/logs/";
        if (path.startsWith(prefix) && path.length() > prefix.length()) {
            String callId = path.substring(prefix.length());
            try {
                String json = queryService.getLogByCallIdJson(callId);
                if ("{}".equals(json)) {
                    writeJson(ex, 404, "{\"detail\":\"call log not found\"}");
                    return;
                }
                writeJson(ex, 200, json);
            } catch (SQLException e) {
                writeJson(ex, 500, "{\"detail\":\"" + esc(e.getMessage()) + "\"}");
            }
            return;
        }

        writeJson(ex, 404, "{\"detail\":\"not found\"}");
    }

    private void handleRecordings(HttpExchange ex) throws IOException {
        if (!"GET".equalsIgnoreCase(ex.getRequestMethod())) {
            writeJson(ex, 405, "{\"detail\":\"method not allowed\"}");
            return;
        }

        String path = ex.getRequestURI().getPath();
        String prefix = "/api/recordings/";
        if (!(path.startsWith(prefix) && path.length() > prefix.length())) {
            writeJson(ex, 404, "{\"detail\":\"not found\"}");
            return;
        }

        String callId = path.substring(prefix.length());
        try {
            Optional<CallLogRecord> rec = queryService.findByCallId(callId);
            if (rec.isEmpty()) {
                writeJson(ex, 404, "{\"detail\":\"call log not found\"}");
                return;
            }

            Path file = Path.of(rec.get().recordFile());
            if (!Files.exists(file)) {
                writeJson(ex, 404, "{\"detail\":\"record file not found\"}");
                return;
            }

            byte[] bytes = Files.readAllBytes(file);
            ex.getResponseHeaders().set("Content-Type", "audio/wav");
            ex.getResponseHeaders().set("Content-Disposition", "attachment; filename=\"" + file.getFileName() + "\"");
            ex.sendResponseHeaders(200, bytes.length);
            try (OutputStream os = ex.getResponseBody()) {
                os.write(bytes);
            }
        } catch (SQLException e) {
            writeJson(ex, 500, "{\"detail\":\"" + esc(e.getMessage()) + "\"}");
        }
    }

    private static void writeJson(HttpExchange ex, int code, String body) throws IOException {
        byte[] bytes = body.getBytes();
        ex.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        ex.sendResponseHeaders(code, bytes.length);
        try (OutputStream os = ex.getResponseBody()) {
            os.write(bytes);
        }
    }

    private static Map<String, String> parseQuery(URI uri) {
        Map<String, String> result = new HashMap<>();
        String raw = uri.getRawQuery();
        if (raw == null || raw.isBlank()) {
            return result;
        }
        String[] pairs = raw.split("&");
        for (String pair : pairs) {
            if (pair.isBlank()) {
                continue;
            }
            int i = pair.indexOf('=');
            if (i < 0) {
                result.put(pair, "");
            } else {
                result.put(pair.substring(0, i), pair.substring(i + 1));
            }
        }
        return result;
    }

    private static int parseInt(String value, int fallback) {
        if (value == null || value.isBlank()) {
            return fallback;
        }
        try {
            return Integer.parseInt(value);
        } catch (Exception e) {
            return fallback;
        }
    }

    private static String esc(String text) {
        if (text == null) {
            return "";
        }
        return text.replace("\\", "\\\\").replace("\"", "\\\"");
    }
}
