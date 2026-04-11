package com.rocktech.ptt;

import java.nio.file.Path;

public final class Config {
    public final String eslHost;
    public final int eslPort;
    public final String eslPassword;
    public final String fsDomain;
    public final Path recordingsDir;

    public final String pgUrl;
    public final String pgUser;
    public final String pgPassword;

    public final boolean httpEnabled;
    public final String httpHost;
    public final int httpPort;

    private Config(
            String eslHost,
            int eslPort,
            String eslPassword,
            String fsDomain,
            Path recordingsDir,
            String pgUrl,
            String pgUser,
            String pgPassword,
            boolean httpEnabled,
            String httpHost,
            int httpPort) {
        this.eslHost = eslHost;
        this.eslPort = eslPort;
        this.eslPassword = eslPassword;
        this.fsDomain = fsDomain;
        this.recordingsDir = recordingsDir;
        this.pgUrl = pgUrl;
        this.pgUser = pgUser;
        this.pgPassword = pgPassword;
        this.httpEnabled = httpEnabled;
        this.httpHost = httpHost;
        this.httpPort = httpPort;
    }

    public static Config fromEnv() {
        String eslHost = env("ESL_HOST", "127.0.0.1");
        int eslPort = Integer.parseInt(env("ESL_PORT", "8021"));
        String eslPassword = env("ESL_PASSWORD", "ClueCon");
        String fsDomain = env("FS_DOMAIN", "127.0.0.1");
        Path recordingsDir = Path.of(env("RECORDINGS_DIR", "D:/03_rocktech/source/freeswitch/x64/Release/recordings"));

        String pgUrl = env("PG_URL", "jdbc:postgresql://127.0.0.1:5432/ptt_demo");
        String pgUser = env("PG_USER", "postgres");
        String pgPassword = env("PG_PASSWORD", "postgres");

        boolean httpEnabled = Boolean.parseBoolean(env("HTTP_ENABLE", "true"));
        String httpHost = env("HTTP_HOST", "0.0.0.0");
        int httpPort = Integer.parseInt(env("HTTP_PORT", "8091"));

        return new Config(
            eslHost,
            eslPort,
            eslPassword,
            fsDomain,
            recordingsDir,
            pgUrl,
            pgUser,
            pgPassword,
            httpEnabled,
            httpHost,
            httpPort);
    }

    private static String env(String key, String defaultValue) {
        String v = System.getenv(key);
        return v == null || v.isBlank() ? defaultValue : v;
    }
}
