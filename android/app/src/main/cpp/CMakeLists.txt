cmake_minimum_required(VERSION 3.22)

project(barony_android LANGUAGES C CXX)

if(NOT ANDROID)
    message(FATAL_ERROR "The smoke target is Android-only")
endif()

option(BARONY_ANDROID_BUILD_GAME "Compile and link the complete Barony source" OFF)

get_filename_component(
    BARONY_REPOSITORY_ROOT
    "${CMAKE_CURRENT_LIST_DIR}/../../../../.."
    ABSOLUTE
)

set(SDL_SHARED ON CACHE BOOL "Build SDL as a shared library" FORCE)
set(SDL_STATIC OFF CACHE BOOL "Do not build static SDL" FORCE)
set(SDL_TESTS OFF CACHE BOOL "Do not build SDL tests" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "Do not build SDL test library" FORCE)
set(SDL_HIDAPI ON CACHE BOOL "Build SDL's Android HID bridge" FORCE)
set(SDL2_DISABLE_INSTALL ON CACHE BOOL "Do not generate SDL install targets" FORCE)

add_subdirectory(
    "${BARONY_REPOSITORY_ROOT}/external/SDL"
    "${CMAKE_BINARY_DIR}/SDL"
    EXCLUDE_FROM_ALL
)

find_library(ANDROID_LIBRARY android REQUIRED)
find_library(GLESV3_LIBRARY GLESv3 REQUIRED)
find_library(LOG_LIBRARY log REQUIRED)

add_library(main SHARED smoke_main.cpp)
target_compile_features(main PRIVATE cxx_std_17)
target_link_libraries(
    main
    PRIVATE
        SDL2::SDL2
        SDL2::SDL2main
        ${ANDROID_LIBRARY}
        ${GLESV3_LIBRARY}
        ${LOG_LIBRARY}
)

