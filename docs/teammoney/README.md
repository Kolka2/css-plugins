# teammoney — деньги и гранаты команды (CS:S)

[English version below](#english)

Слой: утилита. Зависимостей и публичного API нет.

Во время фризтайма и `sm_teammoney_extra_time` секунд после него показывает каждому игроку в KeyHintText (справа на экране) деньги, гранаты и наборы сапёра его команды, отсортированные по деньгам: `Ник — $4500 [FFHS|D]` (F — флешка, H — HE, S — дым, D — набор сапёра; без гранат — `[D]`). У мёртвых — только деньги и подпись «мёртв».

Подписи выводятся на языке игрока (en и ru); игроки с разными языками в одной команде видят каждый свой вариант.

Установка: `build/teammoney.smx` → `addons/sourcemod/plugins/`, `translations/` → `addons/sourcemod/translations/`.

| Квар | По умолчанию | Смысл |
|---|---|---|
| `sm_teammoney_enabled` | 1 | включить |
| `sm_teammoney_extra_time` | 5.0 | сколько секунд показывать после конца фризтайма |
| `sm_teammoney_interval` | 0.25 | период обновления |
| `sm_teammoney_name_length` | 12 | максимум символов ника |
| `sm_teammoney_layout` | 0 | вид строки: 0 — `Ник — $4500 [FFHS\|D]`; 1 — `$4500 [FFHS\|D] Ник` (деньги ровным столбцом слева) |
| `sm_teammoney_debug` | 0 | лог в `logs/teammoney_debug.log` |

## Как это работает

- Показ начинается на `round_start` и заканчивается через `sm_teammoney_extra_time` секунд после `round_freeze_end`. Верхнего предела нет: при длинном фризтайме HUD висит всё время.
- Если плагин загружен или включён (`sm_teammoney_enabled 0 → 1`) посреди фризтайма, показ начинается сразу.
- HUD гаснет на 0,2 с позже расчётного времени: скрытие отправляется с задержкой, чтобы не обогнать последнее обновление.

## Известные ограничения

- В одно сообщение помещается около пяти игроков с длинными кириллическими никами; остальные сворачиваются в строку «и ещё N».
- Изменение `sm_teammoney_interval` применяется со следующего раунда.
- Наблюдатели HUD не видят.
- Выровнять текст по колонкам нельзя: шрифт пропорциональный, а KeyHintText не умеет выравнивание. `sm_teammoney_layout 1` даёт только ровный столбец денег слева.
- Если файла фраз нет, HUD показывается без подписей, в логе ошибок — одна запись.

## История

- **2.2.0** — пробный вид строки «деньги слева»: `sm_teammoney_layout 1`.
- **2.1.0** — набор сапёра в HUD: `[FFHS|D]`.
- **2.0.1** — подписи на языке игрока; проверка фраз перед выводом; скрытие HUD с задержкой; старт показа посреди фризтайма; код на английском.
- **2.0.0** — переписано на основе sm_team_money 1.0.3.

Что проверить на сервере — в [TEST_CHECKLIST.md](TEST_CHECKLIST.md).

---

<a name="english"></a>

# teammoney — team money and grenades (CS:S)

A utility plugin. No dependencies and no public API.

During freeze time and for `sm_teammoney_extra_time` seconds after it, each player sees the money, grenades and defuse kits of their team in KeyHintText (on the right side of the screen), sorted by money: `Name — $4500 [FFHS|D]` (F — flashbang, H — HE, S — smoke, D — defuse kit; with no grenades — `[D]`). Dead players are shown with money only and the label "dead".

Labels are shown in each player's own language (en and ru); teammates with different languages each see their own version.

The plugin has not been verified on a live server yet. What needs checking is listed in [TEST_CHECKLIST.md](TEST_CHECKLIST.md) (in Russian).

## Installation

- `build/teammoney.smx` → `addons/sourcemod/plugins/`
- `translations/teammoney.phrases.txt`, `translations/ru/teammoney.phrases.txt` → `addons/sourcemod/translations/` (and `ru/`)

## ConVars

| ConVar | Default | Meaning |
|---|---|---|
| `sm_teammoney_enabled` | 1 | enable |
| `sm_teammoney_extra_time` | 5.0 | seconds to keep showing after freeze time ends |
| `sm_teammoney_interval` | 0.25 | update period |
| `sm_teammoney_name_length` | 12 | maximum characters of a player name |
| `sm_teammoney_layout` | 0 | line layout: 0 — `Name — $4500 [FFHS\|D]`; 1 — `$4500 [FFHS\|D] Name` (money as a straight left column) |
| `sm_teammoney_debug` | 0 | log to `logs/teammoney_debug.log` |

## How it works

- The HUD appears on `round_start` and disappears `sm_teammoney_extra_time` seconds after `round_freeze_end`. There is no upper limit: with a long freeze time it stays up the whole time.
- If the plugin is loaded or enabled (`sm_teammoney_enabled 0 → 1`) in the middle of freeze time, the HUD appears immediately.
- The HUD disappears 0.2 s later than the calculated time: the hide message is delayed so that it does not overtake the last update.

## Known limitations

- One message fits about five players with long Cyrillic names; the rest are folded into a "+N more" line.
- A change of `sm_teammoney_interval` takes effect from the next round.
- Spectators do not see the HUD.
- The text cannot be aligned in columns: the font is proportional and KeyHintText has no alignment. `sm_teammoney_layout 1` only gives a straight left column of money.
- If the phrase file is missing, the HUD is shown without labels and one entry is written to the error log.

## History

- **2.2.0** — experimental "money first" line layout: `sm_teammoney_layout 1`.
- **2.1.0** — defuse kit in the HUD: `[FFHS|D]`.
- **2.0.1** — labels in the player's language; phrases are checked before output; delayed HUD hide; start in the middle of freeze time; code in English.
- **2.0.0** — rewritten on the basis of sm_team_money 1.0.3.
