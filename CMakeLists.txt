cmake_minimum_required(VERSION 3.20)
project(ReContra VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_C_STANDARD 23)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Strictly enforce mandatory compiler warnings and safety
add_compile_options(
    -Wall
    -Wextra
    -Wpedantic
    -Wconversion
    -Werror
)

# Sandy Bridge Hardware Guard: OptiPlex 390 is AVX-only (no AVX2 / FMA3)
if (CMAKE_SYSTEM_PROCESSOR MATCHES "x86_64|AMD64")
    message(STATUS "x86_64 target detected: Enforcing Sandy Bridge AVX compatibility (-mno-avx2)")
    add_compile_options(-mno-avx2)
endif()

# Find SDL3
find_package(SDL3 CONFIG QUIET)
if (NOT SDL3_FOUND)
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(SDL3 REQUIRED sdl3)
endif()

include_directories(src)

# Core ReContra static library
add_library(recontra_core STATIC
    src/core/crypto.c
    src/rom/rom_loader.c
    src/rom/chr_extractor.c
    src/rom/level_loader.c
    src/render/palette.c
    src/render/ppu.c
    src/render/nametable.c
    src/audio/apu.c
    src/audio/sound_engine.c
    src/game/collision.c
    src/game/player.c
    src/game/game_runtime.c
)
target_include_directories(recontra_core PUBLIC src)

# Main Game Executable
add_executable(contra src/main.cpp)
target_link_libraries(contra PRIVATE recontra_core)

if (TARGET SDL3::SDL3)
    target_link_libraries(contra PRIVATE SDL3::SDL3)
else()
    target_include_directories(contra PRIVATE ${SDL3_INCLUDE_DIRS})
    target_link_libraries(contra PRIVATE ${SDL3_LIBRARIES})
endif()

# Headless & Unit Testing Harness
enable_testing()

find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(TEST_RUNNER ${Python3_EXECUTABLE} "${CMAKE_SOURCE_DIR}/scripts/test_runner.py")

add_executable(test_rom_loader tests/test_rom_loader.cpp)
target_link_libraries(test_rom_loader PRIVATE recontra_core)
add_test(NAME test_rom_loader COMMAND ${TEST_RUNNER} $<TARGET_FILE:test_rom_loader> "${CMAKE_SOURCE_DIR}/Contra (USA).nes")

add_executable(test_chr_extractor tests/test_chr_extractor.cpp)
target_link_libraries(test_chr_extractor PRIVATE recontra_core)
add_test(NAME test_chr_extractor COMMAND ${TEST_RUNNER} $<TARGET_FILE:test_chr_extractor> "${CMAKE_SOURCE_DIR}/Contra (USA).nes")

add_executable(test_level_loader tests/test_level_loader.cpp)
target_link_libraries(test_level_loader PRIVATE recontra_core)
add_test(NAME test_level_loader COMMAND ${TEST_RUNNER} $<TARGET_FILE:test_level_loader> "${CMAKE_SOURCE_DIR}/Contra (USA).nes")

add_executable(test_ppu_renderer tests/test_ppu_renderer.cpp)
target_link_libraries(test_ppu_renderer PRIVATE recontra_core)
add_test(NAME test_ppu_renderer COMMAND ${TEST_RUNNER} $<TARGET_FILE:test_ppu_renderer> "${CMAKE_SOURCE_DIR}/Contra (USA).nes")

add_executable(test_apu_audio tests/test_apu_audio.cpp)
target_link_libraries(test_apu_audio PRIVATE recontra_core)
add_test(NAME test_apu_audio COMMAND ${TEST_RUNNER} $<TARGET_FILE:test_apu_audio> "${CMAKE_SOURCE_DIR}/Contra (USA).nes")

add_executable(test_game_physics tests/test_game_physics.cpp)
target_link_libraries(test_game_physics PRIVATE recontra_core)
add_test(NAME test_game_physics COMMAND ${TEST_RUNNER} $<TARGET_FILE:test_game_physics> "${CMAKE_SOURCE_DIR}/Contra (USA).nes")

# Headless Deterministic Replay & Hash Verification Test
add_test(
    NAME test_headless_deterministic_verify
    COMMAND ${TEST_RUNNER} $<TARGET_FILE:contra> --rom "${CMAKE_SOURCE_DIR}/Contra (USA).nes" --headless --frames 3600 --verify-hash
)
