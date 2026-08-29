# V3CK3 LAN

[English](./README.md) | **简体中文**

这是一个用于 Victoria 3 和 Crusader Kings III 的简单开源局域网启动器，支持 Windows x64。

启动器读取游戏配置，准备本地 Steam 环境，启动游戏，并在游戏退出后恢复原有环境。局域网大厅和网络通信由固定版本的 [Goldberg Steam Emulator](https://gitlab.com/Mr_Goldberg/goldberg_emulator) 提供。

这个项目本质上只是 Goldberg 外面的一层小启动器，并没有重新实现一套网络协议。

## 支持状态

| 游戏 | 状态 |
|---|---|
| Victoria 3 | 已完成 Windows 启动验证 |
| Crusader Kings III | 目标游戏，当前版本仍需实机测试 |
| 其他游戏 | 不承诺支持，也没有测试 |

## 使用方法

1. 备份游戏 `binaries` 目录中的原版 `steam_api64.dll`。
2. 把发布包里的所有文件复制到该目录并允许替换。
3. 检查 `game-lan.ini`，选择正确的游戏配置。
4. 每台电脑运行一次 `configure-player.cmd`。每位玩家必须使用不同的 SteamID64；留空会自动生成。
5. 完全退出真正的 Steam 客户端。
6. 运行 `launch-game-lan.cmd`。

所有玩家必须使用相同的游戏版本、校验和、Mod、App ID 和 TCP/UDP 端口。

## 游戏配置

发布包默认配置为 Victoria 3：

```ini
[launcher]
game_name=Victoria 3
app_id=529340
game_exe=victoria3.exe
working_directory=.
steam_client64=steamclient64.dll
steam_api64=steam_api64.dll
steam_settings=steam_settings
launch_arguments=-steam
```

用于 Crusader Kings III 时修改以下内容：

```ini
game_name=Crusader Kings III
app_id=1158310
game_exe=ck3.exe
launch_arguments=-steam
```

修改 `app_id` 后重新运行 `configure-player.cmd`，它会同步更新 `steam_settings/steam_appid.txt`，不需要重新编译启动器。

## 网络说明

- Goldberg 同时使用 TCP 和 UDP，默认端口是 `47584`。
- 当前固定版本使用 IPv4 进行玩家间通信。
- 两台异地电脑只要虚拟 IPv4 能够互通，就可以尝试通过虚拟局域网联机。
- 如果双方能互相 ping 通但看不到大厅，可在 `steam_settings/custom_broadcasts.txt` 中逐行填写对方的虚拟 IPv4 地址。
- `disable_lan_only.txt` 用于关闭 Goldberg 的非局域网地址过滤；只有 VPN 地址被阻止时才需要启用虚拟局域网兼容模式。

## 启动器做了什么

源码位于 [`src/game_lan_launcher.cpp`](./src/game_lan_launcher.cpp)。主要流程是：

1. 读取 `game-lan.ini` 的 `[launcher]` 配置。
2. 检查游戏 EXE、Goldberg DLL、App ID 和玩家 SteamID64。
3. 临时设置 Steam 环境变量和 `HKCU\Software\Valve\Steam\ActiveProcess`。
4. 使用 `CreateProcessW` 启动游戏。
5. 等待游戏退出并恢复原来的注册表值。

启动器不会向游戏注入 DLL。游戏会从自身目录加载本地 `steam_api64.dll`。

## 构建

需要：

- Git
- CMake 3.20 或更高版本
- Visual Studio 2022，并安装“使用 C++ 的桌面开发”
- Windows PowerShell 5.1 或 PowerShell 7

执行：

```powershell
.\scripts\build.ps1
.\scripts\package.ps1
.\scripts\verify-package.ps1
```

成品位于 `dist\game-lan`。

Goldberg 和 vcpkg 的固定版本记录在 [`SOURCE_LOCK.json`](./SOURCE_LOCK.json)，第三方许可证说明见 [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md)。

## 范围

本仓库不包含游戏文件、DLC 解锁配置、SmartSteamEmu、OnlineFix 或官方在线后端模拟。每位玩家都应使用合法取得的游戏副本。

启动器使用 MIT 许可证；Goldberg 继续使用其上游 LGPL 许可证。
