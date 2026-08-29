# V3CK3 LAN

**English** | [简体中文](./README.zh-CN.md)

A small open-source LAN launcher for Victoria 3 and Crusader Kings III on Windows x64.

The launcher reads a game profile, prepares the local Steam environment, starts the game, and restores the previous environment when the game exits. LAN lobby and networking support are provided by a pinned [Goldberg Steam Emulator](https://gitlab.com/Mr_Goldberg/goldberg_emulator) build.

This is a small wrapper around Goldberg, not a new networking implementation.

## Status

| Game | Status |
|---|---|
| Victoria 3 | Launcher startup tested on Windows |
| Crusader Kings III | Intended target; current version still needs testing |
| Other games | Not supported or tested |

## Usage

1. Back up the original `steam_api64.dll` in the game's `binaries` directory.
2. Copy all files from the release package into that directory and allow replacement.
3. Check `game-lan.ini` and select the correct game profile.
4. Run `configure-player.cmd` once on every computer. Each player must use a different SteamID64; leaving it blank generates one.
5. Exit the real Steam client completely.
6. Run `launch-game-lan.cmd`.

All players must use the same game version, checksum, mods, App ID, and TCP/UDP port.

## Profiles

The package uses Victoria 3 by default:

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

For Crusader Kings III, change these values:

```ini
game_name=Crusader Kings III
app_id=1158310
game_exe=ck3.exe
launch_arguments=-steam
```

Run `configure-player.cmd` again after changing `app_id`. It updates `steam_settings/steam_appid.txt`. The launcher does not need to be rebuilt.

## Network notes

- Goldberg uses both TCP and UDP. The default port is `47584`.
- This pinned networking implementation uses IPv4 for peer communication.
- Virtual LAN software can be used between computers in different locations if both virtual IPv4 addresses are reachable.
- If peers can ping each other but no lobby appears, add the other peer's virtual IPv4 address to `steam_settings/custom_broadcasts.txt`, one address per line.
- `disable_lan_only.txt` disables Goldberg's non-LAN address filter. Enable virtual-LAN compatibility only when the VPN address is otherwise blocked.

## What the launcher does

The source is [`src/game_lan_launcher.cpp`](./src/game_lan_launcher.cpp). It:

1. Reads `[launcher]` from `game-lan.ini`.
2. Checks the game executable, Goldberg DLLs, App ID, and player SteamID64.
3. Temporarily sets Steam environment variables and `HKCU\Software\Valve\Steam\ActiveProcess`.
4. Starts the configured game with `CreateProcessW`.
5. Waits for the game to exit and restores the previous registry values.

The launcher does not inject a DLL. The game loads the local `steam_api64.dll` from its own directory.

## Build

Requirements:

- Git
- CMake 3.20 or newer
- Visual Studio 2022 with Desktop development with C++
- Windows PowerShell 5.1 or PowerShell 7

Run:

```powershell
.\scripts\build.ps1
.\scripts\package.ps1
.\scripts\verify-package.ps1
```

The package is created in `dist\game-lan`.

Goldberg and vcpkg revisions are pinned in [`SOURCE_LOCK.json`](./SOURCE_LOCK.json). Third-party licensing information is in [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md).

## Scope

This repository contains no game files, DLC unlock configuration, SmartSteamEmu, OnlineFix, or official online-service emulation. Every player should use a lawfully obtained copy of the game.

The launcher is MIT licensed. Goldberg remains under its upstream LGPL license.
