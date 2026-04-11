package com.rocktech.ptt.jni;

public final class PttJniApi {
    static {
        String enabled = System.getenv("PTT_JNI_ENABLE");
        if ("1".equals(enabled) || "true".equalsIgnoreCase(enabled)) {
            System.loadLibrary("ptt_jni_bridge");
        }
    }

    public native String queryLogsJson(int limit, int offset);

    public native String getLogByCallIdJson(String callId);

    public native int downloadRecording(String callId, String targetPath);
}
