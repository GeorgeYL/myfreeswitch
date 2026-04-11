package com.rocktech.ptt;

import java.io.BufferedInputStream;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.SocketTimeoutException;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

public final class EslClient {
    private final String host;
    private final int port;
    private final String password;

    private Socket socket;
    private BufferedInputStream input;
    private OutputStream output;
    private byte[] buffer = new byte[0];

    public EslClient(String host, int port, String password) {
        this.host = host;
        this.port = port;
        this.password = password;
    }

    public void connect() throws IOException {
        close();
        socket = new Socket();
        socket.connect(new InetSocketAddress(host, port), 8000);
        socket.setSoTimeout(2000);
        input = new BufferedInputStream(socket.getInputStream());
        output = socket.getOutputStream();

        waitAuthRequest();
        sendCommand("auth " + password);
        requireCommandOk();
        sendCommand("event plain CHANNEL_ANSWER CHANNEL_HANGUP_COMPLETE");
        requireCommandOk();
    }

    public synchronized void close() {
        try {
            if (socket != null) {
                socket.close();
            }
        } catch (Exception ignored) {
        } finally {
            socket = null;
            input = null;
            output = null;
            buffer = new byte[0];
        }
    }

    public Map<String, String> readEvent() throws IOException {
        Frame frame = recvFrame();
        if (frame == null) {
            return null;
        }
        String ct = frame.headers.getOrDefault("Content-Type", "");
        if (!"text/event-plain".equals(ct)) {
            return null;
        }
        return parseHeaders(frame.body);
    }

    private void waitAuthRequest() throws IOException {
        long deadline = System.currentTimeMillis() + 8000;
        while (System.currentTimeMillis() < deadline) {
            Frame frame = recvFrame();
            if (frame == null) {
                continue;
            }
            if ("auth/request".equals(frame.headers.get("Content-Type"))) {
                return;
            }
        }
        throw new IOException("Timeout waiting ESL auth/request");
    }

    private void sendCommand(String command) throws IOException {
        output.write((command + "\n\n").getBytes(StandardCharsets.UTF_8));
        output.flush();
    }

    private void requireCommandOk() throws IOException {
        long deadline = System.currentTimeMillis() + 8000;
        while (System.currentTimeMillis() < deadline) {
            Frame frame = recvFrame();
            if (frame == null) {
                continue;
            }
            if ("command/reply".equals(frame.headers.get("Content-Type"))) {
                String reply = frame.headers.getOrDefault("Reply-Text", "");
                if (!reply.startsWith("+OK")) {
                    throw new IOException("ESL command failed: " + reply);
                }
                return;
            }
        }
        throw new IOException("Timeout waiting command/reply");
    }

    private Frame recvFrame() throws IOException {
        while (true) {
            Frame parsed = tryParseFrame();
            if (parsed != null) {
                return parsed;
            }
            byte[] chunk;
            try {
                chunk = input.readNBytes(65535);
            } catch (SocketTimeoutException e) {
                return null;
            }
            if (chunk.length == 0) {
                return null;
            }
            byte[] merged = new byte[buffer.length + chunk.length];
            System.arraycopy(buffer, 0, merged, 0, buffer.length);
            System.arraycopy(chunk, 0, merged, buffer.length, chunk.length);
            buffer = merged;
        }
    }

    private Frame tryParseFrame() {
        int sep = findHeaderSeparator(buffer);
        if (sep < 0) {
            return null;
        }

        int sepLen = (buffer[sep] == '\r') ? 4 : 2;
        String headerText = new String(buffer, 0, sep, StandardCharsets.UTF_8);
        Map<String, String> headers = parseHeaders(headerText);
        int contentLength = parseContentLength(headers.get("Content-Length"));

        int bodyStart = sep + sepLen;
        int total = bodyStart + contentLength;
        if (buffer.length < total) {
            return null;
        }

        String body = new String(buffer, bodyStart, contentLength, StandardCharsets.UTF_8);
        byte[] remaining = new byte[buffer.length - total];
        System.arraycopy(buffer, total, remaining, 0, remaining.length);
        buffer = remaining;

        return new Frame(headers, body);
    }

    private static int findHeaderSeparator(byte[] data) {
        for (int i = 0; i < data.length - 1; i++) {
            if (data[i] == '\n' && data[i + 1] == '\n') {
                return i;
            }
            if (i + 3 < data.length && data[i] == '\r' && data[i + 1] == '\n' && data[i + 2] == '\r' && data[i + 3] == '\n') {
                return i;
            }
        }
        return -1;
    }

    private static int parseContentLength(String s) {
        if (s == null || s.isBlank()) {
            return 0;
        }
        try {
            return Integer.parseInt(s.trim());
        } catch (Exception e) {
            return 0;
        }
    }

    public static Map<String, String> parseHeaders(String text) {
        Map<String, String> result = new HashMap<>();
        if (text == null || text.isBlank()) {
            return result;
        }
        String[] lines = text.split("\\r?\\n");
        for (String line : lines) {
            if (line == null || line.isBlank()) {
                continue;
            }
            int pos = line.indexOf(':');
            if (pos <= 0) {
                continue;
            }
            result.put(line.substring(0, pos).trim(), line.substring(pos + 1).trim());
        }
        return result;
    }

    private record Frame(Map<String, String> headers, String body) {}
}
