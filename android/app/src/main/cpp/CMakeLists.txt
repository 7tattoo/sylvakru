cmake_minimum_required(VERSION 3.22.1)

project(sylvakru_usb_exclusive)

set(BUILD_CXXLIBS OFF CACHE BOOL "" FORCE)
set(BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_DOCS OFF CACHE BOOL "" FORCE)
set(BUILD_UTILS OFF CACHE BOOL "" FORCE)
set(WITH_OGG OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(INSTALL_MANPAGES OFF CACHE BOOL "" FORCE)
set(INSTALL_PKGCONFIG_MODULES OFF CACHE BOOL "" FORCE)
set(INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
if(ANDROID)
    # libFLAC 1.5.0 会在部分 32 位 Android CMake 配置中误判 API 级别；
    # 本应用 minSdk=26，fseeko/ftello 在所有受支持设备上均可用。
    set(HAVE_FSEEKO 1 CACHE INTERNAL "" FORCE)
endif()
add_subdirectory(
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/flac-1.5.0
    ${CMAKE_CURRENT_BINARY_DIR}/flac
    EXCLUDE_FROM_ALL
)
if(ANDROID AND CMAKE_SYSTEM_PROCESSOR MATCHES "armv7-a|i686")
    target_compile_definitions(FLAC PRIVATE HAVE_FSEEKO)
endif()

# libwavpack：只编解码库，不编 CLI/安装件；DSD 支持关闭（DSD .wv 打开
# 直接失败，上层回退共享输出），legacy(<4.0) 文件同样不支持
set(WAVPACK_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(WAVPACK_ENABLE_LEGACY OFF CACHE BOOL "" FORCE)
set(WAVPACK_ENABLE_DSD OFF CACHE BOOL "" FORCE)
set(WAVPACK_ENABLE_LIBICONV OFF CACHE BOOL "" FORCE)
set(WAVPACK_INSTALL_CMAKE_MODULE OFF CACHE BOOL "" FORCE)
set(WAVPACK_INSTALL_DOCS OFF CACHE BOOL "" FORCE)
set(WAVPACK_INSTALL_PKGCONFIG_MODULE OFF CACHE BOOL "" FORCE)
add_subdirectory(
    ${CMAKE_CURRENT_SOURCE_DIR}/../../../../../third_party/wavpack-5.9.0
    ${CMAKE_CURRENT_BINARY_DIR}/wavpack
    EXCLUDE_FROM_ALL
)

add_library(
    sylvakru_flac_decoder
    STATIC
    flac_decoder.cpp
)
target_include_directories(sylvakru_flac_decoder PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sylvakru_flac_decoder PUBLIC FLAC::FLAC)

add_library(
    sylvakru_wavpack_decoder
    STATIC
    wavpack_decoder.cpp
)
target_include_directories(sylvakru_wavpack_decoder PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sylvakru_wavpack_decoder PUBLIC WavPack::WavPack)

if(ANDROID)
    add_library(
        sylvakru_usb_exclusive
        SHARED
        usb_exclusive_engine.cpp
        flac_decoder_jni.cpp
        wavpack_decoder_jni.cpp
    )

    find_library(log-lib log)

    target_link_libraries(
        sylvakru_usb_exclusive
        sylvakru_flac_decoder
        sylvakru_wavpack_decoder
        ${log-lib}
    )
endif()

option(SYLVAKRU_BUILD_HOST_TESTS "Build Sylvakru native host tests" OFF)
set(
    SYLVAKRU_FLAC_TESTDATA_DIR
    "${CMAKE_CURRENT_SOURCE_DIR}/testdata"
    CACHE STRING
    "Sylvakru FLAC 测试 fixture 目录（设备上运行时覆盖为设备路径）"
)
if(SYLVAKRU_BUILD_HOST_TESTS)
    add_executable(flac_decoder_test tests/flac_decoder_test.cpp)
    target_compile_definitions(
        flac_decoder_test
        PRIVATE SYLVAKRU_FLAC_TESTDATA_DIR="${SYLVAKRU_FLAC_TESTDATA_DIR}"
    )
    target_link_libraries(flac_decoder_test PRIVATE sylvakru_flac_decoder)

    # WavPack 测试不需要 fixture：用 libwavpack 编码 API 现场生成再往返验证
    add_executable(wavpack_decoder_test tests/wavpack_decoder_test.cpp)
    target_link_libraries(wavpack_decoder_test PRIVATE sylvakru_wavpack_decoder)
endif()
