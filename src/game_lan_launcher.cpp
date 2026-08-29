#include <windows.h>

#include <algorithm>
#include <cstdint>
#include <cwchar>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace fs = std::filesystem;

namespace {

constexpr wchar_t kRegistryPath[] = L"Software\\Valve\\Steam\\ActiveProcess";

std::string ToUtf8(const std::wstring& value) {
    if (value.empty()) {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                         static_cast<int>(value.size()), nullptr, 0,
                                         nullptr, nullptr);
    if (size <= 0) {
        return "Windows text conversion failed";
    }
    std::string result(static_cast<std::size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                        result.data(), size, nullptr, nullptr);
    return result;
}

std::wstring FormatWindowsError(DWORD error) {
    wchar_t* buffer = nullptr;
    const DWORD count = FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
            FORMAT_MESSAGE_IGNORE_INSERTS,
        nullptr, error, 0, reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
    std::wstring message = count && buffer ? std::wstring(buffer, count)
                                           : L"Windows error " + std::to_wstring(error);
    if (buffer) {
        LocalFree(buffer);
    }
    while (!message.empty() &&
           (message.back() == L'\r' || message.back() == L'\n' || message.back() == L' ')) {
        message.pop_back();
    }
    return message;
}

[[noreturn]] void Fail(const std::wstring& message) {
    throw std::runtime_error(ToUtf8(message));
}

class UniqueHandle {
public:
    UniqueHandle() = default;
    explicit UniqueHandle(HANDLE handle) : handle_(handle) {}
    ~UniqueHandle() {
        if (handle_ && handle_ != INVALID_HANDLE_VALUE) {
            CloseHandle(handle_);
        }
    }
    UniqueHandle(const UniqueHandle&) = delete;
    UniqueHandle& operator=(const UniqueHandle&) = delete;
    UniqueHandle(UniqueHandle&& other) noexcept : handle_(std::exchange(other.handle_, nullptr)) {}
    UniqueHandle& operator=(UniqueHandle&& other) noexcept {
        if (this != &other) {
            if (handle_ && handle_ != INVALID_HANDLE_VALUE) {
                CloseHandle(handle_);
            }
            handle_ = std::exchange(other.handle_, nullptr);
        }
        return *this;
    }
    HANDLE get() const { return handle_; }

private:
    HANDLE handle_ = nullptr;
};

struct RegistryValue {
    std::wstring name;
    bool existed = false;
    DWORD original_type = REG_NONE;
    std::vector<BYTE> original_data;
    DWORD written_type = REG_NONE;
    std::vector<BYTE> written_data;
};

class RegistryGuard {
public:
    RegistryGuard() {
        DWORD disposition = 0;
        const LONG status = RegCreateKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, nullptr,
                                            REG_OPTION_NON_VOLATILE,
                                            KEY_QUERY_VALUE | KEY_SET_VALUE, nullptr,
                                            &key_, &disposition);
        if (status != ERROR_SUCCESS) {
            Fail(L"Could not open the Steam registry key: " + FormatWindowsError(status));
        }
    }

    ~RegistryGuard() {
        RestoreNoThrow();
        if (key_) {
            RegCloseKey(key_);
        }
    }

    RegistryGuard(const RegistryGuard&) = delete;
    RegistryGuard& operator=(const RegistryGuard&) = delete;

    void SetDword(const std::wstring& name, DWORD value) {
        std::vector<BYTE> data(sizeof(value));
        std::copy_n(reinterpret_cast<const BYTE*>(&value), sizeof(value), data.begin());
        Set(name, REG_DWORD, std::move(data));
    }

