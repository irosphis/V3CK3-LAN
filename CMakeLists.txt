cmake_minimum_required(VERSION 3.20)

project(game_lan_launcher VERSION 0.2.0 LANGUAGES CXX)

if(NOT WIN32)
    message(FATAL_ERROR "game-lan-launcher targets Windows because it configures the Windows Steam registry interface")
endif()

add_executable(game-lan-launcher
    src/game_lan_launcher.cpp
)

target_compile_features(game-lan-launcher PRIVATE cxx_std_17)
target_compile_definitions(game-lan-launcher PRIVATE
    UNICODE
    _UNICODE
    WIN32_LEAN_AND_MEAN
    NOMINMAX
)
target_link_libraries(game-lan-launcher PRIVATE advapi32)

if(MSVC)
    target_compile_options(game-lan-launcher PRIVATE /W4 /permissive- /utf-8)
else()
    target_compile_options(game-lan-launcher PRIVATE -Wall -Wextra -Wpedantic)
endif()

install(TARGETS game-lan-launcher RUNTIME DESTINATION .)
