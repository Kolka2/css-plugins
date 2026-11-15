/*
 * teammoney — деньги и гранаты команды в KeyHintText во время фризтайма.
 *
 * Слой:        утилита
 * Владеет:     своим HUD-сообщением (KeyHintText) во время фризтайма и N секунд после него
 * Читает:      деньги (m_iAccount), оружие и патроны игроков, события раунда
 * Использует:  ничего
 *
 * Основано на sm_team_money 1.0.3. Отличия от 1.0.3:
 *  - один таймер обновления и один таймер остановки, старые отменяются при новом раунде;
 *    конец показа считается от round_freeze_end, а не от mp_freezetime;
 *  - сообщение укладывается в лимит user message по байтам, лишние игроки сворачиваются в «+N»;
 *  - ники обрезаются по границе UTF-8 символа;
 *  - гранаты считаются по оружию игрока и его типу патронов, а не по захардкоженным индексам;
 *  - у неживых игроков показываются только деньги;
 *  - игроки команды отсортированы по деньгам;
 *  - обновления уходят ненадёжным сообщением, скрытие — надёжным.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <cstrike>

#define PLUGIN_VERSION "2.0.0"

// Данные user message в Source ограничены ~255 байтами; KeyHintText добавляет байт
// количества строк и завершающий ноль. Берём с запасом.
#define MAX_HINT_BYTES 240
// Сколько байт держать в запасе под строку «+N».
#define MORE_LINE_RESERVE 24

// Запасные индексы m_iAmmo для CS:S, если тип патронов у оружия прочитать не удалось.
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

Handle g_hRefreshTimer;
Handle g_hStopTimer;
bool g_bActive;

// Кому HUD показан в текущем показе (чтобы скрыть только у них).
bool g_bShownTo[MAXPLAYERS + 1];
// Деньги на момент построения сообщения (для сортировки).
int g_iMoney[MAXPLAYERS + 1];

char g_DebugLogPath[PLATFORM_MAX_PATH];

// Есть ли у оружия свойство m_iPrimaryAmmoType (иначе — запасные индексы).
bool g_bHasAmmoTypeProp;

// ---------------------------------------------------------------------------
// Загрузка
// ---------------------------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    if (GetEngineVersion() != Engine_CSS) {
        strcopy(error, err_max, "This plugin supports Counter-Strike: Source only.");
        return APLRes_Failure;
    }
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

    CreateConVar("sm_teammoney_version", PLUGIN_VERSION, "Версия плагина", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvEnabled    = CreateConVar("sm_teammoney_enabled", "1", "Показывать деньги и гранаты команды во время фризтайма", _, true, 0.0, true, 1.0);
    g_cvDebug      = CreateConVar("sm_teammoney_debug", "0", "Подробный лог в logs/teammoney_debug.log", _, true, 0.0, true, 1.0);
    g_cvExtraTime  = CreateConVar("sm_teammoney_extra_time", "5.0", "Сколько секунд показывать после конца фризтайма", _, true, 0.0, true, 30.0);
    g_cvInterval   = CreateConVar("sm_teammoney_interval", "0.25", "Как часто обновлять (секунды)", _, true, 0.1, true, 2.0);
    g_cvNameLength = CreateConVar("sm_teammoney_name_length", "12", "Максимум символов ника", _, true, 4.0, true, 32.0);
    AutoExecConfig(true, "teammoney");

    g_cvEnabled.AddChangeHook(OnEnabledChanged);

    BuildPath(Path_SM, g_DebugLogPath, sizeof(g_DebugLogPath), "logs/teammoney_debug.log");

    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_freeze_end", Event_RoundFreezeEnd, EventHookMode_PostNoCopy);
}

public void OnMapEnd() {
    StopDisplay(false);
}

public void OnPluginEnd() {
    StopDisplay(true);
}

public void OnClientDisconnect(int client) {
    g_bShownTo[client] = false;
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (!convar.BoolValue) {
        StopDisplay(true);
    }
}

// ---------------------------------------------------------------------------
// Жизненный цикл показа
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
        StopDisplay(true);
        return;
    }
    g_hStopTimer = CreateTimer(extra, Timer_Stop);
    LogDebug("freeze end, hiding in %.1f s", extra);
}

void StartDisplay() {
    // Новый раунд отменяет всё, что осталось от предыдущего (в том числе после рестарта).
    StopDisplay(false);

    g_bActive = true;
    g_hRefreshTimer = CreateTimer(g_cvInterval.FloatValue, Timer_Refresh, _, TIMER_REPEAT);
    LogDebug("display started");
    Refresh();
}

// hide = true — стереть HUD у тех, кому он был показан.
void StopDisplay(bool hide) {
    g_bActive = false;
    delete g_hRefreshTimer;
    delete g_hStopTimer;

    for (int client = 1; client <= MaxClients; client++) {
        if (g_bShownTo[client]) {
            if (hide && IsClientInGame(client)) {
                SendKeyHint(client, "", true);
            }
            g_bShownTo[client] = false;
        }
    }
    LogDebug("display stopped (hide=%d)", hide);
}

public Action Timer_Refresh(Handle timer) {
    Refresh();
    return Plugin_Continue;
}

public Action Timer_Stop(Handle timer) {
    g_hStopTimer = null;  // этот таймер завершается сам, StopDisplay не должен удалять его повторно
    StopDisplay(true);
    return Plugin_Stop;
}

// ---------------------------------------------------------------------------
// Построение и отправка
// ---------------------------------------------------------------------------

void Refresh() {
    char textT[MAX_HINT_BYTES + 1], textCT[MAX_HINT_BYTES + 1];
    BuildTeamText(CS_TEAM_T, textT, sizeof(textT));
    BuildTeamText(CS_TEAM_CT, textCT, sizeof(textCT));

    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client)) {
            continue;
        }

        switch (GetClientTeam(client)) {
            case CS_TEAM_T: {
                g_bShownTo[client] = SendKeyHint(client, textT, false) || g_bShownTo[client];
            }
            case CS_TEAM_CT: {
                g_bShownTo[client] = SendKeyHint(client, textCT, false) || g_bShownTo[client];
            }
        }
    }
}

void BuildTeamText(int team, char[] buffer, int maxlen) {
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
        BuildPlayerLine(players[i], line, sizeof(line));
        int len = strlen(line);

        // Для последнего игрока запас под «+N» не нужен.
        int reserve = (i == count - 1) ? 0 : MORE_LINE_RESERVE;
        if (used + len + reserve > limit) {
            char more[MORE_LINE_RESERVE];
            Format(more, sizeof(more), "%T\n", "More players", LANG_SERVER, count - i);
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

void BuildPlayerLine(int client, char[] line, int maxlen) {
    char name[MAX_NAME_LENGTH];
    GetClientName(client, name, sizeof(name));
    ReplaceString(name, sizeof(name), "\n", " ");
    TruncateUtf8(name, g_cvNameLength.IntValue);

    if (!IsPlayerAlive(client)) {
        Format(line, maxlen, "%s — $%d (%T)\n", name, g_iMoney[client], "Dead", LANG_SERVER);
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

// Гранаты по оружию игрока: 'F' на каждую флешку, 'H' — HE, 'S' — дым. Пример: "FFHS".
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
    buffer[pos] = '\0';
}

int GetGrenadeAmmo(int client, int weapon, int fallbackType) {
    // CSS-VERIFY: m_iPrimaryAmmoType у гранат в CS:S совпадает с 11/12/13 (HE/флешка/дым).
    int type = g_bHasAmmoTypeProp ? GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType") : -1;
    if (type < 0) {
        type = fallbackType;
    }
    return GetEntProp(client, Prop_Send, "m_iAmmo", _, type);
}

// Обрезает строку до maxChars символов, не разрывая многобайтовые UTF-8 символы.
void TruncateUtf8(char[] str, int maxChars) {
    int chars = 0;
    for (int i = 0; str[i] != '\0'; i++) {
        if ((str[i] & 0xC0) != 0x80) {  // начало символа, а не байт продолжения
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
        LogError("Failed to start KeyHintText message for client %d", client);
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