    void SetString(const std::wstring& name, const std::wstring& value) {
        const auto byte_count = (value.size() + 1U) * sizeof(wchar_t);
        std::vector<BYTE> data(byte_count);
        std::copy_n(reinterpret_cast<const BYTE*>(value.c_str()), byte_count, data.begin());
        Set(name, REG_SZ, std::move(data));
    }

private:
    RegistryValue ReadOriginal(const std::wstring& name) {
        RegistryValue value;
        value.name = name;
        DWORD size = 0;
        LONG status = RegQueryValueExW(key_, name.c_str(), nullptr, &value.original_type,
                                       nullptr, &size);
        if (status == ERROR_FILE_NOT_FOUND) {
            return value;
        }
        if (status != ERROR_SUCCESS) {
            Fail(L"Could not back up registry value " + name + L": " +
                 FormatWindowsError(status));
        }
        value.existed = true;
        value.original_data.resize(size);
        if (size != 0) {
            status = RegQueryValueExW(key_, name.c_str(), nullptr, &value.original_type,
                                      value.original_data.data(), &size);
            if (status != ERROR_SUCCESS) {
                Fail(L"Could not read registry value " + name + L": " +
                     FormatWindowsError(status));
            }
            value.original_data.resize(size);
        }
        return value;
    }

    void Set(const std::wstring& name, DWORD type, std::vector<BYTE> data) {
        RegistryValue value = ReadOriginal(name);
        const LONG status = RegSetValueExW(key_, name.c_str(), 0, type, data.data(),
                                           static_cast<DWORD>(data.size()));
        if (status != ERROR_SUCCESS) {
            Fail(L"Could not set registry value " + name + L": " +
                 FormatWindowsError(status));
        }
        value.written_type = type;
        value.written_data = std::move(data);
        values_.push_back(std::move(value));
    }

    bool StillOwns(const RegistryValue& value) const {
        DWORD type = REG_NONE;
        DWORD size = 0;
        LONG status = RegQueryValueExW(key_, value.name.c_str(), nullptr, &type, nullptr, &size);
        if (status != ERROR_SUCCESS || type != value.written_type ||
            size != value.written_data.size()) {
            return false;
        }
        std::vector<BYTE> data(size);
        if (size != 0) {
            status = RegQueryValueExW(key_, value.name.c_str(), nullptr, &type, data.data(), &size);
            if (status != ERROR_SUCCESS) {
                return false;
            }
        }
        return data == value.written_data;
    }

    void RestoreNoThrow() noexcept {
        for (auto it = values_.rbegin(); it != values_.rend(); ++it) {
            if (!StillOwns(*it)) {
                continue;
            }
            if (it->existed) {
                RegSetValueExW(key_, it->name.c_str(), 0, it->original_type,
                               it->original_data.empty() ? nullptr : it->original_data.data(),
                               static_cast<DWORD>(it->original_data.size()));
            } else {
                RegDeleteValueW(key_, it->name.c_str());
            }
        }
        values_.clear();
    }

    HKEY key_ = nullptr;
    std::vector<RegistryValue> values_;
};

class EnvironmentGuard {
public:
    EnvironmentGuard(std::wstring name, const std::wstring& value) : name_(std::move(name)) {
        const DWORD required = GetEnvironmentVariableW(name_.c_str(), nullptr, 0);
        if (required != 0) {
            existed_ = true;
            std::vector<wchar_t> buffer(required);
            GetEnvironmentVariableW(name_.c_str(), buffer.data(), required);
            original_.assign(buffer.data());
        }
        if (!SetEnvironmentVariableW(name_.c_str(), value.c_str())) {
            Fail(L"Could not set environment variable " + name_ + L": " +
                 FormatWindowsError(GetLastError()));
        }
    }

    ~EnvironmentGuard() {
        SetEnvironmentVariableW(name_.c_str(), existed_ ? original_.c_str() : nullptr);
    }

    EnvironmentGuard(const EnvironmentGuard&) = delete;
    EnvironmentGuard& operator=(const EnvironmentGuard&) = delete;

private:
    std::wstring name_;
    std::wstring original_;
    bool existed_ = false;
};

