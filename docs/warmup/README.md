# warmup — разминка для CS:S

[English version below](#english)

Сервис. В CS:S нет встроенной разминки (нет кваров `mp_warmup_*` и свойства `m_bWarmupPeriod`), поэтому её ведёт этот плагин. Он не привязан к какому-либо режиму: режим управляет им через `scripting/include/warmup.inc`, а без режима плагин работает сам (`sm_warmup_autostart 1`).

Плагин перенесён из [Kolka2/css-retakes](https://github.com/Kolka2/css-retakes), где он был написан для режима Retakes; история его изменений осталась там. Retakes использует его как необязательную зависимость.

Основное проверено на сервере вместе с Retakes: бесконечный раунд, респаун, отсутствие бомбы, смена команды, отсчёт, вето на конец разминки, краевые случаи. Что ещё не проверено — в [TEST_CHECKLIST.md](TEST_CHECKLIST.md).

## Что происходит в разминке

- раунд не заканчивается, убитые появляются снова через `sm_warmup_respawn_time` секунд;
- у всех $16000 при появлении и снова после каждой покупки, закупка открыта всё время (плагин на время разминки поднимает `mp_buytime`);
- бомбы нет: C4 убирается у игроков, с земли и установленная;
- команду можно выбирать и менять свободно, в том числе переходить между T и CT;
- разминка заканчивается по таймеру и/или когда набралось нужное число людей, после чего игра перезапускается.

Все игровые квары, которые плагин меняет на время разминки, запоминаются при её старте и возвращаются при её конце, при смене карты и при выгрузке плагина.

## Установка

- `build/warmup.smx` → `addons/sourcemod/plugins/`
- `translations/warmup.phrases.txt`, `translations/ru/warmup.phrases.txt` → `addons/sourcemod/translations/` (и `ru/`)
- для плагинов, использующих API: `scripting/include/warmup.inc`

Зависимостей нет (sdktools, sdkhooks, cstrike). Без gamedata.

## Квары

Конфиг: `cfg/sourcemod/warmup.cfg` (создаётся при первом запуске).

| Квар | По умолчанию | Смысл |
|---|---|---|
| `sm_warmup_enabled` | `1` | можно ли вообще запускать разминку; `0` также завершает идущую |
| `sm_warmup_autostart` | `0` | `1` — запускать разминку на старте каждой карты. Оставьте `0`, если разминку запускает режим (Retakes делает это сам по `sm_retakes_warmuptime`) |
| `sm_warmup_time` | `25` | длительность по умолчанию, секунды; `0` — без ограничения по времени. Используется автозапуском и командой `sm_warmup` без аргумента |
| `sm_warmup_min_players` | `1` | сколько людей нужно на сервере. Если время ограничено, отсчёт идёт только пока их не меньше (и начинается заново, если стало меньше). Если время не ограничено, разминка заканчивается, как только их набралось. `0` — людей не ждать |
| `sm_warmup_respawn_time` | `1.5` | через сколько секунд после смерти игрок появляется снова |
| `sm_warmup_infinite_money` | `1` | `1` — $16000 при появлении и после каждой покупки; `0` — деньги не трогать |
| `sm_warmup_buy_anywhere` | `0` | `1` — покупать можно в любой точке карты, а не только в зоне закупки |
| `sm_warmup_restart_delay` | `1` | через сколько секунд после конца разминки перезапускается игра (`mp_restartgame`); `0` — не перезапускать |
| `sm_warmup_debug` | `0` | `1` — писать в `addons/sourcemod/logs/warmup_debug.log`, что делает разминка: старт и конец, заблокированные концы раунда, рестарты раунда внутри разминки, опустевшие команды, удалённые и отвергнутые бомбы |
| `sm_warmup_version` | — | версия плагина |

Время и число людей сочетаются так:

| `sm_warmup_time` | `sm_warmup_min_players` | Когда заканчивается разминка |
|---|---|---|
| > 0 | > 0 | через заданное время, которое идёт только пока людей достаточно |
| > 0 | 0 | через заданное время, которое идёт пока на сервере есть хотя бы один человек |
| 0 | > 0 | как только набралось нужное число людей |
| 0 | 0 | только по команде `sm_warmup_end` или по вызову режима |

## Команды

Админ-команды (флаг смены карты, `g`):

- `sm_warmup [секунды]` — начать или перезапустить разминку (`0` — без ограничения по времени, без аргумента — `sm_warmup_time`);
- `sm_warmup_end` — закончить разминку.

## Как это работает

- **Бесконечный раунд.** Форвард `CS_OnTerminateRound` возвращает `Plugin_Handled`, а часы раунда (`m_iRoundTime` правил игры) продлеваются раньше, чем истекают. Исключение — «Game Commencing» (первый человек на пустом сервере): этот рестарт игра делает всё равно.
- **Респаун** — `CS_RespawnPlayer` через `sm_warmup_respawn_time` после смерти, если игрок в команде и выбрал модель (`m_iClass` не 0).
- **Деньги** — `m_iAccount` при появлении и на кадре после покупки (`CS_OnBuyCommand`). Закупка открыта, потому что `mp_buytime` на время разминки поднят до 1440 минут; с `sm_warmup_buy_anywhere 1` плагин каждый кадр выставляет игроку `m_bInBuyZone`.
- **Бомба.** Игра выдаёт C4 при рестарте раунда и ботам при входе. Плагин удаляет её при старте разминки и раз в секунду, а `SDKHook_WeaponCanUse` не даёт её взять (отвергнутая бомба удаляется). Нужны обе защиты: так показали логи.
- **Смена команды.** Команда `jointeam` между T и CT перехватывается: плагин сам переводит игрока и сразу респаунит его с моделью новой команды.
- **Квары** меняются через временную установку: исходное значение запоминается, изменение квара кем-то другим во время разминки записывается в debug-лог, и при любом выходе из разминки значение возвращается.

## API

`scripting/include/warmup.inc`, библиотека `WARMUP_LIBRARY` (`"warmup"`), версия API `WARMUP_API_VERSION` (1).

| | Что делает |
|---|---|
| `bool Warmup_IsActive()` | идёт ли разминка |
| `bool Warmup_Start(int seconds = -1)` | начать или перезапустить; `0` — без лимита, `-1` — `sm_warmup_time`. `false`, если плагин выключен |
| `bool Warmup_End(bool restartGame = true)` | закончить сразу, без `Warmup_OnEnding`; `false`, если разминки не было |
| `int Warmup_GetApiVersion()` | версия API загруженного плагина |
| `forward void Warmup_OnStart(int seconds)` | разминка началась (или перезапущена) |
| `forward Action Warmup_OnEnding()` | вето: разминка хочет закончиться сама; `Plugin_Handled` — подождать, спрашивается снова каждую секунду. Не вызывается при `Warmup_End()`, смене карты и выгрузке |
| `forward void Warmup_OnEnd(WarmupEndReason reason)` | разминка закончилась, квары возвращены. Причины: `WarmupEnd_Finished`, `WarmupEnd_Forced`, `WarmupEnd_MapChange`, `WarmupEnd_PluginUnload` |

Подключение как необязательной зависимости — по разделу 6 `ARCHITECTURE.md`; пример — `scripting/retakes/warmup_link.sp` в css-retakes.

## Известные ограничения

- Отсчёт идёт только пока на сервере есть люди и начинается заново, когда заходит первый человек (решение владельца, настройки «считать и на пустом сервере» нет).
- Первый человек на пустом сервере вызывает «Game Commencing»: раунд разминки один раз перезапускается.
- Награда за убийство и деньги вне разминки плагин не трогает: этим владеет режим.

---

# English

Service. CS:S has no built-in warmup (no `mp_warmup_*` cvars and no `m_bWarmupPeriod` property), so this plugin runs one. It is not tied to any game mode: a mode drives it through `scripting/include/warmup.inc`, and without a mode the plugin works on its own (`sm_warmup_autostart 1`).

The plugin was moved here from [Kolka2/css-retakes](https://github.com/Kolka2/css-retakes), where it was written for the Retakes mode; its change history stayed there. Retakes uses it as an optional dependency.

The main parts were tested on a server together with Retakes: the endless round, respawn, no bomb, team changes, the countdown, the veto on the warmup end, edge cases. What is still unchecked is in [TEST_CHECKLIST.md](TEST_CHECKLIST.md) (in Russian).

## What happens during a warmup

- the round never ends, the dead respawn after `sm_warmup_respawn_time` seconds;
- everybody has $16000 on spawn and again after every purchase, and buying stays open the whole time (the plugin raises `mp_buytime` for the duration);
- there is no bomb: the C4 is removed from players, from the ground and when planted;
- players pick and change teams freely, including T <-> CT;
- the warmup ends by time and/or when enough humans have joined, then the game restarts.

Every game cvar the plugin changes for the warmup is remembered when the warmup starts and restored when it ends, on a map change and when the plugin is unloaded.

## Installation

- `build/warmup.smx` → `addons/sourcemod/plugins/`
- `translations/warmup.phrases.txt`, `translations/ru/warmup.phrases.txt` → `addons/sourcemod/translations/` (and `ru/`)
- for plugins that use the API: `scripting/include/warmup.inc`

No dependencies (sdktools, sdkhooks, cstrike). No gamedata.

## ConVars

Config: `cfg/sourcemod/warmup.cfg` (generated on the first run).

| ConVar | Default | Meaning |
|---|---|---|
| `sm_warmup_enabled` | `1` | whether warmups can be started at all; `0` also ends a running one |
| `sm_warmup_autostart` | `0` | `1` — start a warmup on every map start. Leave at `0` when a game mode starts it (Retakes does, using `sm_retakes_warmuptime`) |
| `sm_warmup_time` | `25` | default length in seconds; `0` — no time limit. Used by the autostart and by `sm_warmup` without an argument |
| `sm_warmup_min_players` | `1` | humans needed on the server. With a time limit the countdown only runs while at least this many are present (and starts over if there are fewer). Without a time limit the warmup ends as soon as this many are present. `0` — do not wait for players |
| `sm_warmup_respawn_time` | `1.5` | seconds between a death and the respawn |
| `sm_warmup_infinite_money` | `1` | `1` — $16000 on spawn and after every purchase; `0` — leave the money alone |
| `sm_warmup_buy_anywhere` | `0` | `1` — players can buy anywhere on the map, not only in the buy zones |
| `sm_warmup_restart_delay` | `1` | seconds until the game restarts after the warmup (`mp_restartgame`); `0` — do not restart |
| `sm_warmup_debug` | `0` | `1` — write what the warmup does (start and end, blocked round ends, round restarts inside the warmup, emptied teams, removed and refused bombs) to `addons/sourcemod/logs/warmup_debug.log` |
| `sm_warmup_version` | — | plugin version |

How the time and the player count combine:

| `sm_warmup_time` | `sm_warmup_min_players` | When the warmup ends |
|---|---|---|
| > 0 | > 0 | after the given time, which only runs while enough humans are present |
| > 0 | 0 | after the given time, which runs while at least one human is on the server |
| 0 | > 0 | as soon as enough humans are present |
| 0 | 0 | only by `sm_warmup_end` or when the game mode ends it |

## Commands

Admin commands (map-change flag, `g`):

- `sm_warmup [seconds]` — start or restart the warmup (`0` — no time limit, no argument — `sm_warmup_time`);
- `sm_warmup_end` — end the warmup.

## How it works

- **Endless round.** The `CS_OnTerminateRound` forward returns `Plugin_Handled`, and the round clock (`m_iRoundTime` of the game rules) is extended before it runs out. The exception is "Game Commencing" (the first human on an empty server): the game does that restart anyway.
- **Respawn** — `CS_RespawnPlayer` `sm_warmup_respawn_time` after a death, if the player is on a team and has picked a model (`m_iClass` is not 0).
- **Money** — `m_iAccount` on spawn and on the frame after a purchase (`CS_OnBuyCommand`). Buying stays open because `mp_buytime` is raised to 1440 minutes for the warmup; with `sm_warmup_buy_anywhere 1` the plugin sets `m_bInBuyZone` for the player every frame.
- **The bomb.** The game gives out the C4 on a round restart and to bots as they join. The plugin removes it at the warmup start and once a second, and `SDKHook_WeaponCanUse` keeps players from taking it (a refused bomb is removed). Both protections are needed, as the logs showed.
- **Team changes.** The `jointeam` command between T and CT is intercepted: the plugin moves the player itself and respawns them right away with the model of the new team.
- **Cvars** are changed temporarily: the original value is remembered, a change by somebody else during the warmup is written to the debug log, and the value comes back on any exit from the warmup.

## API

`scripting/include/warmup.inc`, library `WARMUP_LIBRARY` (`"warmup"`), API version `WARMUP_API_VERSION` (1).

| | What it does |
|---|---|
| `bool Warmup_IsActive()` | whether a warmup is running |
| `bool Warmup_Start(int seconds = -1)` | start or restart; `0` — no limit, `-1` — `sm_warmup_time`. `false` if the plugin is disabled |
| `bool Warmup_End(bool restartGame = true)` | end it right away, without `Warmup_OnEnding`; `false` if no warmup was running |
| `int Warmup_GetApiVersion()` | API version of the loaded plugin |
| `forward void Warmup_OnStart(int seconds)` | a warmup started (or was restarted) |
| `forward Action Warmup_OnEnding()` | veto: the warmup wants to end on its own; `Plugin_Handled` — wait, asked again every second. Not called on `Warmup_End()`, a map change or an unload |
| `forward void Warmup_OnEnd(WarmupEndReason reason)` | the warmup ended, the cvars are restored. Reasons: `WarmupEnd_Finished`, `WarmupEnd_Forced`, `WarmupEnd_MapChange`, `WarmupEnd_PluginUnload` |

How to use it as an optional dependency: section 6 of `ARCHITECTURE.md`; an example is `scripting/retakes/warmup_link.sp` in css-retakes.

## Known limitations

- The countdown only runs while humans are on the server and starts over when the first human joins (the owner's decision; there is no "count on an empty server" setting).
- The first human on an empty server causes "Game Commencing": the warmup round restarts once.
- The plugin does not touch the kill award or the money outside the warmup: the game mode owns them.
