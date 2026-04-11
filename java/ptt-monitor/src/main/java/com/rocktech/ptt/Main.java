package com.rocktech.ptt;

public final class Main {
    public static void main(String[] args) throws Exception {
        Config config = Config.fromEnv();
        PostgresRepository repository = new PostgresRepository(config);
        repository.initSchema();
        QueryService queryService = new QueryService(repository);

        System.out.println("[ptt-java] PostgreSQL ready: " + config.pgUrl);
        System.out.println("[ptt-java] monitoring ESL " + config.eslHost + ":" + config.eslPort);

        if (config.httpEnabled) {
            HttpApiServer httpApiServer = new HttpApiServer(queryService, config.httpHost, config.httpPort);
            httpApiServer.start();
        }

        PttEventMonitor monitor = new PttEventMonitor(config, repository);
        monitor.runForever();
    }
}
