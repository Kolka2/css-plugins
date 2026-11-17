/*
 * spawns.sp - map spawn points (stage 13.1): !spawn, !bestspawn, !worstspawn and a menu.
 * Together with the timer (timer.sp) they check timings: whether a player from the best
 * spawn of one side peeks earlier than a player from the best spawn of the other side.
 *
 * Commands follow ".spawn", ".bestspawn", ".worstspawn" of splewis/csgo-practice-mode
 * (GPL-3.0); the code is written anew for CS:S. CS:S spawn points have no priority and
 * cannot be disabled as in CS:GO, so all of them are used.
 */

#define SPAWN_T  0
#define SPAWN_CT 1

char g_SpawnClass[2][] = { "info_player_terrorist", "info_player_counterterrorist" };
char g_SpawnTeamName[2][] = { "T", "CT" };

ArrayList g_Spawns[2];      // each entry: x, y, z, pitch, yaw

void Spawns_Init() {
    RegConsoleCmd("sm_spawn", Command_Spawn, "!spawn [t|ct] [N] - teleport to the nearest spawn (or spawn N) of your team or the given one");
    RegConsoleCmd("sm_bestspawn", Command_BestSpawn, "!bestspawn [t|ct] - teleport to the spawn nearest to you");
    RegConsoleCmd("sm_worstspawn", Command_WorstSpawn, "!worstspawn [t|ct] - teleport to the spawn farthest from you");
    g_Spawns[SPAWN_T] = new ArrayList(5);
    g_Spawns[SPAWN_CT] = new ArrayList(5);
}

// Collects the spawn points in the order the game iterates them (by entity index), so a
// number stays the same after a map restart.
// CSS-VERIFY: this order matches the order the game hands out spawns at round start.
void Spawns_Load() {
    float origin[3], angles[3], entry[5];
    for (int side = 0; side < 2; side++) {
        g_Spawns[side].Clear();
        int entity = -1;
        int guard = 0;
        while ((entity = FindEntityByClassname(entity, g_SpawnClass[side])) != -1 && guard++ < 256) {
            GetEntPropVector(entity, Prop_Data, "m_vecOrigin", origin);
            GetEntPropVector(entity, Prop_Data, "m_angRotation", angles);
            entry[0] = origin[0];
            entry[1] = origin[1];
            entry[2] = origin[2];
            entry[3] = angles[0];
            entry[4] = angles[1];
            g_Spawns[side].PushArray(entry);
        }
    }
    LogDebug("spawns: %d T, %d CT", g_Spawns[SPAWN_T].Length, g_Spawns[SPAWN_CT].Length);
}

// Team side from the command arguments ("t" / "ct") or the player's team. -1 if none.
int Spawns_SideFromArgs(int client, int args, int &number) {
    int side = -1;
    number = 0;
    char arg[16];
    for (int i = 1; i <= args; i++) {
        GetCmdArg(i, arg, sizeof(arg));
        if (StrEqual(arg, "t", false)) {
            side = SPAWN_T;
        } else if (StrEqual(arg, "ct", false)) {
            side = SPAWN_CT;
        } else if (StringToInt(arg) > 0) {
            number = StringToInt(arg);
        }
    }
    if (side == -1) {
        int team = GetClientTeam(client);
        side = (team == CS_TEAM_T) ? SPAWN_T : ((team == CS_TEAM_CT) ? SPAWN_CT : -1);
    }
    return side;
}

// Index of the spawn nearest to (farthest from) the player, by straight distance.
int Spawns_Find(int client, int side, bool farthest) {
    float origin[3], spot[3], entry[5];
    GetClientAbsOrigin(client, origin);
    int best = -1;
    float bestDist = 0.0;
    for (int i = 0; i < g_Spawns[side].Length; i++) {
        g_Spawns[side].GetArray(i, entry);
        spot[0] = entry[0];
        spot[1] = entry[1];
        spot[2] = entry[2];
        float dist = GetVectorDistance(origin, spot);
        if (best == -1 || (farthest ? dist > bestDist : dist < bestDist)) {
            best = i;
            bestDist = dist;
        }
    }
    return best;
}

