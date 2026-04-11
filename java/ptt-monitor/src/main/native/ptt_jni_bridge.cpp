#include <jni.h>
#include <libpq-fe.h>

#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <cstdlib>

namespace {

std::string envOr(const char* key, const char* fallback) {
    const char* v = std::getenv(key);
    if (!v || std::string(v).empty()) {
        return fallback;
    }
    return v;
}

std::string quote(const std::string& s) {
    std::ostringstream oss;
    oss << '"';
    for (char c : s) {
        switch (c) {
            case '\\': oss << "\\\\"; break;
            case '"': oss << "\\\""; break;
            case '\n': oss << "\\n"; break;
            case '\r': oss << "\\r"; break;
            default: oss << c; break;
        }
    }
    oss << '"';
    return oss.str();
}

PGconn* openConn() {
    std::string conn = envOr("PG_CONNINFO", "host=127.0.0.1 port=5432 dbname=ptt_demo user=postgres password=postgres");
    PGconn* c = PQconnectdb(conn.c_str());
    if (PQstatus(c) != CONNECTION_OK) {
        std::string msg = PQerrorMessage(c);
        PQfinish(c);
        throw std::runtime_error("PostgreSQL connection failed: " + msg);
    }
    return c;
}

jstring toJString(JNIEnv* env, const std::string& s) {
    return env->NewStringUTF(s.c_str());
}

std::string jToString(JNIEnv* env, jstring js) {
    if (!js) {
        return "";
    }
    const char* raw = env->GetStringUTFChars(js, nullptr);
    std::string result = raw ? raw : "";
    if (raw) {
        env->ReleaseStringUTFChars(js, raw);
    }
    return result;
}

void throwRuntime(JNIEnv* env, const std::string& msg) {
    jclass ex = env->FindClass("java/lang/RuntimeException");
    env->ThrowNew(ex, msg.c_str());
}

std::string makeRowJson(PGresult* r, int row) {
    std::ostringstream out;
    out << "{";
    out << quote("call_id") << ":" << quote(PQgetvalue(r, row, 0)) << ",";
    out << quote("device_id") << ":" << quote(PQgetvalue(r, row, 1)) << ",";
    out << quote("ip") << ":" << quote(PQgetvalue(r, row, 2)) << ",";
    out << quote("site") << ":" << PQgetvalue(r, row, 3) << ",";
    out << quote("channel") << ":" << PQgetvalue(r, row, 4) << ",";
    out << quote("room") << ":" << quote(PQgetvalue(r, row, 5)) << ",";
    out << quote("start_time") << ":" << quote(PQgetvalue(r, row, 6)) << ",";
    out << quote("end_time") << ":" << quote(PQgetvalue(r, row, 7)) << ",";
    out << quote("duration_seconds") << ":" << PQgetvalue(r, row, 8) << ",";
    out << quote("status") << ":" << quote(PQgetvalue(r, row, 9)) << ",";
    out << quote("record_file") << ":" << quote(PQgetvalue(r, row, 10)) << ",";
    out << quote("file_size_bytes") << ":" << PQgetvalue(r, row, 11);
    out << "}";
    return out.str();
}

}  // namespace

extern "C" JNIEXPORT jstring JNICALL Java_com_rocktech_ptt_jni_PttJniApi_queryLogsJson(
    JNIEnv* env, jobject, jint limit, jint offset) {
    try {
        PGconn* conn = openConn();
        std::string q =
            "SELECT call_id, device_id, ip, site, channel, room, "
            "to_char(start_time, 'YYYY-MM-DD HH24:MI:SS'), "
            "to_char(end_time, 'YYYY-MM-DD HH24:MI:SS'), "
            "duration_seconds, status, record_file, file_size_bytes "
            "FROM ptt_call_logs ORDER BY end_time DESC LIMIT " + std::to_string(limit) +
            " OFFSET " + std::to_string(offset);

        PGresult* r = PQexec(conn, q.c_str());
        if (PQresultStatus(r) != PGRES_TUPLES_OK) {
            std::string err = PQerrorMessage(conn);
            PQclear(r);
            PQfinish(conn);
            throw std::runtime_error(err);
        }

        std::ostringstream out;
        out << "[";
        int rows = PQntuples(r);
        for (int i = 0; i < rows; i++) {
            if (i > 0) out << ",";
            out << makeRowJson(r, i);
        }
        out << "]";

        std::string json = out.str();
        PQclear(r);
        PQfinish(conn);
        return toJString(env, json);
    } catch (const std::exception& e) {
        throwRuntime(env, e.what());
        return toJString(env, "[]");
    }
}

extern "C" JNIEXPORT jstring JNICALL Java_com_rocktech_ptt_jni_PttJniApi_getLogByCallIdJson(
    JNIEnv* env, jobject, jstring callId) {
    try {
        std::string cid = jToString(env, callId);
        PGconn* conn = openConn();
        const char* values[1] = {cid.c_str()};
        PGresult* r = PQexecParams(
            conn,
            "SELECT call_id, device_id, ip, site, channel, room, "
            "to_char(start_time, 'YYYY-MM-DD HH24:MI:SS'), "
            "to_char(end_time, 'YYYY-MM-DD HH24:MI:SS'), "
            "duration_seconds, status, record_file, file_size_bytes "
            "FROM ptt_call_logs WHERE call_id = $1",
            1,
            nullptr,
            values,
            nullptr,
            nullptr,
            0);

        if (PQresultStatus(r) != PGRES_TUPLES_OK) {
            std::string err = PQerrorMessage(conn);
            PQclear(r);
            PQfinish(conn);
            throw std::runtime_error(err);
        }

        std::string json = "{}";
        if (PQntuples(r) > 0) {
            json = makeRowJson(r, 0);
        }
        PQclear(r);
        PQfinish(conn);
        return toJString(env, json);
    } catch (const std::exception& e) {
        throwRuntime(env, e.what());
        return toJString(env, "{}");
    }
}

extern "C" JNIEXPORT jint JNICALL Java_com_rocktech_ptt_jni_PttJniApi_downloadRecording(
    JNIEnv* env, jobject, jstring callId, jstring targetPath) {
    try {
        std::string cid = jToString(env, callId);
        std::string target = jToString(env, targetPath);

        PGconn* conn = openConn();
        const char* values[1] = {cid.c_str()};
        PGresult* r = PQexecParams(
            conn,
            "SELECT record_file FROM ptt_call_logs WHERE call_id = $1",
            1,
            nullptr,
            values,
            nullptr,
            nullptr,
            0);

        if (PQresultStatus(r) != PGRES_TUPLES_OK) {
            std::string err = PQerrorMessage(conn);
            PQclear(r);
            PQfinish(conn);
            throw std::runtime_error(err);
        }

        if (PQntuples(r) == 0) {
            PQclear(r);
            PQfinish(conn);
            return 2;
        }

        std::filesystem::path src(PQgetvalue(r, 0, 0));
        PQclear(r);
        PQfinish(conn);

        if (!std::filesystem::exists(src)) {
            return 3;
        }

        std::filesystem::path dst(target);
        if (!dst.parent_path().empty()) {
            std::filesystem::create_directories(dst.parent_path());
        }
        std::filesystem::copy_file(src, dst, std::filesystem::copy_options::overwrite_existing);
        return 0;
    } catch (const std::exception& e) {
        throwRuntime(env, e.what());
        return 1;
    }
}
