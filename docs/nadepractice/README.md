# nadepractice — режим тренировки гранат для CS:S

[English version below](#english)

Плагин SourceMod 1.12 для Counter-Strike: Source: бесконечные гранаты без урона, трассер настоящих бросков, база лайнапов по картам, подсказки «куда встать и куда навестись», повтор броска и предпросмотр траектории до броска. Всё, что рисуется, видит только сам игрок, поэтому несколько человек тренируются одновременно.

> **Статус.** Первая версия проверена на сервере (результаты — в [TEST_CHECKLIST.md](TEST_CHECKLIST.md)), идёт доработка по замечаниям (`tasks/PRACTICE_TASK.md`, этапы 7–15). Всё, что зависит от движка и ещё не проверено, помечено в коде `CSS-VERIFY` и собрано в чек-листе.

- Слой по `ARCHITECTURE.md`: **режим**. Зависимостей нет, gamedata/DHooks и сторонние библиотеки не используются.
- Владеет (пока режим активен): деньгами, гранатами и уроном игроков, числом ботов (`bot_quota 0`), своими временными кварами, базой лайнапов.

## Установка

1. `build/nadepractice.smx` → `addons/sourcemod/plugins/`
2. `translations/nadepractice.phrases.txt` → `addons/sourcemod/translations/`, `translations/ru/nadepractice.phrases.txt` → `addons/sourcemod/translations/ru/`
3. Перезапустить карту. Появится `cfg/sourcemod/nadepractice.cfg` с кварами.
4. Запуск режима: `sm_nadepractice_start` (админ, флаг changemap) или `sm_nadepractice_autostart 1`.

Папку `addons/sourcemod/configs/nadepractice/lineups/` плагин создаёт сам при первом `!save`.

Режим рассчитан на отдельную конфигурацию сервера: не загружайте его вместе с Retakes и другими режимами (см. `ARCHITECTURE.md`, раздел 13).

## Что меняет режим

При запуске ставятся временные квары, при остановке (команда, смена карты, выгрузка плагина, `sm_nadepractice_enabled 0`) возвращаются прежние значения:

| Квар | Значение | Зачем |
|---|---|---|
| `mp_freezetime` | 0 | без заморозки в начале раунда |
| `mp_roundtime` | 9 | максимальное время раунда |
| `mp_ignore_round_win_conditions` | 1 | раунд не заканчивается |
| `mp_timelimit`, `mp_maxrounds`, `mp_winlimit`, `mp_fraglimit` | 0 | карта не меняется сама |
| `mp_buytime` | 9999 | закупка без ограничения по времени |
| `mp_startmoney` | 16000 | деньги |
| `mp_limitteams`, `mp_autoteambalance` | 0 | любая команда |
| `bot_quota` | 0 | без ботов |

`sv_cheats` не трогается.

## Команды игрока

| Команда | Что делает |
|---|---|
| `!practice`, `!nadepractice` | главное меню |
| `!noclip` | полёт сквозь стены (вкл/выкл) |
| `!back` | вернуться в позицию и углы последнего броска |
| `!last` | повторить последний бросок |
| `!clear` | стереть свои траектории |
| `!tracer` | показывать траектории бросков (вкл/выкл) |
| `!preview` | предпросмотр траектории, пока граната в руках (вкл/выкл) |
| `!preverror` | точность предпросмотра за сессию: число бросков, средняя и максимальная ошибка |
| `!noflash` | не слепнуть от флешек (вкл/выкл) |
| `!hints` | подсказки по выбранному лайнапу (вкл/выкл) |
| `!save <имя>` | сохранить последний бросок как лайнап (после детонации) |
| `!lineups` | меню лайнапов: по типу гранаты, ближайшие первыми |
| `!goto <имя>` | телепорт в точку лайнапа, граната в руки, подсказки |
| `!show <имя>` | повторить бросок лайнапа |
| `!delete [имя]` | удалить лайнап (без имени — выбранный) |
| `!rename <новое имя>` | переименовать выбранный лайнап |
| `!desc <текст>` | описание выбранного лайнапа |

Имя в `!goto`, `!show`, `!delete` можно писать не целиком, если совпадение одно. Без имени `!goto` и `!show` работают с выбранным лайнапом.

Админ-команды: `sm_nadepractice_start`, `sm_nadepractice_stop` (флаг changemap).

## Квары

| Квар | По умолчанию | Описание |
|---|---|---|
| `sm_nadepractice_version` | 0.1.0 | Версия плагина |
| `sm_nadepractice_enabled` | 1 | Разрешён ли режим (0 — режим нельзя запустить, запущенный останавливается) |
| `sm_nadepractice_debug` | 0 | Подробный лог в logs/nadepractice_debug.log |
| `sm_nadepractice_autostart` | 0 | Запускать режим автоматически на каждой карте |
| `sm_nadepractice_restart_on_start` | 1 | При запуске режима перезапускать раунд (mp_restartgame 1), чтобы квары раунда применились сразу |
| `sm_nadepractice_te_per_frame` | 24 | Сколько временных сущностей (лучи, кольца, спрайты) можно отправить одному игроку за кадр |
| `sm_nadepractice_infinite` | 1 | Бесконечные гранаты: после броска выдаётся такая же |
| `sm_nadepractice_give_on_spawn` | 1 | Выдавать HE, флешку и дым при появлении |
| `sm_nadepractice_block_damage` | 1 | Блокировать любой урон игрокам |
| `sm_nadepractice_block_self_nade_damage` | 1 | Блокировать урон от своих гранат (имеет смысл при block_damage 0) |
| `sm_nadepractice_replay_mode` | 1 | Повтор броска: 0 — только отрисовка сохранённой траектории, 1 — настоящий снаряд |
| `sm_nadepractice_replay_engine_fuse` | 0 | Детонация HE/флешки повтора: 0 — плагином (эффект без урона и ослепления), 1 — попытаться запустить таймер движка (экспериментально) |
| `sm_nadepractice_replay_visible_all` | 0 | Показывать снаряды повтора всем игрокам, а не только владельцу |
| `sm_nadepractice_replay_cooldown` | 0.5 | Минимальный интервал между повторами одного игрока, с |
| `sm_nadepractice_replay_smoke_time` | 18.0 | Сколько секунд живёт дым повтора |
| `sm_nadepractice_sim_gravity` | 0.4 | Множитель sv_gravity для гранаты |
| `sm_nadepractice_sim_elasticity` | 0.45 | Упругость гранаты (доля скорости после отскока) |
| `sm_nadepractice_sim_friction` | 0.2 | Трение гранаты (выставляется снаряду повтора; в модели полёта не участвует) |
| `sm_nadepractice_sim_fuse` | 1.5 | Время до детонации HE и флешки, с |
| `sm_nadepractice_sim_smoke_fuse` | 1.5 | Минимальное время до срабатывания дыма, с (дальше — когда граната остановится) |
| `sm_nadepractice_sim_think` | 0.2 | Шаг проверки таймера детонации в движке, с (0 — детонация ровно по таймеру) |
| `sm_nadepractice_trace_count` | 5 | Сколько последних траекторий хранить и показывать на игрока |
| `sm_nadepractice_trace_sample` | 0.05 | Шаг записи точек траектории, с (отскоки записываются всегда) |
| `sm_nadepractice_trace_redraw` | 2.0 | Период перерисовки сохранённых траекторий, с |
| `sm_nadepractice_trace_max_segments` | 24 | Максимум отрезков на одну траекторию при отрисовке (отскоки не пропускаются) |
| `sm_nadepractice_trace_width` | 1.5 | Толщина линии траектории |
| `sm_nadepractice_trace_max_time` | 12.0 | Сколько секунд максимум записывается один снаряд |
| `sm_nadepractice_trace_bounce_dv` | 25.0 | Отскок: изменение скорости за тик сверх гравитации, юнитов/с |
| `sm_nadepractice_edit_access` | 0 | Кто меняет базу лайнапов: 0 — все игроки, 1 — только админы (доступ sm_nadepractice_edit, по умолчанию флаг generic) |
| `sm_nadepractice_hint_interval` | 0.25 | Период обновления подсказки, с |
| `sm_nadepractice_hint_pos_radius` | 6.0 | Допуск позиции, юнитов по горизонтали |
| `sm_nadepractice_hint_angle_tolerance` | 0.5 | Допуск прицела, градусов |
| `sm_nadepractice_hint_mode` | 0 | Куда выводить подсказку: 0 — KeyHintText (панель справа), 1 — HintText, 2 — HUD-текст (цветной) |
| `sm_nadepractice_hint_unicode` | 1 | Стрелки в подсказке: 1 — юникод, 0 — ASCII |
| `sm_nadepractice_hint_look_distance` | 300.0 | На каком расстоянии от глаз ставить метку «куда смотреть» (ближе, если мешает стена) |
| `sm_nadepractice_preview_default` | 1 | Предпросмотр траектории включён у игрока по умолчанию |
| `sm_nadepractice_preview_interval` | 0.1 | Период обновления предпросмотра, с |
| `sm_nadepractice_preview_max_segments` | 14 | Максимум отрезков линии предпросмотра |
| `sm_nadepractice_sim_max_steps` | 400 | Максимум шагов модели на один расчёт |
| `sm_nadepractice_sim_max_bounces` | 20 | Максимум отскоков в модели |
| `sm_nadepractice_sim_tick_mult` | 1 | Шаг модели в тиках сервера (1 — точнее, больше — дешевле) |
| `sm_nadepractice_sim_stop_speed` | 30.0 | Скорость после отскока, ниже которой граната останавливается |
| `sm_nadepractice_sim_throw_speed_max` | 750.0 | Максимальная начальная скорость броска |
| `sm_nadepractice_sim_throw_speed_factor` | 6.0 | Скорость броска = (90 - угол) * множитель |
| `sm_nadepractice_sim_throw_pitch_offset` | -10.0 | Подъём броска относительно взгляда в горизонт, градусов (отрицательное — вверх) |
| `sm_nadepractice_sim_throw_forward` | 16.0 | На сколько юнитов впереди глаз появляется снаряд |
| `sm_nadepractice_sim_hull` | 2.0 | Половина размера снаряда для проверки столкновений |
| `sm_nadepractice_sim_player_velocity` | 1.0 | Какая доля скорости игрока добавляется к броску |

Квары `sm_nadepractice_sim_*` — физические константы модели полёта. Их нужно подстроить на сервере по `!preverror` и debug-логу (порядок — в TEST_CHECKLIST, этап 5).

## Файл лайнапов

`addons/sourcemod/configs/nadepractice/lineups/<карта>.cfg`, формат KeyValues. Файл переписывается целиком при каждом изменении базы; номера секций значения не имеют.

```
"Lineups"
{
    "1"
    {
        "name"                 "xbox smoke"
        "type"                 "smoke"            // he | flash | smoke
        "throw"                "jump"             // stand | crouch | jump | run | runjump
        "origin"               "-300.0 1200.5 64.03"   // player position (feet) at the throw
        "angles"               "-12.4 87.3 0.0"        // view angles: pitch yaw roll
        "eye"                  "-300.0 1200.5 128.03"  // eye position at the throw
        "has_projectile"       "1"
        "projectile_origin"    "..."              // initial projectile position
        "projectile_velocity"  "..."              // initial projectile velocity
        "has_detonation"       "1"
        "detonation"           "..."              // detonation point
        "author"               "player name"
        "description"          "free text"
        "path"                                    // simplified trajectory, up to 32 points
        {
            "0"    "x y z"
            "1"    "x y z"
        }
    }
}
```

Тип броска определяется автоматически в момент появления снаряда: в воздухе — прыжок, на земле в приседе — присед, горизонтальная скорость больше 60 — «с бега».

## API

`scripting/include/nadepractice.inc`, библиотека `nadepractice`, версия API 1:

- `native bool Nadepractice_IsActive()` — запущен ли режим;
- `native int Nadepractice_GetApiVersion()`.

## Известные ограничения

- **Повтор броска без gamedata.** Плагин не может вызвать штатную детонацию у созданного им снаряда. HE и флешка повтора «взрываются» эффектом и звуком без урона и ослепления; дым повтора плагин ставит сам. Полёт и отскоки считает движок.
- **Дым повтора виден всем** игрокам; сам снаряд повтора — только владельцу.
- **Настоящие броски влияют на всех**: флешка слепит соседей (каждый может включить `!noflash`), дым закрывает обзор.
- **Модель предпросмотра приближённая.** Исходников гранат CS:S в открытом SDK нет; модель не учитывает игроков, движущиеся объекты и разбиваемые стёкла.
- **Лайнапы «с бега».** Сохраняется позиция в момент вылета гранаты, а не начала разбега; подсказка ведёт к ней.
- **Стёртые траектории** исчезают не мгновенно: отправленные лучи доживают до конца цикла перерисовки (около 2 с).
- **`!noclip` и funcommands.** В активном режиме `!noclip` перехватывается плагином раньше админской команды `sm_noclip`.
- Команды `!save`, `!goto`, `!show`, `!delete`, `!back`, `!last`, `!clear` могут совпасть с командами сторонних плагинов.
- Цвет «готово» в текстовой подсказке есть только в `hint_mode 2`; в остальных режимах зелёным становится кольцо на земле и появляется строка «ГОТОВО».

## Сборка

`./build.sh` — компилирует `scripting/*.sp` в `build/`. Предупреждение считается ошибкой.

---

<a name="english"></a>

# nadepractice — grenade practice mode for CS:S

A SourceMod 1.12 plugin for Counter-Strike: Source: infinite grenades with no damage, a tracer for real throws, a per-map lineup database, "where to stand / where to aim" hints, throw replay and a trajectory preview before the throw. Everything drawn is visible to its owner only, so several players can practise at once.

> **Status.** The first version has been tested on a server (results in [TEST_CHECKLIST.md](TEST_CHECKLIST.md)); rework based on the feedback is in progress (`tasks/PRACTICE_TASK.md`, stages 7–15). Everything that depends on engine behaviour and is not verified yet is marked `CSS-VERIFY` in the code and listed in the checklist.

- Layer (per `ARCHITECTURE.md`): **mode**. No dependencies, no gamedata/DHooks, no third-party libraries.
- Owns (while active): players' money, grenades and damage, the bot count (`bot_quota 0`), its temporary cvars, the lineup database.

## Installation

1. `build/nadepractice.smx` → `addons/sourcemod/plugins/`
2. `translations/nadepractice.phrases.txt` → `addons/sourcemod/translations/`, `translations/ru/nadepractice.phrases.txt` → `addons/sourcemod/translations/ru/`
3. Reload the map. `cfg/sourcemod/nadepractice.cfg` is generated.
4. Start the mode with `sm_nadepractice_start` (admin, changemap flag) or set `sm_nadepractice_autostart 1`.

The plugin creates `addons/sourcemod/configs/nadepractice/lineups/` on the first `!save`.

## What the mode changes

Temporary cvars are set on start and restored on stop (command, map change, plugin unload, `sm_nadepractice_enabled 0`): `mp_freezetime 0`, `mp_roundtime 9`, `mp_ignore_round_win_conditions 1`, `mp_timelimit 0`, `mp_maxrounds 0`, `mp_winlimit 0`, `mp_fraglimit 0`, `mp_buytime 9999`, `mp_startmoney 16000`, `mp_limitteams 0`, `mp_autoteambalance 0`, `bot_quota 0`. `sv_cheats` is not touched.

## Player commands

| Command | Action |
|---|---|
| `!practice`, `!nadepractice` | main menu |
| `!noclip` | toggle noclip |
| `!back` | return to the position and angles of the last throw |
| `!last` | replay the last throw |
| `!clear` | clear your trajectories |
| `!tracer` | toggle the throw tracer |
| `!preview` | toggle the trajectory preview while holding a grenade |
| `!preverror` | preview accuracy for the session |
| `!noflash` | toggle flash immunity |
| `!hints` | toggle hints for the selected lineup |
| `!save <name>` | save the last throw as a lineup (after it detonates) |
| `!lineups` | lineup menu: by grenade type, nearest first |
| `!goto <name>` | teleport to the lineup, equip the grenade, show hints |
| `!show <name>` | replay the lineup throw |
| `!delete [name]` | delete a lineup (no name: the selected one) |
| `!rename <new name>` | rename the selected lineup |
| `!desc <text>` | set the description of the selected lineup |

A partial name works in `!goto`, `!show`, `!delete` when it matches exactly one lineup.

Admin commands: `sm_nadepractice_start`, `sm_nadepractice_stop` (changemap flag).

## Cvars

| Cvar | Default | Description |
|---|---|---|
| `sm_nadepractice_version` | 0.1.0 | Plugin version |
| `sm_nadepractice_enabled` | 1 | Mode allowed (0: cannot be started, a running mode stops) |
| `sm_nadepractice_debug` | 0 | Verbose log to logs/nadepractice_debug.log |
| `sm_nadepractice_autostart` | 0 | Start the mode automatically on every map |
| `sm_nadepractice_restart_on_start` | 1 | Restart the round (mp_restartgame 1) when the mode starts |
| `sm_nadepractice_te_per_frame` | 24 | Temp entities (beams, rings, sprites) sent to one player per frame |
| `sm_nadepractice_infinite` | 1 | Infinite grenades: the same grenade is given back after a throw |
| `sm_nadepractice_give_on_spawn` | 1 | Give HE, flash and smoke on spawn |
| `sm_nadepractice_block_damage` | 1 | Block all damage to players |
| `sm_nadepractice_block_self_nade_damage` | 1 | Block damage from own grenades (matters when block_damage is 0) |
| `sm_nadepractice_replay_mode` | 1 | Throw replay: 0 = draw the saved trajectory only, 1 = real projectile |
| `sm_nadepractice_replay_engine_fuse` | 0 | HE/flash replay detonation: 0 = by the plugin (effect only), 1 = try the engine think (experimental) |
| `sm_nadepractice_replay_visible_all` | 0 | Show replay projectiles to everyone instead of the owner only |
| `sm_nadepractice_replay_cooldown` | 0.5 | Minimum interval between replays per player, s |
| `sm_nadepractice_replay_smoke_time` | 18.0 | Lifetime of a replay smoke cloud, s |
| `sm_nadepractice_sim_gravity` | 0.4 | sv_gravity multiplier for a grenade |
| `sm_nadepractice_sim_elasticity` | 0.45 | Grenade elasticity (speed kept after a bounce) |
| `sm_nadepractice_sim_friction` | 0.2 | Grenade friction (set on replay projectiles; unused by the flight model) |
| `sm_nadepractice_sim_fuse` | 1.5 | HE and flash fuse time, s |
| `sm_nadepractice_sim_smoke_fuse` | 1.5 | Minimum time before a smoke pops, s (then: when it stops) |
| `sm_nadepractice_sim_think` | 0.2 | Engine fuse check step, s (0 = detonate exactly on the fuse) |
| `sm_nadepractice_trace_count` | 5 | How many last trajectories are kept and shown per player |
| `sm_nadepractice_trace_sample` | 0.05 | Trajectory sampling step, s (bounces are always recorded) |
| `sm_nadepractice_trace_redraw` | 2.0 | Redraw period of stored trajectories, s |
| `sm_nadepractice_trace_max_segments` | 24 | Max beam segments per trajectory (bounces are never skipped) |
| `sm_nadepractice_trace_width` | 1.5 | Trajectory line width |
| `sm_nadepractice_trace_max_time` | 12.0 | Max seconds one projectile is recorded |
| `sm_nadepractice_trace_bounce_dv` | 25.0 | Bounce = per-tick velocity change beyond gravity, units/s |
| `sm_nadepractice_edit_access` | 0 | Who may change the lineup database: 0 = everyone, 1 = admins (access sm_nadepractice_edit, generic flag by default) |
| `sm_nadepractice_hint_interval` | 0.25 | Hint refresh period, s |
| `sm_nadepractice_hint_pos_radius` | 6.0 | Position tolerance, horizontal units |
| `sm_nadepractice_hint_angle_tolerance` | 0.5 | Aim tolerance, degrees |
| `sm_nadepractice_hint_mode` | 0 | Hint output: 0 = KeyHintText (right panel), 1 = HintText, 2 = HUD text (coloured) |
| `sm_nadepractice_hint_unicode` | 1 | Arrows: 1 = Unicode, 0 = ASCII |
| `sm_nadepractice_hint_look_distance` | 300.0 | Distance from the eyes to the "look here" marker (closer if a wall is in the way) |
| `sm_nadepractice_preview_default` | 1 | Trajectory preview is on by default |
| `sm_nadepractice_preview_interval` | 0.1 | Preview refresh period, s |
| `sm_nadepractice_preview_max_segments` | 14 | Max segments of the preview line |
| `sm_nadepractice_sim_max_steps` | 400 | Max model steps per run |
| `sm_nadepractice_sim_max_bounces` | 20 | Max bounces in the model |
| `sm_nadepractice_sim_tick_mult` | 1 | Model step in server ticks (1 = most accurate) |
| `sm_nadepractice_sim_stop_speed` | 30.0 | Speed after a bounce below which the grenade stops |
| `sm_nadepractice_sim_throw_speed_max` | 750.0 | Max initial throw speed |
| `sm_nadepractice_sim_throw_speed_factor` | 6.0 | Throw speed = (90 - pitch) * factor |
| `sm_nadepractice_sim_throw_pitch_offset` | -10.0 | Throw pitch lift relative to a level view, degrees (negative = up) |
| `sm_nadepractice_sim_throw_forward` | 16.0 | How far in front of the eyes the projectile spawns |
| `sm_nadepractice_sim_hull` | 2.0 | Half-size of the projectile hull for collision traces |
| `sm_nadepractice_sim_player_velocity` | 1.0 | Fraction of the player velocity added to the throw |

The `sm_nadepractice_sim_*` cvars are the physical constants of the flight model; tune them on the server using `!preverror` and the debug log.

## Lineup file

`addons/sourcemod/configs/nadepractice/lineups/<map>.cfg`, KeyValues. The file is rewritten on every change; section numbers carry no meaning.

```
"Lineups"
{
    "1"
    {
        "name"                 "xbox smoke"
        "type"                 "smoke"            // he | flash | smoke
        "throw"                "jump"             // stand | crouch | jump | run | runjump
        "origin"               "-300.0 1200.5 64.03"   // player position (feet) at the throw
        "angles"               "-12.4 87.3 0.0"        // view angles: pitch yaw roll
        "eye"                  "-300.0 1200.5 128.03"  // eye position at the throw
        "has_projectile"       "1"
        "projectile_origin"    "..."              // initial projectile position
        "projectile_velocity"  "..."              // initial projectile velocity
        "has_detonation"       "1"
        "detonation"           "..."              // detonation point
        "author"               "player name"
        "description"          "free text"
        "path"                                    // simplified trajectory, up to 32 points
        {
            "0"    "x y z"
            "1"    "x y z"
        }
    }
}
```

The throw type is detected when the projectile spawns: airborne = jump, on the ground and ducked = crouch, horizontal speed above 60 = running.

## API

`scripting/include/nadepractice.inc`, library `nadepractice`, API version 1: `Nadepractice_IsActive()`, `Nadepractice_GetApiVersion()`.

## Known limitations

- **Replay without gamedata.** The plugin cannot trigger the stock detonation of a projectile it created. Replayed HE and flash grenades "detonate" as an effect and a sound with no damage or blindness; the replay smoke cloud is spawned by the plugin. Flight and bounces are computed by the engine.
- The replay smoke cloud is visible to everyone; the replay projectile only to its owner.
- Real throws affect everyone: flashes blind nearby players (each can enable `!noflash`), smoke blocks vision.
- The preview model is approximate: the CS:S grenade source is not in the public SDK; players, moving objects and breakable glass are ignored.
- Running lineups store the position where the grenade left the hand, not where the run started.
- Cleared trajectories fade within about 2 s, not instantly.
- While the mode is active `!noclip` is intercepted before the funcommands admin command.
- `!save`, `!goto`, `!show`, `!delete`, `!back`, `!last`, `!clear` may clash with third-party plugins.
- A green "ready" text exists only in `hint_mode 2`; otherwise the ground ring turns green and a READY line appears.

## Build

`./build.sh` compiles `scripting/*.sp` into `build/`. A warning fails the build.
