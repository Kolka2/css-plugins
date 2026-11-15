/*
 * example — шаблон плагина-сервиса.
 *
 * Слой:        сервис
 * Владеет:     <что меняет только этот плагин: квары, свойства игроков, фазы>
 * Читает:      <чужое состояние, которое только читает>
 * Использует:  <необязательные зависимости, например warmup>
 * API:         include/example.inc
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>
#include <example>

#define PLUGIN_VERSION "0.1.0"

public Plugin myinfo = {
    name        = "[CS:S] Example",
    author      = "you",
    description = "Шаблон плагина-сервиса",
    version     = PLUGIN_VERSION,
    url         = ""
};

ConVar g_cvEnabled;
ConVar g_cvDebug;

GlobalForward g_fwdOnStart;
GlobalForward g_fwdOnEnd;
GlobalForward g_fwdOnEnding;

StringMap g_SavedCvars;
char g_DebugLogPath[PLATFORM_MAX_PATH];

bool g_bActive;

// ---------------------------------------------------------------------------
// Загрузка
// ---------------------------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    if (GetEngineVersion() != Engine_CSS) {
        strcopy(error, err_max, "This plugin supports Counter-Strike: Source only.");
        return APLRes_Failure;
    }

    CreateNative("Example_IsActive", Native_IsActive);
    CreateNative("Example_GetApiVersion", Native_GetApiVersion);
    RegPluginLibrary(EXAMPLE_LIBRARY);
    return APLRes_Success;
}

public void OnPluginStart() {
    // LoadTranslations("example.phrases");

    CreateConVar("sm_example_version", PLUGIN_VERSION, "Версия плагина", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvEnabled = CreateConVar("sm_example_enabled", "1", "Включён ли плагин", _, true, 0.0, true, 1.0);
    g_cvDebug   = CreateConVar("sm_example_debug", "0", "Подробный лог в logs/example_debug.log", _, true, 0.0, true, 1.0);
    AutoExecConfig(true, "example");

    g_fwdOnStart  = new GlobalForward("Example_OnStart", ET_Ignore);
    g_fwdOnEnd    = new GlobalForward("Example_OnEnd", ET_Ignore);
    g_fwdOnEnding = new GlobalForward("Example_OnEnding", ET_Hook);

    g_SavedCvars = new StringMap();
    BuildPath(Path_SM, g_DebugLogPath, sizeof(g_DebugLogPath), "logs/example_debug.log");

    // Сервисы меняют состояние в Pre, режимы реагируют в Post.
    HookEvent("round_end", Event_RoundEnd, EventHookMode_Pre);

    RegAdminCmd("sm_example_start", Command_Start, ADMFLAG_CHANGEMAP, "Запустить сервис");
    RegAdminCmd("sm_example_stop", Command_Stop, ADMFLAG_CHANGEMAP, "Остановить сервис");

    // Поздняя загрузка: обработать игроков, которые уже на сервере.
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client)) {
            OnClientPutInServer(client);
        }
    }
}

public void OnMapEnd() {
    Stop(false);
}

public void OnPluginEnd() {
    Stop(false);
}

public void OnClientPutInServer(int client) {
    // SDKHook(client, SDKHook_..., ...);
}

// ---------------------------------------------------------------------------
// Логика
// ---------------------------------------------------------------------------

void Start() {
    if (g_bActive || !g_cvEnabled.BoolValue) {
        return;
    }
    g_bActive = true;

    SetCvarTemporarily("mp_buytime", "9999");
    LogDebug("start");

    Call_StartForward(g_fwdOnStart);
    Call_Finish();
}

// notify = false — тихая остановка (смена карты, выгрузка): без форвардов.
void Stop(bool notify) {
    if (!g_bActive) {
        return;
    }
    g_bActive = false;

    RestoreCvars();
    LogDebug("stop (notify=%d)", notify);

    if (notify) {
        Call_StartForward(g_fwdOnEnd);
        Call_Finish();
    }
}

// Спросить подписчиков, можно ли закончить (форвард с вето).
bool CanStop() {
    Action result = Plugin_Continue;
    Call_StartForward(g_fwdOnEnding);
    Call_Finish(result);
    return result < Plugin_Handled;
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }
    // ...
}

public Action Command_Start(int client, int args) {
    Start();
    return Plugin_Handled;
}

public Action Command_Stop(int client, int args) {
    if (CanStop()) {
        Stop(true);
    } else {
        ReplyToCommand(client, "[Example] Another plugin asked to wait.");
    }
    return Plugin_Handled;
}

// Таймеры получают userid, а не индекс клиента: за секунду игрок может выйти,
// а его слот занять другой.
stock void ExampleDelayedAction(int client) {
    CreateTimer(1.0, Timer_DelayedAction, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_DelayedAction(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client == 0 || !IsClientInGame(client)) {
        return Plugin_Stop;
    }
    // ...
    return Plugin_Stop;
}

// ---------------------------------------------------------------------------
// Нативы
// ---------------------------------------------------------------------------

public int Native_IsActive(Handle plugin, int numParams) {
    return g_bActive;
}

public int Native_GetApiVersion(Handle plugin, int numParams) {
    return EXAMPLE_API_VERSION;
}

// ---------------------------------------------------------------------------
// Вспомогательное
// ---------------------------------------------------------------------------

// Меняет квар, запомнив исходное значение (только при первом изменении).
void SetCvarTemporarily(const char[] name, const char[] value) {
    ConVar cvar = FindConVar(name);
    if (cvar == null) {
        LogError("ConVar \"%s\" not found", name);
        return;
    }

    char original[256];
    if (!g_SavedCvars.GetString(name, original, sizeof(original))) {
        cvar.GetString(original, sizeof(original));
        g_SavedCvars.SetString(name, original);
    }
    cvar.SetString(value);
}

// Возвращает все квары, изменённые через SetCvarTemporarily.
void RestoreCvars() {
    StringMapSnapshot snapshot = g_SavedCvars.Snapshot();
    char name[128], value[256];
    for (int i = 0; i < snapshot.Length; i++) {
        snapshot.GetKey(i, name, sizeof(name));
        g_SavedCvars.GetString(name, value, sizeof(value));
        ConVar cvar = FindConVar(name);
        if (cvar != null) {
            cvar.SetString(value);
        }
    }
    delete snapshot;
    g_SavedCvars.Clear();
}

void LogDebug(const char[] format, any ...) {
    if (!g_cvDebug.BoolValue) {
        return;
    }
    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 2);
    LogToFileEx(g_DebugLogPath, "%s", buffer);
}
