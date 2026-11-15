/*
 * example_consumer — шаблон плагина, который НЕОБЯЗАТЕЛЬНО использует сервис example.
 *
 * Слой:        режим
 * Владеет:     <...>
 * Использует:  example (необязательно)
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>

#undef REQUIRE_PLUGIN
#include <example>
#define REQUIRE_PLUGIN

public Plugin myinfo = {
    name        = "[CS:S] Example consumer",
    author      = "you",
    description = "Шаблон плагина с необязательной зависимостью",
    version     = "0.1.0",
    url         = ""
};

bool g_bHasExample;

public void OnAllPluginsLoaded() {
    g_bHasExample = LibraryExists(EXAMPLE_LIBRARY);
}

public void OnLibraryAdded(const char[] name) {
    if (StrEqual(name, EXAMPLE_LIBRARY)) {
        g_bHasExample = true;
    }
}

public void OnLibraryRemoved(const char[] name) {
    if (StrEqual(name, EXAMPLE_LIBRARY)) {
        g_bHasExample = false;
    }
}

// Все обращения к сервису — только через такие обёртки.
bool IsExampleActive() {
    return g_bHasExample && Example_IsActive();
}

// Форварды сервиса: если сервис не загружен, они просто не вызываются.
public void Example_OnEnd() {
    // начать работу режима
}

public Action Example_OnEnding() {
    // return Plugin_Handled;  // попросить подождать
    return Plugin_Continue;
}

public void OnPluginStart() {
    HookEvent("player_spawn", Event_PlayerSpawn);  // режимы — в Post (по умолчанию)
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    if (IsExampleActive()) {
        return;  // во время работы сервиса режим не вмешивается
    }
    // ...
}
