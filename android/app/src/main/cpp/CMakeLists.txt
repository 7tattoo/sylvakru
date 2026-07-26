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

add_library(
    sylvakru_flac_decoder
    STATIC
    flac_decoder.cpp
)
target_include_directories(sylvakru_flac_decoder PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
target_link_libraries(sylvakru_flac_decoder PUBLIC FLAC::FLAC)

if(ANDROID)
    add_library(
        sylvakru_usb_exclusive
        SHARED
        usb_exclusive_engine.cpp
    )

    find_library(log-lib log)

    target_link_libraries(
        sylvakru_usb_exclusive
        sylvakru_flac_decoder
        ${log-lib}
    )
endif()

option(SYLVAKRU_BUILD_HOST_TESTS "Build Sylvakru native host tests" OFF)
if(SYLVAKRU_BUILD_HOST_TESTS)
    add_executable(flac_decoder_test tests/flac_decoder_test.cpp)
    target_link_libraries(flac_decoder_test PRIVATE sylvakru_flac_decoder)
endif()
