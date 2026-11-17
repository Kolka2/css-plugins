# css-plugins

[Русская версия](README.ru.md)

SourceMod plugins for Counter-Strike: Source.

The code is written with AI assistance ([Claude Code](https://claude.com/claude-code)) under the author's direction. Not everything has been verified on a live server yet: each plugin has a `TEST_CHECKLIST.md` that lists what has and has not been checked.

## Requirements

- Counter-Strike: Source dedicated server (February 2025 update, 64-bit)
- Metamod:Source 1.12
- SourceMod 1.12

Only CS:S is supported.

## Plugins

| Plugin | What it does | Status | Docs |
|---|---|---|---|
| `nadethrow` | CS:GO-style grenade throws: left click, left + right click and right click give throws of different strength. Has an API for other plugins. | Complete. Core mechanic tested on a server, the rest of the checklist is pending. | [README](docs/nadethrow/README.md), [checklist](docs/nadethrow/TEST_CHECKLIST.md) |
| `teammoney` | Shows each player the money, grenades and defuse kits of their team during freeze time. | Complete, awaiting verification on a server. | [README](docs/teammoney/README.md), [checklist](docs/teammoney/TEST_CHECKLIST.md) |
| `warmup` | A warmup for CS:S, which has none built in: endless round, respawn, $16000 and open buying, no bomb. Game modes drive it through an API; also works on its own. Moved from [css-retakes](https://github.com/Kolka2/css-retakes). | Complete. Tested on a server together with Retakes. | [README](docs/warmup/README.md), [checklist](docs/warmup/TEST_CHECKLIST.md) |

Planned: a grenade practice mode (`nadepractice`), saved lineups and executes (`lineups`, `executes`), bot control and smarter bots (`botcontrol`, `botassist`, `botnav`), a silent knife deploy for other players (`knifesound`), fake defuse and grenades while defusing (`defusetweaks`).

Player-facing text is translated into English and Russian and shown in each player's own language.

## Installation

There are no prebuilt binaries yet, so build the plugins first (see below). Then copy to the server's `cstrike/` folder:

- `build/<plugin>.smx` → `addons/sourcemod/plugins/`
- `translations/` → `addons/sourcemod/translations/`

ConVars and plugin-specific notes are in each plugin's README.

## Building

The SourcePawn compiler and the SourceMod include files are not part of this repository. Take them from a SourceMod 1.12 package:

1. Download SourceMod 1.12 for your OS from <https://www.sourcemod.net/downloads.php>.
2. From `addons/sourcemod/scripting/` in the package, copy into the `tools/` folder of this repository:
   - the compiler: `spcomp` on Linux, `spcomp64.exe` or `spcomp.exe` on Windows;
   - the whole `include/` folder, as `tools/include/`.

The result:

```
tools/
  spcomp            (or spcomp64.exe / spcomp.exe)
  include/
    sourcemod.inc
    ...
```

Then run from the repository root (on Windows, in Git Bash or MSYS2):

```
./build.sh              # build every plugin into build/
./build.sh nadethrow    # build one plugin
```

To use a compiler from another location, set `SPCOMP=/path/to/spcomp`. The include files are still read from `tools/include/`.

## Repository layout

| Path | Contents |
|---|---|
| `scripting/` | plugin sources; `scripting/include/` holds their public APIs |
| `translations/` | translation files (English and Russian) |
| `docs/<plugin>/` | README, test checklist and work log of each plugin |
| `templates/` | templates: a service plugin, its API and a plugin with an optional dependency |
| `ARCHITECTURE.md` | architecture and coding rules for all plugins |
| `CLAUDE.md` | rules for the AI agent |
| `tasks/` | task descriptions for the AI agent and their queue |
| `build.sh` | build script |

## Development

Plugins are developed in sessions with an AI coding agent, and the files it works from are kept in the repository:

- `CLAUDE.md` — working rules for the agent: build, code style, commits.
- `ARCHITECTURE.md` — plugin layers, dependencies, naming and API rules.
- `tasks/` — a task description per plugin; `tasks/README.md` is the queue.
- `docs/<plugin>/PROGRESS.md` — the current state of the work and the decisions made.
- `docs/<plugin>/TEST_CHECKLIST.md` — what has to be checked on a real server. There is no CS:S server in the development environment, so everything that depends on engine behaviour is marked `CSS-VERIFY` in the code and listed here.

These working documents are in Russian. Code comments, ConVar descriptions and log messages are in English.

## License

[GPL-3.0](LICENSE). The plugins are built on [SourceMod](https://www.sourcemod.net/) by AlliedModders.
