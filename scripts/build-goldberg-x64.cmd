@echo off
setlocal

rem Reproducible x64-only form of Goldberg's pinned
rem build_win_release_experimental.bat. The Goldberg sources built by this
rem script remain licensed under LGPL-3.0-or-later and their own notices.

if "%~4"=="" (
    echo Usage: build-goldberg-x64.cmd SOURCE VCPKG_X64 VSDEVCMD OUTPUT
    exit /b 2
)

set "SOURCE=%~1"
set "PROTOBUF_X64_DIRECTORY=%~2"
set "VSDEVCMD=%~3"
set "OUTPUT=%~4"
set "PROTOC_X64_EXE=%PROTOBUF_X64_DIRECTORY%\tools\protobuf\protoc.exe"

if exist "%PROTOBUF_X64_DIRECTORY%\lib\libprotobuf-lite.lib" (
    set "PROTOBUF_X64_LIBRARY=%PROTOBUF_X64_DIRECTORY%\lib\libprotobuf-lite.lib"
) else (
    set "PROTOBUF_X64_LIBRARY=%PROTOBUF_X64_DIRECTORY%\lib\libprotobuf.lib"
)

if not exist "%PROTOC_X64_EXE%" (
    echo Missing protoc: %PROTOC_X64_EXE%
    exit /b 3
)
if not exist "%PROTOBUF_X64_LIBRARY%" (
    echo Missing protobuf library: %PROTOBUF_X64_LIBRARY%
    exit /b 3
)

if not exist "%OUTPUT%" mkdir "%OUTPUT%"
if errorlevel 1 exit /b %errorlevel%
del /Q "%OUTPUT%\steam_api64.dll" "%OUTPUT%\steamclient64.dll" 2>nul

call "%VSDEVCMD%" -no_logo -arch=x64 -host_arch=x64
if errorlevel 1 exit /b %errorlevel%

cd /d "%SOURCE%"
if errorlevel 1 exit /b %errorlevel%

"%PROTOC_X64_EXE%" -I.\dll --cpp_out=.\dll .\dll\net.proto
if errorlevel 1 exit /b %errorlevel%

cl dll\rtlgenrandom.c dll\rtlgenrandom.def
if errorlevel 1 exit /b %errorlevel%

cl /LD /DEMU_RELEASE_BUILD /DEMU_EXPERIMENTAL_BUILD /DCONTROLLER_SUPPORT /DEMU_OVERLAY /DNDEBUG /IImGui "/I%PROTOBUF_X64_DIRECTORY%\include" /Ioverlay_experimental dll\*.cpp dll\*.cc detours\*.cpp controller\gamepad.c ImGui\*.cpp ImGui\backends\imgui_impl_dx*.cpp ImGui\backends\imgui_impl_win32.cpp ImGui\backends\imgui_impl_vulkan.cpp ImGui\backends\imgui_impl_opengl3.cpp ImGui\backends\imgui_win_shader_blobs.cpp overlay_experimental\*.cpp overlay_experimental\windows\*.cpp overlay_experimental\System\*.cpp "%PROTOBUF_X64_LIBRARY%" opengl32.lib Iphlpapi.lib Ws2_32.lib rtlgenrandom.lib Shell32.lib Winmm.lib /EHsc /MP12 /Ox /link /debug:none "/OUT:%OUTPUT%\steam_api64.dll"
if errorlevel 1 exit /b %errorlevel%

cl /LD /DEMU_RELEASE_BUILD /DEMU_EXPERIMENTAL_BUILD /DNDEBUG steamclient.cpp /EHsc /MP4 /Ox /link /debug:none "/OUT:%OUTPUT%\steamclient64.dll"
if errorlevel 1 exit /b %errorlevel%

exit /b 0
