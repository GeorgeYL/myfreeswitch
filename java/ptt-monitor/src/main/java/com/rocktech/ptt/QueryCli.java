package com.rocktech.ptt;

import java.nio.file.Path;

public final class QueryCli {
    public static void main(String[] args) throws Exception {
        if (args.length < 1) {
            System.out.println("Usage:");
            System.out.println("  QueryCli logs [limit] [offset]");
            System.out.println("  QueryCli call <call_id>");
            System.out.println("  QueryCli download <call_id> <target_file>");
            return;
        }

        Config config = Config.fromEnv();
        PostgresRepository repo = new PostgresRepository(config);
        QueryService query = new QueryService(repo);

        String cmd = args[0];
        if ("logs".equalsIgnoreCase(cmd)) {
            int limit = args.length > 1 ? Integer.parseInt(args[1]) : 20;
            int offset = args.length > 2 ? Integer.parseInt(args[2]) : 0;
            System.out.println(query.queryLogsJson(limit, offset));
        } else if ("call".equalsIgnoreCase(cmd)) {
            if (args.length < 2) {
                throw new IllegalArgumentException("call_id is required");
            }
            System.out.println(query.getLogByCallIdJson(args[1]));
        } else if ("download".equalsIgnoreCase(cmd)) {
            if (args.length < 3) {
                throw new IllegalArgumentException("call_id and target_file are required");
            }
            Path file = query.downloadRecording(args[1], Path.of(args[2]));
            System.out.println(file.toAbsolutePath());
        } else {
            throw new IllegalArgumentException("Unknown command: " + cmd);
        }
    }
}
