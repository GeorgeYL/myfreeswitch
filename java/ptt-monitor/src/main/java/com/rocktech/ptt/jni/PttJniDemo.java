package com.rocktech.ptt.jni;

public final class PttJniDemo {
    public static void main(String[] args) {
        PttJniApi api = new PttJniApi();
        String list = api.queryLogsJson(10, 0);
        System.out.println(list);

        if (args.length >= 1) {
            String callId = args[0];
            System.out.println(api.getLogByCallIdJson(callId));
            int rc = api.downloadRecording(callId, "./jni-demo.wav");
            System.out.println("download rc=" + rc);
        }
    }
}
