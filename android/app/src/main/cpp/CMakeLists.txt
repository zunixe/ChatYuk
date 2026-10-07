# JNI helper untuk mengembalikan arena allocator native (jemalloc) ke OS.
# Dipakai ImageBridge.nativeTrim() → malloc_trim/mallctl. Lihat
# docs/PERFORMANCE.md §27.
cmake_minimum_required(VERSION 3.18.1)

project(chatyuknative C)

add_library(chatyuknative SHARED native_trim.c)

# libc/libdl tersedia lewat toolchain NDK; dlsym perlu libdl.
find_library(log-lib log)
target_link_libraries(chatyuknative ${log-lib})
