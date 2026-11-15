/*
 * teammoney - team money, grenades and defuse kits in KeyHintText during freeze time.
 *
 * Layer:   utility
 * Owns:    its own HUD message (KeyHintText) during freeze time and N seconds after it
 * Reads:   money (m_iAccount), players' weapons and ammo, defuse kit (m_bHasDefuser), round events
 * Uses:    nothing
 *
 * Based on sm_team_money 1.0.3. Differences from 1.0.3:
 *  - one refresh timer and one stop timer, old ones are cancelled on a new round;
 *    the end of the display is counted from round_freeze_end, not from mp_freezetime;
 *  - the message fits the user message byte limit, extra players collapse into "+N";
 *  - names are truncated on a UTF-8 character boundary;
 *  - grenades are counted from the player's weapons and their ammo type, not hardcoded indices;
 *  - dead players show money only;
 *  - team players are sorted by money;
 *  - refreshes are sent unreliably, the hide message reliably and after a short delay.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define PLUGIN_VERSION "2.1.0"

// User message data in Source is limited to ~255 bytes; KeyHintText adds a string
// count byte and a terminating zero. Keep a margin.
#define MAX_HINT_BYTES 240
// Bytes kept in reserve for the "+N" line.
#define MORE_LINE_RESERVE 24

// Languages cached per refresh; viewers beyond that get their text built individually.
#define MAX_CACHED_LANGS 8

// Delay between the last refresh and the hide message. Must exceed the longest gap between
// packets to a client (1 / sv_minupdaterate, 0.1 s by default), see StopDisplay.
#define HIDE_DELAY 0.2

// Fallback m_iAmmo indices for CS:S, used if the weapon's ammo type cannot be read.
#define AMMO_HEGRENADE_FALLBACK  11
#define AMMO_FLASHBANG_FALLBACK  12
#define AMMO_SMOKE_FALLBACK      13

public Plugin myinfo = {
    name        = "[CS:S] Team money & nades",
    author      = "Kolka2",
    description = "Shows team money and grenades in KeyHintText during freeze time",
    version     = PLUGIN_VERSION,
    url         = ""
};

ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvExtraTime;
ConVar g_cvInterval;
ConVar g_cvNameLength;

enum StopMode {
    Stop_Silent,        // new round, map end: nothing to hide
    Stop_HideNow,       // plugin unload: timers will not survive
    Stop_HideDeferred   // normal end of the display
};

Handle g_hRefreshTimer;
Handle g_hStopTimer;
Handle g_hHideTimer;
bool g_bActive;
bool g_bLate;
bool g_bMapStarted;
bool g_bLoggedSendError;

// Who has been shown the HUD in the current display (to hide it only for them).
bool g_bShownTo[MAXPLAYERS + 1];
// Money at the moment the message is built (for sorting).
int g_iMoney[MAXPLAYERS + 1];

char g_DebugLogPath[PLATFORM_MAX_PATH];

// Team texts of the current refresh, one per language in use ([lang slot][0 = T, 1 = CT]).
int g_iCacheLang[MAX_CACHED_LANGS];
char g_TextCache[MAX_CACHED_LANGS][2][MAX_HINT_BYTES + 1];
bool g_bCacheBuilt[MAX_CACHED_LANGS][2];

bool g_bHasPhraseDead;
bool g_bHasPhraseMore;
bool g_bLoggedNoPhrase;

// Whether weapons have m_iPrimaryAmmoType (otherwise fallback indices are used).
bool g_bHasAmmoTypeProp;
// Whether players have m_bHasDefuser (otherwise the defuse kit is not shown).
bool g_bHasDefuserProp;

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    if (GetEngineVersion() != Engine_CSS) {
        strcopy(error, err_max, "This plugin supports Counter-Strike: Source only.");
        return APLRes_Failure;
    }
    g_bLate = late;
    return APLRes_Success;
}

public void OnPluginStart() {
    if (GetUserMessageId("KeyHintText") == INVALID_MESSAGE_ID || GetUserMessageType() != UM_BitBuf) {
        SetFailState("KeyHintText user message is not available.");
    }

    LoadTranslations("teammoney.phrases");

    g_bHasAmmoTypeProp = FindSendPropInfo("CBaseCombatWeapon", "m_iPrimaryAmmoType") != -1;
    if (!g_bHasAmmoTypeProp) {
        LogError("m_iPrimaryAmmoType not found, using fixed CS:S ammo indices");
    }

    // CSS-VERIFY: CCSPlayer has m_bHasDefuser in CS:S and it is 1 for a CT with a defuse kit.
    g_bHasDefuserProp = FindSendPropInfo("CCSPlayer", "m_bHasDefuser") != -1;
    if (!g_bHasDefuserProp) {
        LogError("m_bHasDefuser not found, defuse kits will not be shown");
    }

    CreateConVar("sm_teammoney_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvEnabled    = CreateConVar("sm_teammoney_enabled", "1", "Show team money and grenades during freeze time", _, true, 0.0, true, 1.0);
    g_cvDebug      = CreateConVar("sm_teammoney_debug", "0", "Verbose log in logs/teammoney_debug.log", _, true, 0.0, true, 1.0);
    g_cvExtraTime  = CreateConVar("sm_teammoney_extra_time", "5.0", "Seconds to keep showing after freeze time ends", _, true, 0.0, true, 30.0);
    g_cvInterval   = CreateConVar("sm_teammoney_interval", "0.25", "Refresh period in seconds", _, true, 0.1, true, 2.0);
    g_cvNameLength = CreateConVar("sm_teammoney_name_length", "12", "Maximum characters of a player name", _, true, 4.0, true, 32.0);
    AutoExecConfig(true, "teammoney");

    g_cvEnabled.AddChangeHook(OnEnabledChanged);

    BuildPath(Path_SM, g_DebugLogPath, sizeof(g_DebugLogPath), "logs/teammoney_debug.log");

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
}

public void OnAllPluginsLoaded() {
    LogMessage("[teammoney] %s, optional libraries: none", PLUGIN_VERSION);
}

public void OnMapStart() {
    g_bMapStarted = true;

    // Late load: there are no per-client hooks to restore, but if the plugin was (re)loaded
    // during freeze time (e.g. a long pause), start showing right away, not from the next round.
    if (g_bLate) {
        g_bLate = false;
        if (g_cvEnabled.BoolValue && IsFreezePeriod()) {
            StartDisplay();
        }
    }
}

public void OnMapEnd() {
    g_bMapStarted = false;
    StopDisplay(Stop_Silent);
}

public void OnPluginEnd() {
    StopDisplay(Stop_HideNow);
}

public void OnClientDisconnect(int client) {
    g_bShownTo[client] = false;
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (!convar.BoolValue) {
        StopDisplay(Stop_HideDeferred);
    } else if (!g_bActive && g_bMapStarted && IsFreezePeriod()) {
        StartDisplay();
    }
}

bool IsFreezePeriod() {
    // CSS-VERIFY: m_bFreezePeriod is readable through GameRules_GetProp in CS:S and is 1
    // from round_start until round_freeze_end.
    if (FindEntityByClassname(-1, "cs_gamerules") == -1) {
        return false;
    }
    return GameRules_GetProp("m_bFreezePeriod") != 0;
}

// ---------------------------------------------------------------------------
// Display lifecycle
// ---------------------------------------------------------------------------

public void Event_RoundStart(Event event, const char[] name, bool dontBroadcast) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    StartDisplay();
}

public void Event_RoundFreezeEnd(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }

    delete g_hStopTimer;
    float extra = g_cvExtraTime.FloatValue;
    if (extra <= 0.0) {
        StopDisplay(Stop_HideDeferred);
        return;
    }
    g_hStopTimer = CreateTimer(extra, Timer_Stop);
    LogDebug("freeze end, hiding in %.1f s", extra);
}

void StartDisplay() {
    // A new round cancels whatever is left from the previous one (including after a restart).
    // A pending hide is cancelled too: the new display overwrites the HUD.
    StopDisplay(Stop_Silent);

    g_bActive = true;
    g_bLoggedSendError = false;
    g_hRefreshTimer = CreateTimer(g_cvInterval.FloatValue, Timer_Refresh, _, TIMER_REPEAT);
    LogDebug("display started");
    Refresh();
}

void StopDisplay(StopMode mode) {
    g_bActive = false;
    delete g_hRefreshTimer;
    delete g_hStopTimer;
    delete g_hHideTimer;

    if (mode == Stop_HideDeferred) {
        // Refreshes are unreliable, the hide is reliable. If both end up in one packet, the
        // client is expected to process the reliable hide first and the stale refresh after
        // it, leaving the HUD on screen. Sending the hide later puts it in a later packet.
        // CSS-VERIFY: the HUD never stays on screen after the display ends (also with cl_updaterate 10).
        g_hHideTimer = CreateTimer(HIDE_DELAY, Timer_Hide);
        LogDebug("display stopped, hiding in %.1f s", HIDE_DELAY);
        return;
    }

    HideAll(mode == Stop_HideNow);
    LogDebug("display stopped (mode=%d)", mode);
}

// send = true: erase the HUD for those it was shown to; false: only forget who saw it.
void HideAll(bool send) {
    for (int client = 1; client <= MaxClients; client++) {
        if (g_bShownTo[client]) {
            if (send && IsClientInGame(client)) {
                SendKeyHint(client, "", true);
            }
            g_bShownTo[client] = false;
        }
    }
}

public Action Timer_Refresh(Handle timer) {
    Refresh();
    return Plugin_Continue;
}

public Action Timer_Stop(Handle timer) {
    g_hStopTimer = null;  // this timer ends by itself, StopDisplay must not delete it again
    StopDisplay(Stop_HideDeferred);
    return Plugin_Stop;
}

public Action Timer_Hide(Handle timer) {
    g_hHideTimer = null;
    HideAll(true);
    return Plugin_Stop;
}

// ---------------------------------------------------------------------------
// Building and sending
// ---------------------------------------------------------------------------

void Refresh() {
    CheckPhrases();

    // Every viewer gets the text in their own language: it is built once per refresh
    // for each (language, team) pair in use.
    int langCount = 0;
    char overflow[MAX_HINT_BYTES + 1];

    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client)) {
            continue;
        }

        int team = GetClientTeam(client);
        if (team != CS_TEAM_T && team != CS_TEAM_CT) {
            continue;
        }
        int teamSlot = (team == CS_TEAM_T) ? 0 : 1;

        int lang = GetClientLanguage(client);
        int slot = -1;
        for (int i = 0; i < langCount; i++) {
            if (g_iCacheLang[i] == lang) {
                slot = i;
                break;
            }
        }
        if (slot == -1 && langCount < MAX_CACHED_LANGS) {
            slot = langCount++;
            g_iCacheLang[slot] = lang;
            g_bCacheBuilt[slot][0] = false;
            g_bCacheBuilt[slot][1] = false;
        }

        bool sent;
        if (slot == -1) {
            // More languages than cache slots: build for this viewer alone.
            BuildTeamText(team, client, overflow, sizeof(overflow));
            sent = SendKeyHint(client, overflow, false);
        } else {
            if (!g_bCacheBuilt[slot][teamSlot]) {
                BuildTeamText(team, client, g_TextCache[slot][teamSlot], MAX_HINT_BYTES + 1);
                g_bCacheBuilt[slot][teamSlot] = true;
            }
            sent = SendKeyHint(client, g_TextCache[slot][teamSlot], false);
        }
        if (sent) {
            g_bShownTo[client] = true;
        }
    }
}

// A missing phrase must not throw inside the refresh timer: check before every refresh
// and fall back to text without the phrase.
void CheckPhrases() {
    g_bHasPhraseDead = TranslationPhraseExists("Dead");
    g_bHasPhraseMore = TranslationPhraseExists("More players");
    if ((!g_bHasPhraseDead || !g_bHasPhraseMore) && !g_bLoggedNoPhrase) {
        g_bLoggedNoPhrase = true;
        LogError("Phrases \"Dead\" / \"More players\" not found: install translations/teammoney.phrases.txt");
    }
}

// viewer - the client whose language the text is built in.
void BuildTeamText(int team, int viewer, char[] buffer, int maxlen) {
    buffer[0] = '\0';

    int players[MAXPLAYERS];
    int count = 0;
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && GetClientTeam(client) == team) {
            g_iMoney[client] = GetEntProp(client, Prop_Send, "m_iAccount");
            players[count++] = client;
        }
    }
    SortCustom1D(players, count, Sort_ByMoneyDesc);

    int limit = maxlen - 1;
    if (limit > MAX_HINT_BYTES) {
        limit = MAX_HINT_BYTES;
    }

    int used = 0;
    char line[256];
    for (int i = 0; i < count; i++) {
        BuildPlayerLine(players[i], viewer, line, sizeof(line));
        int len = strlen(line);

        // The last player needs no reserve for the "+N" line.
        int reserve = (i == count - 1) ? 0 : MORE_LINE_RESERVE;
        if (used + len + reserve > limit) {
            // Larger than the reserve so that a long translation is not cut mid-character;
            // if it does not fit the message, the line is skipped.
            char more[64];
            if (g_bHasPhraseMore) {
                Format(more, sizeof(more), "%T\n", "More players", viewer, count - i);
            } else {
                Format(more, sizeof(more), "+%d\n", count - i);
            }
            if (used + strlen(more) <= limit) {
                StrCat(buffer, maxlen, more);
            }
            LogDebug("team %d: %d of %d players did not fit (%d bytes used)", team, count - i, count, used);
            return;
        }

        StrCat(buffer, maxlen, line);
        used += len;
    }
}

void BuildPlayerLine(int client, int viewer, char[] line, int maxlen) {
    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    ReplaceString(name, sizeof(name), "\n", " ");
    TruncateUtf8(name, g_cvNameLength.IntValue);

    if (!IsPlayerAlive(client)) {
        if (g_bHasPhraseDead) {
            Format(line, maxlen, "%s — $%d (%T)\n", name, g_iMoney[client], "Dead", viewer);
        } else {
            Format(line, maxlen, "%s — $%d\n", name, g_iMoney[client]);
        }
        return;
    }

    char nades[8];
    GetPlayerNades(client, nades, sizeof(nades));
    if (nades[0] != '\0') {
        Format(line, maxlen, "%s — $%d [%s]\n", name, g_iMoney[client], nades);
    } else {
        Format(line, maxlen, "%s — $%d\n", name, g_iMoney[client]);
    }
}

public int Sort_ByMoneyDesc(int elem1, int elem2, const int[] array, Handle hndl) {
    if (g_iMoney[elem1] > g_iMoney[elem2]) {
        return -1;
    }
    if (g_iMoney[elem1] < g_iMoney[elem2]) {
        return 1;
    }
    return elem1 - elem2;
}

// Grenades from the player's weapons: 'F' per flashbang, 'H' for HE, 'S' for smoke, then the
// defuse kit as 'D' after a '|' separator. Examples: "FFHS", "FFHS|D", "D".
void GetPlayerNades(int client, char[] buffer, int maxlen) {
    int flashes = 0;
    bool he = false, smoke = false;

    int size = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    char classname[32];
    for (int i = 0; i < size; i++) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (weapon == -1 || !GetEntityClassname(weapon, classname, sizeof(classname))) {
            continue;
        }

        if (StrEqual(classname, "weapon_flashbang")) {
            flashes = GetGrenadeAmmo(client, weapon, AMMO_FLASHBANG_FALLBACK);
        } else if (StrEqual(classname, "weapon_hegrenade")) {
            he = GetGrenadeAmmo(client, weapon, AMMO_HEGRENADE_FALLBACK) > 0;
        } else if (StrEqual(classname, "weapon_smokegrenade")) {
            smoke = GetGrenadeAmmo(client, weapon, AMMO_SMOKE_FALLBACK) > 0;
        }
    }

    int pos = 0;
    for (int i = 0; i < flashes && pos < maxlen - 1; i++) {
        buffer[pos++] = 'F';
    }
    if (he && pos < maxlen - 1) {
        buffer[pos++] = 'H';
    }
    if (smoke && pos < maxlen - 1) {
        buffer[pos++] = 'S';
    }
    // The separator and the letter go together or not at all.
    if (g_bHasDefuserProp && GetEntProp(client, Prop_Send, "m_bHasDefuser") != 0) {
        int need = (pos > 0) ? 2 : 1;
        if (pos + need <= maxlen - 1) {
            if (pos > 0) {
                buffer[pos++] = '|';
            }
            buffer[pos++] = 'D';
        }
    }
    buffer[pos] = '\0';
}

int GetGrenadeAmmo(int client, int weapon, int fallbackType) {
    // CSS-VERIFY: m_iPrimaryAmmoType of grenades in CS:S matches 11/12/13 (HE/flashbang/smoke).
    int type = g_bHasAmmoTypeProp ? GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType") : -1;
    if (type < 0) {
        type = fallbackType;
    }
    return GetEntProp(client, Prop_Send, "m_iAmmo", _, type);
}

// Truncates the string to maxChars characters without splitting multibyte UTF-8 characters.
void TruncateUtf8(char[] str, int maxChars) {
    int chars = 0;
    for (int i = 0; str[i] != '\0'; i++) {
        if ((str[i] & 0xC0) != 0x80) {  // start of a character, not a continuation byte
            if (chars == maxChars) {
                str[i] = '\0';
                return;
            }
            chars++;
        }
    }
}

bool SendKeyHint(int client, const char[] text, bool reliable) {
    Handle msg = StartMessageOne("KeyHintText", client, reliable ? USERMSG_RELIABLE : 0);
    if (msg == null) {
        // Once per display: this runs for every viewer on every refresh.
        if (!g_bLoggedSendError) {
            g_bLoggedSendError = true;
            LogError("Failed to start KeyHintText message for client %d", client);
        }
        return false;
    }

    BfWrite bf = UserMessageToBfWrite(msg);
    bf.WriteByte(1);
    bf.WriteString(text);
    EndMessage();
    return true;
}

void LogDebug(const char[] format, any ...) {
    if (!g_cvDebug.BoolValue) {
        return;
    }
    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 2);
    LogToFileEx(g_DebugLogPath, "%s", buffer);
}
