# JNI helper untuk mengembalikan arena allocator native (jemalloc) ke OS.
# Dipakai ImageBridge.nativeTrim() → mallopt(M_PURGE/M_PURGE_ALL). Lihat
# docs/PERFORMANCE.md §39–§42.
cmake_minimum_required(VERSION 3.18.1)

project(chatyuknative C)

add_library(chatyuknative SHARED native_trim.c)

# mallopt() ada di libc (bionic) — di-link otomatis. liblog untuk LOGI().
find_library(log-lib log)
target_link_libraries(chatyuknative ${log-lib})
