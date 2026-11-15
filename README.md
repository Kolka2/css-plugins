# css-plugins

SourceMod-плагины для сервера Counter-Strike: Source (SourceMod 1.12, Metamod:Source 1.12).

## Начало работы

```
cd css-plugins
git init && git add -A && git commit -m "Initial layout"
./build.sh            # собрать все плагины в build/
```

Дальше — новая сессия Claude Code в этой папке; как запускать задания, написано в `tasks/README.md`.

## Что где

| Путь | Что |
|---|---|
| `CLAUDE.md` | правила для агента |
| `ARCHITECTURE.md` | архитектура и правила написания плагинов |
| `templates/` | шаблоны плагина-сервиса, его API и плагина с необязательной зависимостью |
| `tasks/` | задания и их очередь |
| `scripting/` | исходники плагинов; `scripting/include/` — их API |
| `translations/` | переводы |
| `docs/<плагин>/` | README, чек-лист проверки, прогресс |
| `tools/` | компилятор SourcePawn 1.12 (Linux x86_64) и include-файлы SourceMod 1.12 |

## Установка на сервер

`build/<плагин>.smx` → `addons/sourcemod/plugins/`, `translations/` → `addons/sourcemod/translations/`, остальное — по README плагина.