std::wstring Trim(std::wstring value) {
    const auto is_space = [](wchar_t ch) { return std::iswspace(ch) != 0; };
    value.erase(value.begin(), std::find_if_not(value.begin(), value.end(), is_space));
    value.erase(std::find_if_not(value.rbegin(), value.rend(), is_space).base(), value.end());
    return value;
}

std::wstring ReadAsciiLine(const fs::path& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) {
        Fail(L"Could not read configuration file: " + path.wstring());
    }
    std::string line;
    std::getline(input, line);
    if (line.size() >= 3 && static_cast<unsigned char>(line[0]) == 0xEF &&
        static_cast<unsigned char>(line[1]) == 0xBB &&
        static_cast<unsigned char>(line[2]) == 0xBF) {
        line.erase(0, 3);
    }
    return Trim(std::wstring(line.begin(), line.end()));
}

std::uint64_t ParseUnsigned64(const std::wstring& text, const std::wstring& source) {
    if (text.empty() ||
        !std::all_of(text.begin(), text.end(), [](wchar_t ch) { return ch >= L'0' && ch <= L'9'; })) {
        Fail(L"The value must be an unsigned decimal integer: " + source);
    }
    try {
        std::size_t consumed = 0;
        const auto value = std::stoull(text, &consumed, 10);
        if (consumed != text.size()) {
            Fail(L"The value contains invalid characters: " + source);
        }
        return value;
    } catch (const std::exception&) {
        Fail(L"The value is out of range: " + source);
    }
}

fs::path ExecutableDirectory() {
    std::vector<wchar_t> buffer(512);
    for (;;) {
        const DWORD count = GetModuleFileNameW(nullptr, buffer.data(),
                                               static_cast<DWORD>(buffer.size()));
        if (count == 0) {
            Fail(L"Could not determine the launcher location: " +
                 FormatWindowsError(GetLastError()));
        }
        if (count < buffer.size() - 1) {
            return fs::path(std::wstring(buffer.data(), count)).parent_path();
        }
        buffer.resize(buffer.size() * 2);
    }
}

std::wstring ReadIni(const fs::path& ini, const wchar_t* key,
                     const wchar_t* default_value = L"") {
    std::vector<wchar_t> buffer(32768);
    const DWORD count = GetPrivateProfileStringW(L"launcher", key, default_value,
                                                  buffer.data(),
                                                  static_cast<DWORD>(buffer.size()),
                                                  ini.c_str());
    return Trim(std::wstring(buffer.data(), count));
}

std::wstring ReadRequiredIni(const fs::path& ini, const wchar_t* key) {
    std::wstring value = ReadIni(ini, key);
    if (value.empty()) {
        Fail(L"Missing required [launcher] setting '" + std::wstring(key) +
             L"' in " + ini.wstring());
    }
    return value;
}

fs::path Resolve(const fs::path& base, const std::wstring& configured) {
    fs::path result(configured);
    if (result.is_relative()) {
        result = base / result;
    }
    std::error_code error;
    const fs::path canonical = fs::weakly_canonical(result, error);
    return error ? result.lexically_normal() : canonical;
}

void RequireFile(const fs::path& path, const wchar_t* label) {
    std::error_code error;
    if (!fs::is_regular_file(path, error)) {
        Fail(std::wstring(L"Missing ") + label + L": " + path.wstring());
    }
}

void RequireDirectory(const fs::path& path, const wchar_t* label) {
    std::error_code error;
    if (!fs::is_directory(path, error)) {
        Fail(std::wstring(L"Missing ") + label + L": " + path.wstring());
    }
}

