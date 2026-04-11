cmake_minimum_required(VERSION 3.16)
project(ptt_jni_bridge)

set(CMAKE_CXX_STANDARD 17)

if(NOT DEFINED ENV{JAVA_HOME})
    message(FATAL_ERROR "JAVA_HOME is not set")
endif()

set(JAVA_HOME_DIR $ENV{JAVA_HOME})
include_directories(${JAVA_HOME_DIR}/include)

if(WIN32)
    include_directories(${JAVA_HOME_DIR}/include/win32)
else()
    include_directories(${JAVA_HOME_DIR}/include/linux)
endif()

find_library(PQ_LIB pq HINTS
    "D:/03_rocktech/source/freeswitch/x64/Release"
    "C:/Program Files/PostgreSQL/17/lib"
)

if(NOT PQ_LIB)
    message(FATAL_ERROR "libpq not found. Set library path for PostgreSQL client.")
endif()

add_library(ptt_jni_bridge SHARED ptt_jni_bridge.cpp)
target_link_libraries(ptt_jni_bridge PRIVATE ${PQ_LIB})