void Spawns_Teleport(int client, int side, int index) {
    float entry[5], pos[3], angles[3];
    g_Spawns[side].GetArray(index, entry);
    pos[0] = entry[0];
    pos[1] = entry[1];
    pos[2] = entry[2];
    angles[0] = entry[3];
    angles[1] = entry[4];
    angles[2] = 0.0;
    float from[3];
    GetClientAbsOrigin(client, from);
    // A timer waiting for the first step keeps waiting: "!timer" then "!spawn" is the main scenario.
    Timer_OnPluginTeleport(client, "spawn");
    TeleportEntity(client, pos, angles, view_as<float>({ 0.0, 0.0, 0.0 }));
    Movement_Clear(client);
    LogDebug("spawn: %N to %s #%d of %d, %.0f u from (%.1f %.1f %.1f)", client, g_SpawnTeamName[side], index + 1,
        g_Spawns[side].Length, GetVectorDistance(from, pos), from[0], from[1], from[2]);
    NP_Print(client, "%t", "Spawn Teleported", g_SpawnTeamName[side], index + 1, g_Spawns[side].Length);
}

// mode: 0 = nearest or number, 1 = best (nearest), 2 = worst (farthest)
void Spawns_Command(int client, int args, int mode) {
    if (!CanPractice(client)) {
        return;
    }
    int number;
    int side = Spawns_SideFromArgs(client, args, number);
    if (side == -1) {
        NP_Print(client, "%t", "Spawn Need Team");
        return;
    }
    if (g_Spawns[side].Length == 0) {
        NP_Print(client, "%t", "Spawn None", g_SpawnTeamName[side]);
        return;
    }
    int index;
    if (mode == 0 && number > 0) {
        if (number > g_Spawns[side].Length) {
            NP_Print(client, "%t", "Spawn Bad Number", g_SpawnTeamName[side], g_Spawns[side].Length);
            return;
        }
        index = number - 1;
    } else {
        index = Spawns_Find(client, side, mode == 2);
    }
    Spawns_Teleport(client, side, index);
}

public Action Command_Spawn(int client, int args) {
    Spawns_Command(client, args, 0);
    return Plugin_Handled;
}

public Action Command_BestSpawn(int client, int args) {
    Spawns_Command(client, args, 1);
    return Plugin_Handled;
}

public Action Command_WorstSpawn(int client, int args) {
    Spawns_Command(client, args, 2);
    return Plugin_Handled;
}

// Menu: spawns of the player's side first, then the other side, with numbers and distance.
void Spawns_ShowMenu(int client) {
    Menu menu = new Menu(MenuHandler_Spawns);
    menu.SetTitle("%T", "Spawn Menu Title", client);
    menu.ExitBackButton = true;
    int first = (GetClientTeam(client) == CS_TEAM_CT) ? SPAWN_CT : SPAWN_T;
    float origin[3], spot[3], entry[5];
    GetClientAbsOrigin(client, origin);
    char info[16], text[64];
    for (int k = 0; k < 2; k++) {
        int side = (k == 0) ? first : 1 - first;
        for (int i = 0; i < g_Spawns[side].Length; i++) {
            g_Spawns[side].GetArray(i, entry);
            spot[0] = entry[0];
            spot[1] = entry[1];
            spot[2] = entry[2];
            FormatEx(info, sizeof(info), "%d:%d", side, i);
            FormatEx(text, sizeof(text), "%s #%d (%d u)", g_SpawnTeamName[side], i + 1, RoundToNearest(GetVectorDistance(origin, spot)));
            menu.AddItem(info, text);
        }
    }
    if (menu.ItemCount == 0) {
        Menu_AddPhrase(menu, client, "none", "Spawn Menu Empty");
    }
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Spawns(Menu menu, MenuAction action, int client, int item) {
    if (action == MenuAction_End) {
        delete menu;
        return 0;
    }
    if (!g_bActive) {
        return 0;
    }
    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack) {
        Practice_ShowMenu(client, g_PracticeMenuPos[client]);
        return 0;
    }
    if (action != MenuAction_Select) {
        return 0;
    }
    char info[16], parts[2][8];
    menu.GetItem(item, info, sizeof(info));
    if (ExplodeString(info, ":", parts, 2, sizeof(parts[])) == 2 && CanPractice(client)) {
        int side = StringToInt(parts[0]);
        int index = StringToInt(parts[1]);
        if (side >= 0 && side < 2 && index >= 0 && index < g_Spawns[side].Length) {
            Spawns_Teleport(client, side, index);
        }
    }
    Spawns_ShowMenu(client);
    return 0;
}