if(BARONY_ANDROID_BUILD_GAME)
    # SDL 2's Android OpenSL driver defaults to two buffers and only keeps one
    # queued ahead. Give the promoted SDL audio thread enough mix-ahead for
    # sustained gameplay without modifying the pinned SDL submodule.
    set(_barony_sdl_opensles_source
        "${BARONY_REPOSITORY_ROOT}/external/SDL/src/audio/openslES/SDL_openslES.c")
    set(_barony_sdl_opensles_override
        "${CMAKE_CURRENT_LIST_DIR}/sdl_opensles_queue_override.h")
    set_property(SOURCE "${_barony_sdl_opensles_source}"
        DIRECTORY "${BARONY_REPOSITORY_ROOT}/external/SDL"
        APPEND PROPERTY COMPILE_OPTIONS
            "-include"
            "${_barony_sdl_opensles_override}"
    )

    # SDL add-ons choose their SDL target name from BUILD_SHARED_LIBS. They are
    # static here, but intentionally consume the one shared SDL runtime that is
    # packaged by the smoke application.
    if(NOT TARGET SDL2::SDL2-static)
        add_library(SDL2::SDL2-static ALIAS SDL2)
    endif()

    set(BUILD_SHARED_LIBS OFF CACHE BOOL "Build Android dependencies statically" FORCE)
    set(CMAKE_POSITION_INDEPENDENT_CODE ON CACHE BOOL "Build static dependencies with PIC" FORCE)
    set(SKIP_INSTALL_ALL ON CACHE BOOL "Disable vendored dependency installs" FORCE)
    set(PNG_SHARED OFF CACHE BOOL "Do not build shared libpng" FORCE)
    set(PNG_STATIC ON CACHE BOOL "Build static libpng" FORCE)
    set(PNG_TESTS OFF CACHE BOOL "Do not build libpng tests" FORCE)
    set(PNG_TOOLS OFF CACHE BOOL "Do not build libpng tools" FORCE)
    set(ZLIB_BUILD_EXAMPLES OFF CACHE BOOL "Do not build zlib examples" FORCE)

    set(SDL2IMAGE_INSTALL OFF CACHE BOOL "Do not install SDL_image" FORCE)
    set(SDL2IMAGE_SAMPLES OFF CACHE BOOL "Do not build SDL_image samples" FORCE)
    set(SDL2IMAGE_TESTS OFF CACHE BOOL "Do not build SDL_image tests" FORCE)
    set(SDL2IMAGE_VENDORED ON CACHE BOOL "Use pinned SDL_image dependencies" FORCE)
    set(SDL2IMAGE_DEPS_SHARED OFF CACHE BOOL "Statically link SDL_image dependencies" FORCE)
    set(SDL2IMAGE_BACKEND_STB OFF CACHE BOOL "Use libpng instead of stb_image" FORCE)
    foreach(format AVIF BMP GIF JPG JXL LBM PCX PNM QOI SVG TGA TIF WEBP XCF XPM XV)
        set(SDL2IMAGE_${format} OFF CACHE BOOL "Disable unused SDL_image format" FORCE)
    endforeach()
    set(SDL2IMAGE_PNG ON CACHE BOOL "Enable PNG images" FORCE)
    set(SDL2IMAGE_PNG_SAVE ON CACHE BOOL "Enable PNG output" FORCE)

    set(SDL2NET_INSTALL OFF CACHE BOOL "Do not install SDL_net" FORCE)

    set(SDL2TTF_INSTALL OFF CACHE BOOL "Do not install SDL_ttf" FORCE)
    set(SDL2TTF_SAMPLES OFF CACHE BOOL "Do not build SDL_ttf samples" FORCE)
    set(SDL2TTF_VENDORED ON CACHE BOOL "Use pinned FreeType" FORCE)
    set(SDL2TTF_HARFBUZZ OFF CACHE BOOL "Disable HarfBuzz" FORCE)

    set(PHYSFS_BUILD_STATIC ON CACHE BOOL "Build static PhysFS" FORCE)
    set(PHYSFS_BUILD_SHARED OFF CACHE BOOL "Do not build shared PhysFS" FORCE)
    set(PHYSFS_BUILD_TEST OFF CACHE BOOL "Do not build PhysFS tests" FORCE)
    set(PHYSFS_BUILD_DOCS OFF CACHE BOOL "Do not build PhysFS docs" FORCE)
    set(PHYSFS_DISABLE_INSTALL ON CACHE BOOL "Do not install PhysFS" FORCE)
    set(PHYSFS_TARGETNAME_DIST physfs-dist CACHE STRING "Avoid embedded target collisions" FORCE)
    set(PHYSFS_TARGETNAME_UNINSTALL physfs-uninstall CACHE STRING "Avoid embedded target collisions" FORCE)
    set(PHYSFS_ARCHIVE_ZIP ON CACHE BOOL "Enable ZIP archives" FORCE)
    foreach(archive 7Z GRP WAD HOG MVL QPAK SLB ISO9660 VDF)
        set(PHYSFS_ARCHIVE_${archive} OFF CACHE BOOL "Disable unused PhysFS archive" FORCE)
    endforeach()

    set(BUILD_TESTING OFF CACHE BOOL "Do not build dependency tests" FORCE)
    set(INSTALL_DOCS OFF CACHE BOOL "Do not install libogg documentation" FORCE)
    set(INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "Do not install pkg-config metadata" FORCE)
    set(INSTALL_CMAKE_PACKAGE_MODULE OFF CACHE BOOL "Do not install CMake package metadata" FORCE)

    set(ALSOFT_UTILS OFF CACHE BOOL "Do not build OpenAL Soft utilities" FORCE)
    set(ALSOFT_EXAMPLES OFF CACHE BOOL "Do not build OpenAL Soft examples" FORCE)
    set(ALSOFT_TESTS OFF CACHE BOOL "Do not build OpenAL Soft tests" FORCE)
    set(ALSOFT_INSTALL OFF CACHE BOOL "Do not install OpenAL Soft" FORCE)
    set(ALSOFT_INSTALL_CONFIG OFF CACHE BOOL "Do not install OpenAL Soft configuration" FORCE)
    set(ALSOFT_INSTALL_HRTF_DATA OFF CACHE BOOL "Do not install OpenAL Soft HRTF data" FORCE)
    set(ALSOFT_INSTALL_AMBDEC_PRESETS OFF CACHE BOOL "Do not install OpenAL Soft AmbDec data" FORCE)
    set(ALSOFT_UPDATE_BUILD_VERSION OFF CACHE BOOL "Use the pinned OpenAL Soft version" FORCE)
    set(ALSOFT_ENABLE_MODULES OFF CACHE BOOL "Do not use C++ modules" FORCE)
    set(ALSOFT_DLOPEN OFF CACHE BOOL "Do not dynamically load Android backends" FORCE)
    set(ALSOFT_EAX OFF CACHE BOOL "Disable legacy EAX" FORCE)
    # OpenAL Soft 1.25.2 unconditionally attaches its generated HRTF targets to
    # the library, so keep the built-in default dataset enabled. Installation
    # remains disabled and no external HRTF files are packaged.
    set(ALSOFT_EMBED_HRTF_DATA ON CACHE BOOL "Embed OpenAL Soft's default HRTF dataset" FORCE)
    # Route OpenAL Soft through SDL so SDL's Android audio thread receives
    # THREAD_PRIORITY_AUDIO. OpenAL Soft's direct OpenSL mixer cannot acquire
    # real-time scheduling on stock Android and can underrun during gameplay.
    set(SDL2_DIR "${CMAKE_CURRENT_LIST_DIR}/cmake" CACHE PATH
        "Bundled SDL2 package shim" FORCE)
    set(ALSOFT_BACKEND_OBOE OFF CACHE BOOL "Do not require the external Oboe dependency" FORCE)
    set(ALSOFT_BACKEND_OPENSL OFF CACHE BOOL "Use SDL2 instead of direct OpenSL ES" FORCE)
    set(ALSOFT_REQUIRE_OPENSL OFF CACHE BOOL "Do not require direct OpenSL ES" FORCE)
    set(ALSOFT_BACKEND_SDL2 ON CACHE BOOL "Enable SDL2 OpenAL output" FORCE)
    set(ALSOFT_REQUIRE_SDL2 ON CACHE BOOL "Require bundled SDL2 OpenAL output" FORCE)
    foreach(backend PIPEWIRE PULSEAUDIO ALSA OSS SOLARIS SNDIO WASAPI DSOUND WINMM JACK
            COREAUDIO PORTAUDIO SDL3 WAVE)
        set(ALSOFT_BACKEND_${backend} OFF CACHE BOOL "Disable non-Android OpenAL backend" FORCE)
    endforeach()
    set(LIBTYPE SHARED CACHE STRING "Build OpenAL Soft as a shared LGPL library" FORCE)

    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/external/SDL_image"
        "${CMAKE_BINARY_DIR}/SDL_image"
        EXCLUDE_FROM_ALL
    )
    # zlib's upstream CMake project renames its checked-in zconf.h during an
    # out-of-tree configure. SDL_image only consumes the generated build-tree
    # header, so restore the source header immediately to keep the checkout
    # reproducible and clean.
    set(_barony_zlib_source_dir "${BARONY_REPOSITORY_ROOT}/external/SDL_image/external/zlib")
    if(EXISTS "${_barony_zlib_source_dir}/zconf.h.included"
        AND NOT EXISTS "${_barony_zlib_source_dir}/zconf.h")
        file(RENAME
            "${_barony_zlib_source_dir}/zconf.h.included"
            "${_barony_zlib_source_dir}/zconf.h"
        )
    endif()
    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/external/SDL_net"
        "${CMAKE_BINARY_DIR}/SDL_net"
        EXCLUDE_FROM_ALL
    )
    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/external/SDL_ttf"
        "${CMAKE_BINARY_DIR}/SDL_ttf"
        EXCLUDE_FROM_ALL
    )
    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/external/physfs"
        "${CMAKE_BINARY_DIR}/physfs"
        EXCLUDE_FROM_ALL
    )
    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/external/ogg"
        "${CMAKE_BINARY_DIR}/ogg"
        EXCLUDE_FROM_ALL
    )
    set(OGG_INCLUDE_DIR "${BARONY_REPOSITORY_ROOT}/external/ogg/include" CACHE PATH "Pinned libogg include path" FORCE)
    set(OGG_LIBRARY ogg CACHE STRING "Pinned libogg target" FORCE)
    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/external/vorbis"
        "${CMAKE_BINARY_DIR}/vorbis"
        EXCLUDE_FROM_ALL
    )
    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/external/openal-soft"
        "${CMAKE_BINARY_DIR}/openal-soft"
        EXCLUDE_FROM_ALL
    )

    set(Android 1)
    set(Windows 0)
    set(Apple 0)
    set(Linux 0)
    set(Bsd 0)
    set(Haiku 0)
    set(PANDORA 0)
    set(NOT_DWORD_DEFINED 1)
    set(STEAMWORKS_ENABLED 0)
    set(EOS_ENABLED 0)
    set(PLAYFAB_ENABLED 0)
    set(IMGUI 1)
    set(CURL_ENABLED 0)
    set(THEORAPLAYER_ENABLED 0)
    set(OPUS_ENABLED 0)
    set(FMOD 0)
    set(OPENAL 1)
    set(TREMOR 0)
    set(BUILD_ENV_PR "")
    set(BUILD_ENV_SA "")
    set(BUILD_ENV_DE "")
    set(BUILD_ENV_CC "")
    set(BUILD_ENV_CS "")
    set(BUILD_ENV_GSE "")
    set(BUILD_ENV_PFTID "")
    set(BUILD_ENV_PFHID "")

    set(BARONY_GENERATED_INCLUDE_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated")
    file(MAKE_DIRECTORY "${BARONY_GENERATED_INCLUDE_DIR}")
    configure_file(
        "${BARONY_REPOSITORY_ROOT}/src/Config.hpp.in"
        "${BARONY_GENERATED_INCLUDE_DIR}/Config.hpp"
        @ONLY
    )

    set(GAME_SOURCES)
    add_subdirectory(
        "${BARONY_REPOSITORY_ROOT}/src"
        "${CMAKE_BINARY_DIR}/barony_sources"
    )

    add_library(barony_game SHARED ${GAME_SOURCES})
    target_compile_features(barony_game PRIVATE cxx_std_17)
    target_compile_options(
        barony_game
        PRIVATE
            -Wno-deprecated-declarations
            -Wno-error=format-security
            -Wno-inconsistent-missing-override
            -Wno-parentheses
    )
    target_compile_definitions(
        barony_game
        PRIVATE
            BASE_DATA_DIR="./"
            IMGUI_IMPL_OPENGL_ES3
    )
    target_include_directories(
        barony_game
        PRIVATE
            "${BARONY_GENERATED_INCLUDE_DIR}"
            "${BARONY_REPOSITORY_ROOT}/src"
            "${BARONY_REPOSITORY_ROOT}/external/rapidjson/include"
    )
    target_link_libraries(
        barony_game
        PRIVATE
            SDL2::SDL2
            SDL2::SDL2main
            SDL2_image
            SDL2_net
            SDL2_ttf
            PhysFS::PhysFS-static
            PNG::PNG
            OpenAL::OpenAL
            vorbisfile
            ${ANDROID_LIBRARY}
            ${GLESV3_LIBRARY}
            ${LOG_LIBRARY}
            m
    )
endif()