void EnsureSteamIsNotRunning() {
    HKEY key = nullptr;
    if (RegOpenKeyExW(HKEY_CURRENT_USER, kRegistryPath, 0, KEY_QUERY_VALUE, &key) !=
        ERROR_SUCCESS) {
        return;
    }
    DWORD pid = 0;
    DWORD type = REG_NONE;
    DWORD size = sizeof(pid);
    const LONG status = RegQueryValueExW(key, L"pid", nullptr, &type,
                                         reinterpret_cast<BYTE*>(&pid), &size);
    RegCloseKey(key);
    if (status != ERROR_SUCCESS || type != REG_DWORD || size != sizeof(pid) || pid == 0) {
        return;
    }

    UniqueHandle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid));
    if (!process.get()) {
        return;
    }
    std::vector<wchar_t> path(32768);
    DWORD path_size = static_cast<DWORD>(path.size());
    if (!QueryFullProcessImageNameW(process.get(), 0, path.data(), &path_size)) {
        return;
    }
    const std::wstring executable = fs::path(std::wstring(path.data(), path_size)).filename().wstring();
    if (_wcsicmp(executable.c_str(), L"steam.exe") == 0) {
        Fail(L"The Steam client is still running. Exit Steam completely before "
             L"starting the LAN backend.");
    }
}

std::wstring Quote(const std::wstring& argument) {
    std::wstring result = L"\"";
    std::size_t backslashes = 0;
    for (const wchar_t ch : argument) {
        if (ch == L'\\') {
            ++backslashes;
            continue;
        }
        if (ch == L'\"') {
            result.append(backslashes * 2 + 1, L'\\');
            result.push_back(L'\"');
            backslashes = 0;
            continue;
        }
        result.append(backslashes, L'\\');
        backslashes = 0;
        result.push_back(ch);
    }
    result.append(backslashes * 2, L'\\');
    result.push_back(L'\"');
    return result;
}

