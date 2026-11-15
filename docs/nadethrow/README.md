# nadethrow — броски гранат разной силы (CS:S)

[English version below](#english)

Сервис. Добавляет в CS:S броски гранат, как в CS:GO:

| Кнопки в момент броска | Сила | Бросок |
|---|---|---|
| ЛКМ | 1.0 | обычный, плагин ничего не меняет |
| ЛКМ + ПКМ | 0.5 | средний |
| ПКМ | 0.0 | лёгкий, «снизу» |

Пока граната в руке с выдернутой чекой, силу можно менять, зажимая и отпуская кнопки. Бросок происходит, когда отпущены обе.

Основная механика проверена на сервере (броски, сохранение скорости игрока, поправка в том же тике). Что ещё не проверено — в [TEST_CHECKLIST.md](TEST_CHECKLIST.md).

## Установка

- `build/nadethrow.smx` → `addons/sourcemod/plugins/`
- `translations/nadethrow.phrases.txt`, `translations/ru/nadethrow.phrases.txt` → `addons/sourcemod/translations/` (и `ru/`)
- для плагинов, использующих API: `scripting/include/nadethrow.inc`

Зависимостей нет (sdktools, sdkhooks). Без gamedata.

## Квары

Конфиг: `cfg/sourcemod/nadethrow.cfg`.

| Квар | По умолчанию | Смысл |
|---|---|---|
| `sm_nadethrow_enabled` | 1 | включить механику |
| `sm_nadethrow_min_scale` | 0.3 | доля собственной скорости броска при силе 0.0 |
| `sm_nadethrow_z_offset` | 12.0 | на сколько юнитов ниже вылетает граната при силе 0.0 |
| `sm_nadethrow_release_grace` | 0.1 | сколько секунд после отпускания одной из двух кнопок сила ещё считается по обеим; 0 — строго по последнему тику |
| `sm_nadethrow_announce` | 1 | один раз за подключение написать игроку в чат, как бросать с разной силой |
| `sm_nadethrow_bots` | 0 | обрабатывать ли ввод ботов |
| `sm_nadethrow_debug` | 0 | лог в `logs/nadethrow_debug.log`: сила, скорость и позиция до и после поправки |
| `sm_nadethrow_version` | — | версия |

Команд нет.

## Jumpthrow

Обычный алиас отпускает только ЛКМ, поэтому с ПКМ и ЛКМ+ПКМ не сработает: ПКМ остаётся зажатой, и граната остаётся в руке. Сервер не может отличить `-attack` из алиаса от отпущенной кнопки, так что алиас нужно дополнить `-attack2` (как в CS:GO):

```
alias "+jumpthrow" "+jump; -attack; -attack2"
alias "-jumpthrow" "-jump"
```

С ним обе кнопки отпускаются в одном тике, и сила берётся по тем, что были зажаты: ЛКМ — 1.0, ЛКМ+ПКМ — 0.5, ПКМ — 0.0.

## Как это работает

1. **Ввод.** Пока в руке `weapon_hegrenade`, `weapon_flashbang` или `weapon_smokegrenade` и зажата ПКМ, плагин подменяет её на `IN_ATTACK`: игра выдёргивает чеку и держит гранату как обычно. Если зажата только ЛКМ, команда игрока не меняется вообще.
2. **Сила.** Считается по зажатым кнопкам. Когда отпущены обе и чека была выдернута, сила запоминается; игра создаёт снаряд примерно через 0.1 с.
3. **Снаряд.** При силе меньше 1.0:
   - скорость: `new = (v - playerVel) * k + playerVel`, `k = min_scale + (1 - min_scale) * strength` — скорость игрока сохраняется, уменьшается только сам бросок;
   - позиция: ниже на `(1 - strength) * z_offset`, если по пути нет стены или пола (иначе остаётся исходной).

   При значениях по умолчанию: ЛКМ+ПКМ — 65 % скорости и −6 юнитов, ПКМ — 30 % и −12.
4. Таймер детонации не меняется.

## API

`scripting/include/nadethrow.inc`, библиотека `nadethrow`, версия API 1.

```sourcepawn
native int   Nadethrow_GetApiVersion();
native bool  Nadethrow_IsEnabled();
native float Nadethrow_GetThrowStrength(int client);  // 0.0–1.0 при выдернутой чеке, иначе -1.0
native float Nadethrow_GetMinScale();
native float Nadethrow_GetZOffset();

forward void Nadethrow_OnGrenadeThrown(int client, int projectile, float strength);
```

- `Nadethrow_OnGrenadeThrown` вызывается после поправки снаряда, для любых бросков, включая силу 1.0 и броски ботов. Если плагин выключен — не вызывается.
- Для предпросмотра траектории в другом плагине достаточно `GetThrowStrength`, `GetMinScale`, `GetZOffset` и формул выше.
- Подключать как необязательную зависимость (раздел 6 `ARCHITECTURE.md`).

## Известные ограничения

- Анимация броска в CS:S одна: бросок «снизу» выглядит как обычный, и от первого лица, и со стороны.
- Клиент не знает, что ПКМ выдёргивает чеку: анимация рук при ПКМ приходит с сервера и может запаздывать на величину пинга, а при удержании ПКМ клиент может на мгновение показать анимацию броска. Звук чеки при нажатии ЛКМ поверх ПКМ плагин подавляет, сдвигая `m_flNextPrimaryAttack` гранаты, пока чека выдернута.
- Jumpthrow с ПКМ требует `-attack2` в алиасе (см. выше).
- Средний бросок: если отпустить одну кнопку и держать вторую дольше `sm_nadethrow_release_grace`, сила изменится на силу оставшейся кнопки. Это поведение по заданию; пауза нужна только для того, чтобы «отпустил обе почти одновременно» давало средний бросок.
- ПКМ с гранатой в руке больше не доходит до игры и других плагинов (если им нужен `IN_ATTACK2` с гранатой).
- Ввод ботов обрабатывается только при `sm_nadethrow_bots 1`; сами боты ПКМ не нажимают.
- Значения `min_scale` и `z_offset` — приблизительные, из CS:GO; их нужно подобрать на сервере.

---

<a name="english"></a>

# nadethrow — variable-strength grenade throws (CS:S)

A service plugin that adds CS:GO-style grenade throws to Counter-Strike: Source:

| Buttons at the moment of the throw | Strength | Throw |
|---|---|---|
| Left click | 1.0 | normal, the plugin changes nothing |
| Left + right click | 0.5 | medium |
| Right click | 0.0 | light, underhand |

While the pin is pulled, the strength follows the buttons currently held. The grenade is thrown when both are released.

The core mechanic has been tested on a server (throws, kept player velocity, same-tick adjustment). What is still unverified is listed in [TEST_CHECKLIST.md](TEST_CHECKLIST.md).

## Installation

- `build/nadethrow.smx` → `addons/sourcemod/plugins/`
- `translations/nadethrow.phrases.txt`, `translations/ru/nadethrow.phrases.txt` → `addons/sourcemod/translations/` (and `ru/`)
- for plugins that use the API: `scripting/include/nadethrow.inc`

No dependencies (sdktools, sdkhooks) and no gamedata.

## ConVars

Config file: `cfg/sourcemod/nadethrow.cfg`.

| ConVar | Default | Meaning |
|---|---|---|
| `sm_nadethrow_enabled` | 1 | enable the mechanic |
| `sm_nadethrow_min_scale` | 0.3 | fraction of the throw's own speed at strength 0.0 |
| `sm_nadethrow_z_offset` | 12.0 | how many units lower the grenade is released at strength 0.0 |
| `sm_nadethrow_release_grace` | 0.1 | seconds during which releasing one of two held buttons does not change the strength; 0 = strictly the last tick |
| `sm_nadethrow_announce` | 1 | tell each player in chat, once per connection, how to throw with different strength |
| `sm_nadethrow_bots` | 0 | process bot input |
| `sm_nadethrow_debug` | 0 | log to `logs/nadethrow_debug.log`: strength, velocity and position before and after the adjustment |
| `sm_nadethrow_version` | — | version |

No commands.

## Jumpthrow

The usual alias releases left click only, so it does not work with right or left + right click: right click stays held and the grenade stays in hand. The server cannot tell `-attack` in an alias from a released button, so the alias needs `-attack2` (as in CS:GO):

```
alias "+jumpthrow" "+jump; -attack; -attack2"
alias "-jumpthrow" "-jump"
```

Both buttons are then released in the same tick and the strength follows the ones that were held: left — 1.0, left + right — 0.5, right — 0.0.

## How it works

1. **Input.** While `weapon_hegrenade`, `weapon_flashbang` or `weapon_smokegrenade` is the active weapon and right click is held, the plugin replaces it with `IN_ATTACK`, so the game pulls the pin and holds the grenade as usual. With left click only, the player's command is not touched at all.
2. **Strength.** Derived from the held buttons. When both are released and the pin was pulled, the strength is remembered; the game creates the projectile about 0.1 s later.
3. **Projectile.** For strength below 1.0:
   - velocity: `new = (v - playerVel) * k + playerVel`, `k = min_scale + (1 - min_scale) * strength` — the player's velocity is kept, only the throw itself is scaled;
   - position: lowered by `(1 - strength) * z_offset` unless a wall or floor is in the way (then the original position is kept).

   With defaults: left+right — 65 % speed and −6 units, right — 30 % and −12.
4. The detonation timer is not changed.

## API

`scripting/include/nadethrow.inc`, library `nadethrow`, API version 1.

```sourcepawn
native int   Nadethrow_GetApiVersion();
native bool  Nadethrow_IsEnabled();
native float Nadethrow_GetThrowStrength(int client);  // 0.0–1.0 while the pin is pulled, otherwise -1.0
native float Nadethrow_GetMinScale();
native float Nadethrow_GetZOffset();

forward void Nadethrow_OnGrenadeThrown(int client, int projectile, float strength);
```

- `Nadethrow_OnGrenadeThrown` fires after the projectile has been adjusted, for every throw, including strength 1.0 and bot throws. It does not fire while the plugin is disabled.
- A trajectory preview in another plugin only needs `GetThrowStrength`, `GetMinScale`, `GetZOffset` and the formulas above.
- Use it as an optional dependency (`ARCHITECTURE.md`, section 6).

## Known limitations

- CS:S has a single throw animation: an underhand throw looks like a normal one in both first and third person.
- The client does not know that right click pulls the pin: the viewmodel animation on right click comes from the server and may lag by the player's ping, and while right click is held the client may briefly show the throw animation. The pin sound on pressing left click over right click is suppressed by pushing the grenade's `m_flNextPrimaryAttack` forward while the pin is pulled.
- A right click jumpthrow needs `-attack2` in the alias (see above).
- Medium throw: releasing one button and holding the other for longer than `sm_nadethrow_release_grace` switches the strength to the remaining button. The grace period only exists so that "released both almost at once" still gives a medium throw.
- Right click with a grenade in hand no longer reaches the game or other plugins.
- Bot input is processed only with `sm_nadethrow_bots 1`; bots never press right click on their own.
- `min_scale` and `z_offset` are approximate CS:GO values and need tuning on the server.
