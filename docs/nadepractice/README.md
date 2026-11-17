# nadepractice — режим тренировки гранат для CS:S

[English version below](#english)

Плагин SourceMod 1.12 для Counter-Strike: Source: бесконечные гранаты без урона, трассер настоящих бросков, база лайнапов по картам, подсказки «где встать и куда навестись» (старт разбега и точка броска, рамка прицела), повтор броска, предпросмотр траектории до броска, проверка ослепления, урон HE, время полёта, спавны и таймеры. Всё, что рисуется, видит только сам игрок, поэтому несколько человек тренируются одновременно.

> **Статус.** Версия 0.2.0. Первая версия (0.1.0) проверена на сервере, доработка по замечаниям (`tasks/PRACTICE_TASK.md`, этапы 7–15) написана, но на сервере ещё не проверялась. Всё, что зависит от движка и не проверено, помечено в коде `CSS-VERIFY` и собрано в [TEST_CHECKLIST.md](TEST_CHECKLIST.md).

- Слой по `ARCHITECTURE.md`: **режим**. Необязательно использует `nadethrow` (сила броска). Сторонних библиотек и DHooks нет.
- **Gamedata — по решению владельца** (отступление от правила 5 раздела 2 `ARCHITECTURE.md`): только для настоящей детонации снарядов повтора. Если gamedata устарела, эта функция выключается, остальное работает (см. «Gamedata»).
- Владеет (пока режим активен): деньгами, гранатами и уроном игроков, возрождением, числом ботов (`bot_quota 0`), своими временными кварами, флагами консольной команды `noclip`, длительностью дыма игроков; всегда — базой лайнапов.

## Установка

Копировать вместе, при каждом обновлении:

1. `build/nadepractice.smx` → `addons/sourcemod/plugins/`
2. `translations/nadepractice.phrases.txt` → `addons/sourcemod/translations/`, `translations/ru/nadepractice.phrases.txt` → `addons/sourcemod/translations/ru/`
3. `gamedata/nadepractice.games.txt` → `addons/sourcemod/gamedata/` (для настоящей детонации повтора; без него плагин работает)
4. Перезапустить карту (или `sm plugins reload nadepractice` и `sm_reload_translations`). Появится `cfg/sourcemod/nadepractice.cfg` с кварами.
5. Запуск режима: `sm_nadepractice_start` (админ, флаг changemap) или `sm_nadepractice_autostart 1`.

Если переводы не обновлены, меню всё равно открывается (вместо текстов — имена фраз), а в логе ошибок — строка `translations/nadepractice.phrases.txt is outdated`.

Папку `addons/sourcemod/configs/nadepractice/lineups/` плагин создаёт сам при первом `!save`.

Режим рассчитан на отдельную конфигурацию сервера: не загружайте его вместе с Retakes и другими режимами (`ARCHITECTURE.md`, раздел 13).

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

`sv_cheats` не трогается. На время режима у консольной команды `noclip` снимается флаг cheat (её обрабатывает плагин), при остановке флаг возвращается.

Умерший игрок возрождается через `sm_nadepractice_respawn_delay` секунд (раунд в режиме не заканчивается); вошедший в T/CT посреди раунда — сразу.

## Команды игрока

| Команда | Что делает |
|---|---|
| `!practice`, `!nadepractice` | главное меню |
| `!noclip` | полёт сквозь стены (вкл/выкл); консольная `noclip` в режиме работает так же |
| `!back` | на старт (или точку броска) последнего броска с углами броска |
| `!last` | повторить последний бросок |
| `!clear` | стереть свои траектории |
| `!tracer` | показывать траектории бросков (вкл/выкл) |
| `!preview` | предпросмотр траектории, пока граната в руках (вкл/выкл) |
| `!preverror [reset]` | точность предпросмотра за сессию (по кнопкам, если есть броски `nadethrow`); `reset` — сброс |
| `!noflash` | не слепнуть от флешек (вкл/выкл) |
| `!hands` | вернуть пропавшую модель рук и оружия |
| `!hints` | подсказки по выбранному лайнапу (вкл/выкл) |
| `!save <имя>` | сохранить последний бросок как лайнап (после детонации) |
| `!lineups` | меню лайнапов: показать или скрыть лайнап на карте (по типу гранаты, ближайшие первыми), «показывать все», карточки лайнапов |
| `!all` | показывать все лайнапы карты сразу (вкл/выкл) |
| `!goto <имя>` | телепорт на старт лайнапа, граната в руки, подсказки |
| `!show <имя>` | повторить бросок лайнапа |
| `!delete [имя]` | удалить лайнап (без имени — выбранный) |
| `!rename <новое имя>` | переименовать выбранный лайнап |
| `!desc <текст>` | описание выбранного лайнапа |
| `!setstart` | старт выбранного лайнапа (или последнего броска) — где стоишь (на земле) |
| `!setrelease` | точка броска — где стоишь |
| `!setaim` | прицел — куда смотришь |
| `!nostart` | убрать старт: подсказка ведёт к точке броска |
| `!flash [off]` | точка проверки ослепления — где стоишь; `off` — выключить |
| `!spawn [t\|ct] [N]` | на ближайший спавн своей (или указанной) стороны; `N` — спавн номер N |
| `!bestspawn [t\|ct]`, `!worstspawn [t\|ct]` | на ближайший / самый дальний спавн от текущей позиции |
| `!timer` | таймер от первого шага до остановки (повторно — отмена) |
| `!timer2` | ручной таймер: запуск, повторно — стоп |

Имя в `!goto`, `!show`, `!delete` можно писать не целиком, если совпадение одно. Без имени `!goto` и `!show` работают с выбранным лайнапом. `!setstart`, `!setrelease`, `!setaim`, `!nostart` меняют выбранный лайнап (сразу пишется в файл, нужны права `edit_access`), а если лайнап не выбран — последний бросок до `!save`.

`sm_noclip` / `!noclip` без аргумента в активном режиме обрабатывает `nadepractice` (поэтому в чате префикс `NadePractice`); вне режима и `sm_noclip <ник>` у админа — `funcommands`.

Пока режим запущен, команды плагина работают и с точкой: `.spawn`, `.noclip`, `.save имя` и т. д. (`sm_nadepractice_dot_commands`).

Админ-команды: `sm_nadepractice_start`, `sm_nadepractice_stop` (флаг changemap), `sm_nadepractice_gamedata` (флаг generic) — состояние функций gamedata.

## Меню `!practice`

Лайнапы (с кнопкой «Назад»), повтор, назад, noclip, очистка, переключатели трассера, предпросмотра и подсказок; **текст подсказки** (панель справа / по центру экрана / цветной под прицелом); **метка прицела** (рамка допуска / крестик / спрайт); **проверка позиции** (авто / старт / точка броска); **правка** старта, точки броска и прицела; **замеры** (точка проверки ослепления, для флешек или флешек и HE, возврат после проверки, отчёт урона HE, отчёт времени полёта, `!noflash`); **спавны**; **длительность дыма** (по умолчанию игры / 5 / 10 / 30 / 60 с); `!noflash`; «вернуть руки»; точность предпросмотра; список команд.

## Как пользоваться

**Лайнап.** Бросить гранату → `!save имя`. Плагин запоминает старт и точку броска, углы, тип броска, силу (`nadethrow`), траекторию, точку и время детонации.

**Несколько лайнапов сразу.** В `!lineups` каждый лайнап — переключатель: нажал — он показан на карте, нажал ещё раз — скрыт; «Показывать все» (или `!all`) показывает все лайнапы карты. У каждого показанного лайнапа поблизости (`sm_nadepractice_show_radius`, не больше `sm_nadepractice_show_max` ближайших) — кольцо и столбик цветом гранаты там, где встать. Зашёл в кольцо (`sm_nadepractice_show_select_radius`) — этот лайнап выбирается сам и получает полную подсказку: рамку прицела, текст, точку приземления. Подсказка остаётся, пока не зайдёшь в кольцо другого лайнапа. Телепорт, повтор, правка и удаление — в «Карточках лайнапов».

**Два места: старт и точка броска.** Старт — где встать перед разбегом или прыжком, точка броска — где граната вылетела из рук. Определяются автоматически: стоя и в приседе — одно место; прыжок и jumpthrow — точка отрыва; бег — последняя точка на земле со скоростью ниже `sm_nadepractice_start_speed`, не дальше `sm_nadepractice_start_lookback` секунд. Подсказка рисует жёлтое кольцо (цель проверки позиции, зеленеет в допуске), голубое кольцо поменьше (второе место) и линию разбега между ними. Прицел — тот, что был в момент броска: при броске с бега наводишься на старте и бежишь, не двигая мышь.

**Рамка прицела.** Квадрат, угловой размер которого равен допуску (`2 × sm_nadepractice_hint_angle_tolerance`): прицел внутри рамки — прицел в допуске, рамка зеленеет. «ГОТОВО» в тексте — когда позиция, прицел и кнопки совпадают.

**Jumpthrow.** Отдельный тип: атака отпущена в том же тике, что нажат прыжок (или в пределах `sm_nadepractice_jumpthrow_ticks`), — так работает бинд `alias +jt "+jump;-attack"; alias -jt -jump`. С `nadethrow` бинд должен отпускать и ПКМ: `"+jump;-attack;-attack2"` (см. `docs/nadethrow/README.md`). Готовый бинд плагин пишет в чат один раз за подключение, при первом появлении в режиме. В первой версии jumpthrow считался обычным «прыжком».

**`nadethrow`.** Если загружен, у лайнапа хранится сила броска (ЛКМ / ЛКМ+ПКМ / ПКМ), в подсказке — строка «Кнопки» и текущая сила, пока чека выдернута; «готово» только при совпадении. Предпросмотр учитывает текущую силу. Без `nadethrow` всё работает как при ЛКМ; у лайнапа с ПКМ — предупреждение.

**Проверка ослепления.** `!flash` на месте, где хочешь проверить, отойти, бросить флешку: плагин переносит обратно в точку, ты видишь прилёт и слепнешь; в чате — длительность, сила и расстояние до взрыва, а также кого ещё ослепила флешка. После ослепления — возврат на место броска. С `!noflash` замер всё равно пишется («ослепило бы на N с»).

**Урон HE** — сколько нанесла бы граната (урон блокируется, но плагин видит его до блокировки), с оценкой «в броне». **Время полёта** — после каждой детонации: срабатывание, первое касание, отскоки, в воздухе или нет (у дыма главное — время раскрытия).

**Спавны и таймер.** `!timer`, затем `!bestspawn` — таймер ждёт первого шага; так сравниваются тайминги сторон.

**Повтор (`!last`, `!show`).** Снаряд создаётся с сохранёнными начальными позицией и скоростью, полёт считает движок. С gamedata снаряд создаёт сама игра, и он взрывается по-настоящему: флешка слепит, HE взрывается, дым настоящий. Без gamedata HE и флешку «взрывает» плагин (эффект без урона и ослепления), дым ставит плагин.

## Квары

| Квар | По умолчанию | Описание |
|---|---|---|
| `sm_nadepractice_version` | 0.2.0 | версия плагина |
| `sm_nadepractice_enabled` | 1 | разрешён ли режим (0 — нельзя запустить, запущенный останавливается) |
| `sm_nadepractice_debug` | 0 | подробный лог в `logs/nadepractice_debug.log` |
| `sm_nadepractice_autostart` | 0 | запускать режим на каждой карте |
| `sm_nadepractice_restart_on_start` | 1 | при запуске перезапускать раунд (`mp_restartgame 1`) |
| `sm_nadepractice_te_per_frame` | 24 | временных сущностей (лучи, кольца) одному игроку на сетевое обновление (предел движка — 32) |
| `sm_nadepractice_infinite` | 1 | бесконечные гранаты |
| `sm_nadepractice_give_on_spawn` | 1 | выдавать HE, флешку и дым при появлении |
| `sm_nadepractice_block_damage` | 1 | блокировать любой урон |
| `sm_nadepractice_block_self_nade_damage` | 1 | блокировать урон от своих гранат (при `block_damage 0`) |
| `sm_nadepractice_respawn_delay` | 1.0 | возрождение через столько секунд (0 — выключено) |
| `sm_nadepractice_respawn_at_death` | 0 | возрождать в точке смерти с теми же углами |
| `sm_nadepractice_replay_mode` | 1 | повтор: 0 — только отрисовка траектории, 1 — снаряд |
| `sm_nadepractice_replay_real` | 1 | настоящая детонация повтора через `Create()` игры (gamedata); 0 — детонация плагином |
| `sm_nadepractice_replay_engine_fuse` | 0 | старый опыт: запуск таймера движка у снаряда без gamedata (на сервере не сработал) |
| `sm_nadepractice_replay_visible_all` | 0 | показывать снаряды повтора всем |
| `sm_nadepractice_replay_cooldown` | 0.5 | минимальный интервал между повторами, с |
| `sm_nadepractice_replay_smoke_time` | 18.0 | сколько живёт дым повтора плагином при «длительности по умолчанию», с |
| `sm_nadepractice_smoke_time_min` | 5 | наименьшая длительность дыма в меню, с |
| `sm_nadepractice_smoke_time_max` | 60 | наибольшая длительность дыма в меню, с |
| `sm_nadepractice_flash_return` | 1 | возврат на место броска после проверки ослепления (у игрока — в меню) |
| `sm_nadepractice_he_damage_report` | 1 | сообщать урон HE (по умолчанию у игрока) |
| `sm_nadepractice_he_armor_ratio` | 0.5 | оценка урона HE в броне: доля урона, уходящая в здоровье |
| `sm_nadepractice_airtime_report` | 1 | сообщать время полёта (по умолчанию у игрока) |
| `sm_nadepractice_timer_speed` | 10.0 | `!timer`: скорость, выше которой игрок движется |
| `sm_nadepractice_timer_stop_ticks` | 8 | `!timer`: тиков подряд ниже порога = остановка |
| `sm_nadepractice_trace_count` | 5 | сколько траекторий хранить и показывать (до 10) |
| `sm_nadepractice_trace_sample` | 0.05 | шаг записи точек траектории, с |
| `sm_nadepractice_trace_redraw` | 2.0 | период перерисовки траекторий, с |
| `sm_nadepractice_trace_max_segments` | 24 | отрезков на траекторию при отрисовке |
| `sm_nadepractice_trace_width` | 1.5 | толщина линии траектории |
| `sm_nadepractice_trace_max_time` | 12.0 | сколько секунд максимум записывается снаряд |
| `sm_nadepractice_trace_bounce_dv` | 25.0 | порог определения отскока, юнитов/с за тик |
| `sm_nadepractice_edit_access` | 0 | кто меняет базу: 0 — все, 1 — админы (доступ `sm_nadepractice_edit`, флаг generic) |
| `sm_nadepractice_start_speed` | 10.0 | старт разбега: последняя точка на земле со скоростью ниже этой |
| `sm_nadepractice_start_lookback` | 3.0 | на сколько секунд назад искать старт разбега |
| `sm_nadepractice_jumpthrow_ticks` | 2 | jumpthrow: атака отпущена не дальше стольких тиков от нажатия прыжка |
| `sm_nadepractice_hint_interval` | 0.25 | период обновления подсказки, с |
| `sm_nadepractice_hint_pos_radius` | 6.0 | допуск позиции, юнитов |
| `sm_nadepractice_hint_angle_tolerance` | 0.5 | допуск прицела, градусов |
| `sm_nadepractice_hint_mode` | 0 | вывод подсказки по умолчанию: 0 — KeyHintText (панель справа), 1 — HintText (по центру), 2 — HUD-текст (цветной); у игрока — в меню |
| `sm_nadepractice_hint_unicode` | 1 | стрелки: 1 — юникод, 0 — ASCII |
| `sm_nadepractice_hint_look_distance` | 300.0 | расстояние от глаз до метки прицела |
| `sm_nadepractice_hint_target` | 0 | цель проверки позиции по умолчанию: 0 — авто, 1 — старт, 2 — точка броска |
| `sm_nadepractice_show_radius` | 1500.0 | показанные лайнапы: кольца у тех, что ближе этого, юнитов |
| `sm_nadepractice_show_max` | 8 | показанные лайнапы: колец не больше, чем у стольких ближайших |
| `sm_nadepractice_show_select_radius` | 48.0 | показанные лайнапы: так близко к месту лайнапа — он выбирается для полной подсказки, юнитов |
| `sm_nadepractice_dot_commands` | 1 | команды с точкой (`.spawn`, `.noclip`…) в режиме работают как `!`-команды |
| `sm_nadepractice_hint_marker` | 0 | метка прицела по умолчанию: 0 — рамка, 1 — крестик, 2 — спрайт |
| `sm_nadepractice_hint_marker_width` | 0.6 | толщина линий рамки и крестика |
| `sm_nadepractice_preview_default` | 1 | предпросмотр включён у игрока по умолчанию |
| `sm_nadepractice_preview_interval` | 0.1 | период обновления предпросмотра, с |
| `sm_nadepractice_preview_max_segments` | 14 | отрезков линии предпросмотра |
| `sm_nadepractice_sim_gravity` | 0.4 | множитель `sv_gravity` для гранаты |
| `sm_nadepractice_sim_elasticity` | 0.45 | упругость гранаты |
| `sm_nadepractice_sim_friction` | 0.2 | трение (только снаряду повтора без gamedata) |
| `sm_nadepractice_sim_fuse` | 1.5 | таймер HE и флешки, с |
| `sm_nadepractice_sim_smoke_fuse` | 1.5 | минимальное время до срабатывания дыма, с |
| `sm_nadepractice_sim_think` | 0.2 | шаг проверки таймера детонации, с |
| `sm_nadepractice_sim_max_steps` | 400 | шагов модели на расчёт |
| `sm_nadepractice_sim_max_bounces` | 20 | отскоков в модели |
| `sm_nadepractice_sim_tick_mult` | 1 | шаг модели в тиках |
| `sm_nadepractice_sim_stop_speed` | 30.0 | скорость после отскока, ниже которой граната останавливается |
| `sm_nadepractice_sim_throw_speed_max` | 750.0 | наибольшая скорость броска |
| `sm_nadepractice_sim_throw_speed_factor` | 6.0 | скорость = (90 − угол броска) × множитель |
| `sm_nadepractice_sim_throw_pitch_offset` | -10.0 | угол броска при взгляде в горизонт |
| `sm_nadepractice_sim_throw_down_scale` | 1.111111 | взгляд вниз: угол броска = смещение + угол взгляда × это (100/90) |
| `sm_nadepractice_sim_throw_up_scale` | 0.888889 | взгляд вверх: угол броска = смещение − угол над горизонтом × это (80/90) |
| `sm_nadepractice_sim_throw_forward` | 16.0 | на сколько юнитов впереди глаз появляется снаряд |
| `sm_nadepractice_sim_hull` | 2.0 | половина размера снаряда для столкновений модели |
| `sm_nadepractice_sim_player_velocity` | 1.0 | доля скорости игрока в броске |

Квары `sm_nadepractice_sim_*` — константы модели полёта; формула начальной скорости проверена по 210 броскам, отскоки подстраиваются на сервере по `!preverror` (инструкция — в TEST_CHECKLIST, этап 8.6).

## Файл лайнапов

`addons/sourcemod/configs/nadepractice/lineups/<карта>.cfg`, KeyValues. Файл переписывается целиком при каждом изменении базы; номера секций значения не имеют. Старые файлы (версии 0.1.0) читаются: отсутствующие ключи получают значения по умолчанию.

```
"Lineups"
{
    "1"
    {
        "name"                 "xbox smoke"
        "type"                 "smoke"            // he | flash | smoke
        "throw"                "runjumpthrow"     // stand | crouch | jump | run | runjump | jumpthrow | runjumpthrow
        "origin"               "-300.0 1200.5 64.03"   // точка броска: позиция игрока (ноги), когда граната вылетела
        "angles"               "-12.4 87.3 0.0"        // углы прицела в момент броска
        "eye"                  "-300.0 1200.5 128.03"  // позиция глаз в момент броска
        "strength"             "1.000000"         // сила nadethrow: 1 — ЛКМ, 0.5 — ЛКМ+ПКМ, 0 — ПКМ (нет ключа — 1.0)
        "start_origin"         "-420.0 1180.0 64.03"   // старт: где встать перед разбегом (нет ключа — старт в точке броска)
        "start_auto"           "1"                // 1 — найден автоматически, 0 — задан !setstart
        "has_projectile"       "1"
        "projectile_origin"    "..."              // начальная позиция снаряда
        "projectile_velocity"  "..."              // начальная скорость снаряда
        "has_detonation"       "1"
        "detonation"           "..."              // точка детонации
        "airtime"              "3.210000"         // от броска до срабатывания, с (нет ключа — не показывается)
        "first_contact"        "0.750000"         // до первого касания, с; -1 — без касаний
        "author"               "player name"
        "description"          "free text"
        "path"                                    // упрощённая траектория, до 32 точек
        {
            "0"    "x y z"
            "1"    "x y z"
        }
    }
}
```

## Gamedata

Файл `gamedata/nadepractice.games.txt`: статические `CHEGrenadeProjectile::Create`, `CFlashbangProjectile::Create`, `CSmokeGrenadeProjectile::Create` для четырёх сборок сервера (Windows 32/64 — байтовые подписи, Linux 32/64 — символы), сделан под `PatchVersion=11003710`. Каждая функция включается отдельно. Если после обновления игры подпись не нашлась, плагин пишет одну строку в лог ошибок, выключает только эту функцию (повтор детонирует плагин) и работает дальше. Состояние — `sm_nadepractice_gamedata`. Как восстановить подпись самому — [GAMEDATA.md](GAMEDATA.md).

Настоящий взрыв и ослепление повтора действуют на **всех** игроков рядом, хотя сам снаряд повтора виден только владельцу.

## Откуда идеи

Проверка ослепления (`!flash`), спавны (`!spawn`, `!bestspawn`, `!worstspawn`) и таймеры (`!timer`, `!timer2`) повторяют устройство команд `.flash`, `.spawn`, `.bestspawn`, `.worstspawn`, `.timer`, `.timer2` из [splewis/csgo-practice-mode](https://github.com/splewis/csgo-practice-mode) (GPL-3.0). Оттуда же — команды с точкой (`.spawn` и т. п.). Код написан заново под CS:S, куски оригинала не переносились.

## API

`scripting/include/nadepractice.inc`, библиотека `nadepractice`, версия API 1:

- `native bool Nadepractice_IsActive()` — запущен ли режим;
- `native int Nadepractice_GetApiVersion()`.

## Известные ограничения

- **Повтор без gamedata**: HE и флешка «взрываются» эффектом без урона и ослепления; дым ставит плагин. С gamedata — настоящий взрыв (см. выше).
- **Дым виден всем**; снаряд повтора — только владельцу. Длительность дыма — свойство дыма бросившего, её видят все.
- **Настоящие броски влияют на всех**: флешка слепит соседей (каждый может включить `!noflash`), дым закрывает обзор.
- **Модель предпросмотра** не учитывает игроков, движущиеся объекты и разбиваемые стёкла; отскоки подстраиваются кварами.
- **Старт разбега** находится, только если перед разбегом игрок стоял (скорость ниже `start_speed`) не дольше `start_lookback` секунд назад; иначе — `!setstart`.
- **Стёртые траектории** исчезают не мгновенно: отправленные лучи доживают до конца цикла перерисовки (около 2 с).
- **Оценка урона HE «в броне»** приблизительная (`sm_nadepractice_he_armor_ratio`), сверяется на сервере.
- Команды `!save`, `!goto`, `!show`, `!delete`, `!back`, `!last`, `!clear`, `!spawn`, `!timer`, `!flash` могут совпасть с командами сторонних плагинов.
- **Подложка панели справа** (KeyHintText) бывает уже длинных строк: текст выходит за тёмный фон, но выводится целиком. Ширину фона считает клиент игры. Если мешает — «Текст подсказки» в меню.
- Цвет «готово» в тексте есть только в `hint_mode 2`; в остальных режимах «готово» показывают рамка прицела и строка «ГОТОВО». Зелёное кольцо под ногами от первого лица не видно — это ориентир издалека.

## Сборка

`./build.sh nadepractice` — компилирует в `build/`. Предупреждение считается ошибкой.

---

<a name="english"></a>

# nadepractice — grenade practice mode for CS:S

A SourceMod 1.12 plugin for Counter-Strike: Source: infinite grenades with no damage, a tracer for real throws, a per-map lineup database, "where to stand and where to aim" hints (run-up start and release point, aim frame), throw replay, a trajectory preview before the throw, a flash check, HE damage, air time, spawns and timers. Everything drawn is visible to its owner only, so several players can practise at once.

> **Status.** Version 0.2.0. The first version (0.1.0) was tested on a server; the rework based on that feedback (`tasks/PRACTICE_TASK.md`, stages 7–15) is written but not yet tested on a server. Everything that depends on engine behaviour and is unverified is marked `CSS-VERIFY` in the code and listed in [TEST_CHECKLIST.md](TEST_CHECKLIST.md).

- Layer (per `ARCHITECTURE.md`): **mode**. Optionally uses `nadethrow` (throw strength). No third-party libraries, no DHooks.
- **Gamedata — by the owner's decision** (an exception to rule 5 of section 2 of `ARCHITECTURE.md`): only for the real detonation of replay projectiles. If the gamedata is out of date, that feature turns off and everything else keeps working (see "Gamedata").
- Owns (while active): players' money, grenades and damage, respawning, the bot count (`bot_quota 0`), its temporary cvars, the flags of the `noclip` console command, players' smoke duration; always — the lineup database.

## Installation

Copy together, on every update:

1. `build/nadepractice.smx` → `addons/sourcemod/plugins/`
2. `translations/nadepractice.phrases.txt` → `addons/sourcemod/translations/`, `translations/ru/nadepractice.phrases.txt` → `addons/sourcemod/translations/ru/`
3. `gamedata/nadepractice.games.txt` → `addons/sourcemod/gamedata/` (for the real replay detonation; the plugin works without it)
4. Reload the map (or `sm plugins reload nadepractice` and `sm_reload_translations`). `cfg/sourcemod/nadepractice.cfg` is generated.
5. Start the mode with `sm_nadepractice_start` (admin, changemap flag) or `sm_nadepractice_autostart 1`.

With outdated translations the menu still opens (phrase names instead of texts), and the error log gets the line `translations/nadepractice.phrases.txt is outdated`.

The plugin creates `addons/sourcemod/configs/nadepractice/lineups/` on the first `!save`.

The mode is meant for its own server configuration: do not load it together with Retakes or other modes (`ARCHITECTURE.md`, section 13).

## What the mode changes

On start it sets temporary cvars; on stop (command, map change, plugin unload, `sm_nadepractice_enabled 0`) the previous values are restored:

| ConVar | Value | Why |
|---|---|---|
| `mp_freezetime` | 0 | no freeze at round start |
| `mp_roundtime` | 9 | maximum round time |
| `mp_ignore_round_win_conditions` | 1 | the round never ends |
| `mp_timelimit`, `mp_maxrounds`, `mp_winlimit`, `mp_fraglimit` | 0 | the map does not change by itself |
| `mp_buytime` | 9999 | buying without a time limit |
| `mp_startmoney` | 16000 | money |
| `mp_limitteams`, `mp_autoteambalance` | 0 | any team |
| `bot_quota` | 0 | no bots |

`sv_cheats` is not touched. While the mode runs, the `noclip` console command loses its cheat flag (the plugin handles it); the flag is restored on stop.

A dead player respawns after `sm_nadepractice_respawn_delay` seconds (rounds never end in this mode); a player joining T/CT mid-round spawns at once.

## Player commands

| Command | What it does |
|---|---|
| `!practice`, `!nadepractice` | main menu |
| `!noclip` | fly through walls (toggle); the console `noclip` works the same in the mode |
| `!back` | to the start (or release point) of the last throw with its angles |
| `!last` | replay the last throw |
| `!clear` | clear your trajectories |
| `!tracer` | show throw trajectories (toggle) |
| `!preview` | trajectory preview while holding a grenade (toggle) |
| `!preverror [reset]` | preview accuracy for the session (per buttons when there are `nadethrow` throws); `reset` starts over |
| `!noflash` | do not get flashed (toggle) |
| `!hands` | bring back a missing first person hands/weapon model |
| `!hints` | hints for the selected lineup (toggle) |
| `!save <name>` | save the last throw as a lineup (after the detonation) |
| `!lineups` | lineup menu: show or hide a lineup on the map (by grenade type, nearest first), "show all", lineup cards |
| `!all` | show all lineups of the map at once (toggle) |
| `!goto <name>` | teleport to the lineup start, grenade in hand, hints |
| `!show <name>` | replay the lineup throw |
| `!delete [name]` | delete a lineup (the selected one without a name) |
| `!rename <new name>` | rename the selected lineup |
| `!desc <text>` | description of the selected lineup |
| `!setstart` | start of the selected lineup (or the last throw) = where you stand (on the ground) |
| `!setrelease` | release point = where you stand |
| `!setaim` | aim = where you look |
| `!nostart` | remove the start: hints lead to the release point |
| `!flash [off]` | flash check point = where you stand; `off` turns it off |
| `!spawn [t\|ct] [N]` | to the nearest spawn of your (or the given) side; `N` = spawn number N |
| `!bestspawn [t\|ct]`, `!worstspawn [t\|ct]` | to the spawn nearest to / farthest from your position |
| `!timer` | timer from the first step to the stop (again to cancel) |
| `!timer2` | manual timer: start, and again to stop |

Names in `!goto`, `!show`, `!delete` may be partial if only one lineup matches. Without a name `!goto` and `!show` use the selected lineup. `!setstart`, `!setrelease`, `!setaim`, `!nostart` change the selected lineup (written to the file at once, `edit_access` rights required), or the last throw before `!save` when no lineup is selected.

While the mode is active, `sm_noclip` / `!noclip` without an argument is handled by `nadepractice` (hence the `NadePractice` chat prefix); outside the mode, and `sm_noclip <name>` for admins, it goes to `funcommands`.

While the mode is active, the plugin's commands also work with a dot: `.spawn`, `.noclip`, `.save name` and so on (`sm_nadepractice_dot_commands`).

Admin commands: `sm_nadepractice_start`, `sm_nadepractice_stop` (changemap flag), `sm_nadepractice_gamedata` (generic flag) — state of the gamedata features.

## The `!practice` menu

Lineups (with a Back button), replay, back, noclip, clear, tracer/preview/hints toggles; **hint text** (panel on the right / centre of the screen / colored under the crosshair); **aim marker** (tolerance frame / cross / sprite); **position check** (auto / start / release point); **edit** start, release point and aim; **measurements** (flash check point, used by flashbangs or flashbangs and HE, return after the check, HE damage report, air time report, `!noflash`); **spawns**; **smoke duration** (game default / 5 / 10 / 30 / 60 s); `!noflash`; "fix hands"; preview accuracy; command list.

## How to use it

**A lineup.** Throw a grenade → `!save name`. The plugin stores the start and the release point, the angles, the throw type, the strength (`nadethrow`), the trajectory, the detonation point and time.

**Several lineups at once.** In `!lineups` every lineup is a toggle: press it to show it on the map, press again to hide it; "Show all" (or `!all`) shows every lineup of the map. Each shown lineup nearby (`sm_nadepractice_show_radius`, at most `sm_nadepractice_show_max` nearest) gets a ring and a pillar in the grenade color where to stand. Walk into a ring (`sm_nadepractice_show_select_radius`) and that lineup is selected automatically with the full hint: aim frame, text, landing point. The hint stays until you walk into the ring of another lineup. Teleport, replay, edit and delete are in "Lineup cards".

**Two places: start and release point.** The start is where to stand before the run-up or the jump, the release point is where the grenade left the hand. Both are found automatically: standing and crouched — one place; jump and jumpthrow — the takeoff point; running — the last point on the ground with speed below `sm_nadepractice_start_speed`, no older than `sm_nadepractice_start_lookback` seconds. The hint draws a yellow ring (the position check target, green within tolerance), a smaller light blue ring (the other place) and the run-up line between them. The aim is the one at the moment of the throw: for a running throw you aim at the start and run without moving the mouse.

**Aim frame.** A square whose angular size equals the tolerance (`2 × sm_nadepractice_hint_angle_tolerance`): crosshair inside the frame means aim within tolerance, and the frame turns green. "READY" in the text means position, aim and buttons all match.

**Jumpthrow.** A separate type: the attack is released in the same tick as the jump press (or within `sm_nadepractice_jumpthrow_ticks`) — what the bind `alias +jt "+jump;-attack"; alias -jt -jump` does. With `nadethrow` the bind must release the right button too: `"+jump;-attack;-attack2"` (see `docs/nadethrow/README.md`). The plugin prints a ready bind in chat once per connection, on the first spawn in the mode. In the first version a jumpthrow counted as a plain "jump" throw.

**`nadethrow`.** When it is loaded, a lineup stores the throw strength (LMB / LMB+RMB / RMB); the hint shows a "Buttons" line and the current strength while the pin is pulled; "ready" only when they match. The preview follows the current strength. Without `nadethrow` everything works as with left click; a right click lineup shows a warning.

**Flash check.** `!flash` where you want to check, walk away, throw a flashbang: the plugin moves you back to the point, you see the grenade arrive and get flashed; the chat shows the duration, strength and distance to the explosion, and who else got flashed. After the blindness you go back to the throw position. With `!noflash` the measurement is still reported ("would be flashed for N s").

**HE damage** — how much the grenade would do (the damage is blocked, but the plugin sees it before), with an "armored" estimate. **Air time** — after each detonation: time to go off, first contact, bounces, in the air or not (for a smoke the pop time is what matters).

**Spawns and timer.** `!timer`, then `!bestspawn` — the timer waits for the first step; that is how the timings of the sides are compared.

**Replay (`!last`, `!show`).** A projectile is created with the saved initial position and velocity; the engine computes the flight. With gamedata the projectile is made by the game itself and detonates for real: a flash blinds, an HE explodes, the smoke is real. Without gamedata HE and flash are "detonated" by the plugin (effect without damage or blindness) and the smoke is spawned by the plugin.

## ConVars

| ConVar | Default | Description |
|---|---|---|
| `sm_nadepractice_version` | 0.2.0 | plugin version |
| `sm_nadepractice_enabled` | 1 | whether the mode is allowed (0 = cannot be started, a running mode stops) |
| `sm_nadepractice_debug` | 0 | verbose log in `logs/nadepractice_debug.log` |
| `sm_nadepractice_autostart` | 0 | start the mode on every map |
| `sm_nadepractice_restart_on_start` | 1 | restart the round on start (`mp_restartgame 1`) |
| `sm_nadepractice_te_per_frame` | 24 | temp entities (beams, rings) per player per network update (engine limit 32) |
| `sm_nadepractice_infinite` | 1 | infinite grenades |
| `sm_nadepractice_give_on_spawn` | 1 | give HE, flashbang and smoke on spawn |
| `sm_nadepractice_block_damage` | 1 | block all damage |
| `sm_nadepractice_block_self_nade_damage` | 1 | block damage from your own grenades (with `block_damage 0`) |
| `sm_nadepractice_respawn_delay` | 1.0 | respawn after this many seconds (0 = off) |
| `sm_nadepractice_respawn_at_death` | 0 | respawn at the death point with the same angles |
| `sm_nadepractice_replay_mode` | 1 | replay: 0 = draw the trajectory only, 1 = projectile |
| `sm_nadepractice_replay_real` | 1 | real replay detonation through the game's `Create()` (gamedata); 0 = plugin-made detonation |
| `sm_nadepractice_replay_engine_fuse` | 0 | old experiment: start the engine timer of a projectile without gamedata (did not work on the server) |
| `sm_nadepractice_replay_visible_all` | 0 | show replay projectiles to everyone |
| `sm_nadepractice_replay_cooldown` | 0.5 | minimum interval between replays, s |
| `sm_nadepractice_replay_smoke_time` | 18.0 | lifetime of a plugin-made replay smoke with the "game default" duration, s |
| `sm_nadepractice_smoke_time_min` | 5 | shortest smoke duration in the menu, s |
| `sm_nadepractice_smoke_time_max` | 60 | longest smoke duration in the menu, s |
| `sm_nadepractice_flash_return` | 1 | return to the throw position after a flash check (per player in the menu) |
| `sm_nadepractice_he_damage_report` | 1 | report HE damage (per-player default) |
| `sm_nadepractice_he_armor_ratio` | 0.5 | armored HE estimate: fraction of the damage that goes to health |
| `sm_nadepractice_airtime_report` | 1 | report air time (per-player default) |
| `sm_nadepractice_timer_speed` | 10.0 | `!timer`: speed above which the player is moving |
| `sm_nadepractice_timer_stop_ticks` | 8 | `!timer`: ticks in a row below the threshold = stop |
| `sm_nadepractice_trace_count` | 5 | trajectories to keep and show (up to 10) |
| `sm_nadepractice_trace_sample` | 0.05 | trajectory sampling step, s |
| `sm_nadepractice_trace_redraw` | 2.0 | trajectory redraw period, s |
| `sm_nadepractice_trace_max_segments` | 24 | segments per drawn trajectory |
| `sm_nadepractice_trace_width` | 1.5 | trajectory line width |
| `sm_nadepractice_trace_max_time` | 12.0 | maximum recording time of a projectile, s |
| `sm_nadepractice_trace_bounce_dv` | 25.0 | bounce detection threshold, units/s per tick |
| `sm_nadepractice_edit_access` | 0 | who may change the database: 0 = everyone, 1 = admins (override `sm_nadepractice_edit`, generic flag) |
| `sm_nadepractice_start_speed` | 10.0 | run-up start: the last point on the ground with speed below this |
| `sm_nadepractice_start_lookback` | 3.0 | how many seconds back to look for the run-up start |
| `sm_nadepractice_jumpthrow_ticks` | 2 | jumpthrow: attack released at most this many ticks from the jump press |
| `sm_nadepractice_hint_interval` | 0.25 | hint update period, s |
| `sm_nadepractice_hint_pos_radius` | 6.0 | position tolerance, units |
| `sm_nadepractice_hint_angle_tolerance` | 0.5 | aim tolerance, degrees |
| `sm_nadepractice_hint_mode` | 0 | default hint output: 0 = KeyHintText (right panel), 1 = HintText (centre), 2 = HUD text (colored); per player in the menu |
| `sm_nadepractice_hint_unicode` | 1 | arrows: 1 = unicode, 0 = ASCII |
| `sm_nadepractice_hint_look_distance` | 300.0 | distance from the eyes to the aim marker |
| `sm_nadepractice_hint_target` | 0 | default position check target: 0 = auto, 1 = start, 2 = release point |
| `sm_nadepractice_show_radius` | 1500.0 | shown lineups: rings for those closer than this, units |
| `sm_nadepractice_show_max` | 8 | shown lineups: rings for at most this many nearest |
| `sm_nadepractice_show_select_radius` | 48.0 | shown lineups: this close to a lineup's place selects it for the full hint, units |
| `sm_nadepractice_dot_commands` | 1 | dot commands (`.spawn`, `.noclip`, ...) work as the `!` commands in the mode |
| `sm_nadepractice_hint_marker` | 0 | default aim marker: 0 = frame, 1 = cross, 2 = sprite |
| `sm_nadepractice_hint_marker_width` | 0.6 | line width of the frame and the cross |
| `sm_nadepractice_preview_default` | 1 | preview on for players by default |
| `sm_nadepractice_preview_interval` | 0.1 | preview update period, s |
| `sm_nadepractice_preview_max_segments` | 14 | segments of the preview line |
| `sm_nadepractice_sim_gravity` | 0.4 | `sv_gravity` multiplier for grenades |
| `sm_nadepractice_sim_elasticity` | 0.45 | grenade elasticity |
| `sm_nadepractice_sim_friction` | 0.2 | friction (only for replay projectiles without gamedata) |
| `sm_nadepractice_sim_fuse` | 1.5 | HE and flash fuse, s |
| `sm_nadepractice_sim_smoke_fuse` | 1.5 | minimum time before a smoke pops, s |
| `sm_nadepractice_sim_think` | 0.2 | detonation check interval, s |
| `sm_nadepractice_sim_max_steps` | 400 | model steps per simulation |
| `sm_nadepractice_sim_max_bounces` | 20 | bounces in the model |
| `sm_nadepractice_sim_tick_mult` | 1 | model step in ticks |
| `sm_nadepractice_sim_stop_speed` | 30.0 | speed after a bounce below which the grenade stops |
| `sm_nadepractice_sim_throw_speed_max` | 750.0 | maximum throw speed |
| `sm_nadepractice_sim_throw_speed_factor` | 6.0 | speed = (90 − throw pitch) × factor |
| `sm_nadepractice_sim_throw_pitch_offset` | -10.0 | throw pitch when looking at the horizon |
| `sm_nadepractice_sim_throw_down_scale` | 1.111111 | looking down: throw pitch = offset + view pitch × this (100/90) |
| `sm_nadepractice_sim_throw_up_scale` | 0.888889 | looking up: throw pitch = offset − angle above the horizon × this (80/90) |
| `sm_nadepractice_sim_throw_forward` | 16.0 | how far in front of the eyes the projectile appears |
| `sm_nadepractice_sim_hull` | 2.0 | half size of the projectile for model collisions |
| `sm_nadepractice_sim_player_velocity` | 1.0 | fraction of the player velocity in the throw |

The `sm_nadepractice_sim_*` cvars are constants of the flight model; the initial velocity formula was checked against 210 throws, bounces are tuned on the server with `!preverror` (instructions in TEST_CHECKLIST, stage 8.6).

## Lineup file

`addons/sourcemod/configs/nadepractice/lineups/<map>.cfg`, KeyValues. The file is rewritten on every change; section numbers are meaningless. Older files (version 0.1.0) are read: missing keys get defaults.

```
"Lineups"
{
    "1"
    {
        "name"                 "xbox smoke"
        "type"                 "smoke"            // he | flash | smoke
        "throw"                "runjumpthrow"     // stand | crouch | jump | run | runjump | jumpthrow | runjumpthrow
        "origin"               "-300.0 1200.5 64.03"   // release point: player position (feet) when the grenade left the hand
        "angles"               "-12.4 87.3 0.0"        // aim angles at the throw
        "eye"                  "-300.0 1200.5 128.03"  // eye position at the throw
        "strength"             "1.000000"         // nadethrow strength: 1 = LMB, 0.5 = LMB+RMB, 0 = RMB (no key = 1.0)
        "start_origin"         "-420.0 1180.0 64.03"   // start: where to stand before the run-up (no key = start at the release point)
        "start_auto"           "1"                // 1 = found automatically, 0 = set with !setstart
        "has_projectile"       "1"
        "projectile_origin"    "..."              // initial projectile position
        "projectile_velocity"  "..."              // initial projectile velocity
        "has_detonation"       "1"
        "detonation"           "..."              // detonation point
        "airtime"              "3.210000"         // from the throw to going off, s (no key = not shown)
        "first_contact"        "0.750000"         // to the first contact, s; -1 = no contact
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

## Gamedata

`gamedata/nadepractice.games.txt`: the static `CHEGrenadeProjectile::Create`, `CFlashbangProjectile::Create`, `CSmokeGrenadeProjectile::Create` for four server builds (Windows 32/64 — byte signatures, Linux 32/64 — symbols), made for `PatchVersion=11003710`. Every function is enabled separately. If a signature is not found after a game update, the plugin writes one line to the error log, turns off only that feature (the replay is detonated by the plugin) and keeps working. State: `sm_nadepractice_gamedata`. How to restore a signature yourself: [GAMEDATA.md](GAMEDATA.md).

A real replay explosion and flash affect **everyone** nearby, even though the replay projectile itself is visible to its owner only.

## Credits

The flash check (`!flash`), spawns (`!spawn`, `!bestspawn`, `!worstspawn`) and timers (`!timer`, `!timer2`) follow the design of the `.flash`, `.spawn`, `.bestspawn`, `.worstspawn`, `.timer`, `.timer2` commands of [splewis/csgo-practice-mode](https://github.com/splewis/csgo-practice-mode) (GPL-3.0). So are the dot commands (`.spawn` and so on). The code is written anew for CS:S; no parts of the original were copied.

## API

`scripting/include/nadepractice.inc`, library `nadepractice`, API version 1:

- `native bool Nadepractice_IsActive()` — whether the mode is running;
- `native int Nadepractice_GetApiVersion()`.

## Known limitations

- **Replay without gamedata**: HE and flash "explode" as an effect without damage or blindness; the smoke is spawned by the plugin. With gamedata — a real explosion (see above).
- **Smoke is visible to everyone**; a replay projectile only to its owner. The smoke duration is a property of the thrower's smoke and everyone sees it.
- **Real throws affect everyone**: a flash blinds neighbours (everyone can use `!noflash`), smoke blocks the view.
- **The preview model** ignores players, moving objects and breakable glass; bounces are tuned with cvars.
- **The run-up start** is found only if the player stood still (speed below `start_speed`) no more than `start_lookback` seconds before; otherwise use `!setstart`.
- **Cleared trajectories** do not vanish instantly: beams already sent live until the end of the redraw cycle (about 2 s).
- **The armored HE estimate** is approximate (`sm_nadepractice_he_armor_ratio`), to be checked on the server.
- Commands `!save`, `!goto`, `!show`, `!delete`, `!back`, `!last`, `!clear`, `!spawn`, `!timer`, `!flash` may clash with third-party plugins.
- **The right panel background** (KeyHintText) can be narrower than long lines: the text goes past the dark background but is shown in full. The client computes the background width. If it bothers you, change "Hint text" in the menu.
- A colored "ready" text exists only in `hint_mode 2`; in the other modes "ready" is shown by the aim frame and the "READY" line. The green ring under your feet cannot be seen in first person — it is a landmark from afar.

## Building

`./build.sh nadepractice` compiles into `build/`. Warnings count as errors.