int Run(const fs::path& ini_path) {
    RequireFile(ini_path, L"launcher configuration");
    const fs::path base = ini_path.parent_path();
    const std::wstring game_name = ReadIni(ini_path, L"game_name", L"Game");
    const std::wstring app_id_text = ReadRequiredIni(ini_path, L"app_id");
    const std::uint64_t app_id_value = ParseUnsigned64(
        app_id_text, L"[launcher] app_id in " + ini_path.wstring());
    if (app_id_value == 0 || app_id_value > std::numeric_limits<std::uint32_t>::max()) {
        Fail(L"[launcher] app_id must be between 1 and 4294967295: " +
             ini_path.wstring());
    }

    const fs::path game = Resolve(base, ReadRequiredIni(ini_path, L"game_exe"));
    const fs::path work_dir = Resolve(base, ReadIni(ini_path, L"working_directory", L"."));
    const fs::path client64 = Resolve(base, ReadIni(ini_path, L"steam_client64", L"steamclient64.dll"));
    const fs::path api64 = Resolve(base, ReadIni(ini_path, L"steam_api64", L"steam_api64.dll"));
    const fs::path settings = Resolve(base, ReadIni(ini_path, L"steam_settings", L"steam_settings"));
    const std::wstring launch_arguments = ReadIni(ini_path, L"launch_arguments");

    RequireFile(game, L"game executable");
    RequireDirectory(work_dir, L"game working directory");
    RequireFile(client64, L"Goldberg steamclient64.dll");
    RequireFile(api64, L"Goldberg steam_api64.dll");
    RequireDirectory(settings, L"steam_settings directory");

    std::error_code path_error;
    if (!fs::equivalent(game.parent_path(), work_dir, path_error) || path_error) {
        Fail(L"working_directory must be the directory containing the game executable");
    }
    path_error.clear();
    if (!fs::equivalent(api64.parent_path(), game.parent_path(), path_error) || path_error) {
        Fail(L"steam_api64.dll must be in the same directory as the game executable");
    }
    path_error.clear();
    if (!fs::equivalent(client64.parent_path(), game.parent_path(), path_error) || path_error) {
        Fail(L"steamclient64.dll must be in the same directory as the game executable");
    }
    path_error.clear();
    if (!fs::equivalent(settings, api64.parent_path() / L"steam_settings", path_error) ||
        path_error) {
        Fail(L"steam_settings must be next to the Goldberg DLLs");
    }

    const fs::path appid_file = settings / L"steam_appid.txt";
    const fs::path steamid_file = settings / L"force_steamid.txt";
    const fs::path setup_marker = settings / L"player_setup_required.txt";
    std::error_code marker_error;
    if (fs::is_regular_file(setup_marker, marker_error)) {
        Fail(L"Player settings have not been configured. Run configure-player.cmd first.");
    }
    if (ReadAsciiLine(appid_file) != app_id_text) {
        Fail(L"steam_appid.txt must match [launcher] app_id (" + app_id_text +
             L"): " + appid_file.wstring());
    }
    const std::uint64_t steam_id =
        ParseUnsigned64(ReadAsciiLine(steamid_file), steamid_file.wstring());
    if (steam_id < 76561197960265729ULL || steam_id > 76561202255233023ULL) {
        Fail(L"force_steamid.txt is not a valid individual-account SteamID64: " +
             steamid_file.wstring());
    }

    EnvironmentGuard app_id(L"SteamAppId", app_id_text);
    EnvironmentGuard game_id(L"SteamGameId", app_id_text);
    EnvironmentGuard overlay_id(L"SteamOverlayGameId", app_id_text);

    EnsureSteamIsNotRunning();
    RegistryGuard registry;
    registry.SetDword(L"ActiveUser", static_cast<DWORD>(steam_id & 0xFFFFFFFFULL));
    registry.SetDword(L"pid", GetCurrentProcessId());
    registry.SetDword(L"Universe", 1);
    registry.SetString(L"SteamClientDll64", client64.wstring());

    std::wstring command_line = Quote(game.wstring());
    if (!launch_arguments.empty()) {
        command_line += L" " + launch_arguments;
    }
    std::vector<wchar_t> mutable_command(command_line.begin(), command_line.end());
    mutable_command.push_back(L'\0');

    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(game.c_str(), mutable_command.data(), nullptr, nullptr, FALSE,
                        CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT, nullptr,
                        work_dir.c_str(), &startup, &process)) {
        Fail(L"Could not start " + game_name + L": " +
             FormatWindowsError(GetLastError()));
    }
    UniqueHandle process_handle(process.hProcess);
    UniqueHandle thread_handle(process.hThread);

    if (ResumeThread(thread_handle.get()) == static_cast<DWORD>(-1)) {
        TerminateProcess(process_handle.get(), ERROR_PROCESS_ABORTED);
        Fail(L"Could not resume the " + game_name + L" process: " +
             FormatWindowsError(GetLastError()));
    }

    std::wcout << game_name
               << L" was started through the open-source Steam backend. Keep this "
                  L"window open until the game exits.\n";
    const DWORD wait = WaitForSingleObject(process_handle.get(), INFINITE);
    if (wait != WAIT_OBJECT_0) {
        Fail(L"An error occurred while waiting for " + game_name + L" to exit: " +
             FormatWindowsError(GetLastError()));
    }
    DWORD exit_code = 1;
    if (!GetExitCodeProcess(process_handle.get(), &exit_code)) {
        Fail(L"Could not read the " + game_name + L" exit code: " +
             FormatWindowsError(GetLastError()));
    }
    return static_cast<int>(exit_code);
}

void PrintUsage() {
    std::wcout << L"Usage: game-lan-launcher.exe [--config <game-lan.ini>]\n";
}

}  // namespace

int wmain(int argc, wchar_t* argv[]) {
    try {
        fs::path config = ExecutableDirectory() / L"game-lan.ini";
        if (argc == 2 && (std::wstring(argv[1]) == L"--help" ||
                          std::wstring(argv[1]) == L"-h")) {
            PrintUsage();
            return 0;
        }
        if (argc == 3 && std::wstring(argv[1]) == L"--config") {
            config = fs::absolute(fs::path(argv[2]));
        } else if (argc != 1) {
            PrintUsage();
            return 2;
        }
        return Run(config);
    } catch (const std::exception& error) {
        std::cerr << "game-lan-launcher: " << error.what() << '\n';
        return 1;
    }
}
