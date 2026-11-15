/*
 * example_consumer - template of a plugin that OPTIONALLY uses the example service.
 *
 * Layer:   mode
 * Owns:    <...>
 * Uses:    example (optional)
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
    description = "Template of a plugin with an optional dependency",
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

// Every call to the service goes through wrappers like this one.
bool IsExampleActive() {
    return g_bHasExample && Example_IsActive();
}

// Service forwards: if the service is not loaded, they are simply never called.
public void Example_OnEnd() {
    // start the mode
}

public Action Example_OnEnding() {
    // return Plugin_Handled;  // ask to wait
    return Plugin_Continue;
}

public void OnPluginStart() {
    HookEvent("player_spawn", Event_PlayerSpawn);  // modes hook in Post (the default)
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    if (IsExampleActive()) {
        return;  // the mode stays out while the service is active
    }
    // ...
}
