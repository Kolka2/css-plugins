/*
 * lineups.sp - lineup database: one KeyValues file per map, commands and menus.
 *
 * File: addons/sourcemod/configs/nadepractice/lineups/<map>.cfg
 * The format is described in the README. A lineup is made from the player's last throw.
 */

void Lineups_Init() {
    RegConsoleCmd("sm_save", Command_Save, "!save <name> - save the last throw as a lineup");
    RegConsoleCmd("sm_lineups", Command_Lineups, "Lineup menu");
    RegConsoleCmd("sm_goto", Command_Goto, "!goto <name> - teleport to a lineup and select it for hints");
    RegConsoleCmd("sm_show", Command_Show, "!show <name> - replay the lineup throw");
    RegConsoleCmd("sm_delete", Command_Delete, "!delete [name] - delete a lineup (the selected one without a name)");
    RegConsoleCmd("sm_rename", Command_Rename, "!rename <new name> - rename the selected lineup");
    RegConsoleCmd("sm_desc", Command_Desc, "!desc <text> - description of the selected lineup");
}

// ---------------------------------------------------------------------------
// File
// ---------------------------------------------------------------------------

void Lineups_Load() {
    g_Lineups.Clear();
    g_NextLineupId = 1;

    char map[64];
    GetCurrentMap(map, sizeof(map));
    BuildPath(Path_SM, g_LineupsFile, sizeof(g_LineupsFile), "configs/nadepractice/lineups/%s.cfg", map);

    if (!FileExists(g_LineupsFile)) {
        LogDebug("lineups: no file %s", g_LineupsFile);
        return;
    }

    KeyValues kv = new KeyValues("Lineups");
    if (!kv.ImportFromFile(g_LineupsFile)) {
        LogError("[nadepractice] Cannot parse %s", g_LineupsFile);
        delete kv;
        return;
    }

    if (kv.GotoFirstSubKey()) {
        char buffer[64];
        float vec[3];
        do {
            Lineup lineup;
            lineup.id = g_NextLineupId++;
            kv.GetString("name", lineup.name, sizeof(Lineup::name));
            if (lineup.name[0] == '\0') {
                continue;
            }
            kv.GetString("type", buffer, sizeof(buffer));
            lineup.nade = NadeFromKey(buffer);
            if (lineup.nade == NADE_NONE) {
                LogError("[nadepractice] Lineup \"%s\": unknown grenade type \"%s\", skipped", lineup.name, buffer);
                continue;
            }
            kv.GetString("throw", buffer, sizeof(buffer), "stand");
            lineup.throwType = THROW_STAND;
            for (int i = 0; i < THROW_COUNT; i++) {
                if (StrEqual(buffer, g_ThrowKey[i], false)) {
                    lineup.throwType = i;
                }
            }
            kv.GetVector("origin", vec);
            lineup.origin = vec;
            kv.GetVector("angles", vec);
            lineup.angles = vec;
            kv.GetVector("eye", vec);
            lineup.eye = vec;
            lineup.hasProj = kv.GetNum("has_projectile", 0) != 0;
            kv.GetVector("projectile_origin", vec);
            lineup.projOrigin = vec;
            kv.GetVector("projectile_velocity", vec);
            lineup.projVelocity = vec;
            lineup.hasDetonation = kv.GetNum("has_detonation", 0) != 0;
            kv.GetVector("detonation", vec);
            lineup.detonation = vec;
            kv.GetString("author", lineup.author, sizeof(Lineup::author));
            kv.GetString("description", lineup.desc, sizeof(Lineup::desc));

            lineup.pathCount = 0;
            if (kv.JumpToKey("path")) {
                if (kv.GotoFirstSubKey(false)) {
                    do {
                        if (lineup.pathCount >= MAX_PATH_POINTS) {
                            break;
                        }
                        kv.GetVector(NULL_STRING, vec);
                        lineup.path[lineup.pathCount * 3] = vec[0];
                        lineup.path[lineup.pathCount * 3 + 1] = vec[1];
                        lineup.path[lineup.pathCount * 3 + 2] = vec[2];
                        lineup.pathCount++;
                    } while (kv.GotoNextKey(false));
                    kv.GoBack();
                }
                kv.GoBack();
            }

            g_Lineups.PushArray(lineup);
        } while (kv.GotoNextKey());
    }
    delete kv;
    LogDebug("lineups: loaded %d from %s", g_Lineups.Length, g_LineupsFile);
}

bool Lineups_Save() {
    char dir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, dir, sizeof(dir), "configs/nadepractice");
    if (!DirExists(dir)) {
        CreateDirectory(dir, 493);      // 0755
    }
    BuildPath(Path_SM, dir, sizeof(dir), "configs/nadepractice/lineups");
    if (!DirExists(dir)) {
        CreateDirectory(dir, 493);
    }

    KeyValues kv = new KeyValues("Lineups");
    char key[16];
    float vec[3];
    Lineup lineup;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        IntToString(i + 1, key, sizeof(key));
        kv.JumpToKey(key, true);
        kv.SetString("name", lineup.name);
        kv.SetString("type", g_NadeKey[lineup.nade]);
        kv.SetString("throw", g_ThrowKey[lineup.throwType]);
        vec = lineup.origin;
        kv.SetVector("origin", vec);
        vec = lineup.angles;
        kv.SetVector("angles", vec);
        vec = lineup.eye;
        kv.SetVector("eye", vec);
        kv.SetNum("has_projectile", lineup.hasProj);
        vec = lineup.projOrigin;
        kv.SetVector("projectile_origin", vec);
        vec = lineup.projVelocity;
        kv.SetVector("projectile_velocity", vec);
        kv.SetNum("has_detonation", lineup.hasDetonation);
        vec = lineup.detonation;
        kv.SetVector("detonation", vec);
        kv.SetString("author", lineup.author);
        kv.SetString("description", lineup.desc);

        if (lineup.pathCount > 0) {
            kv.JumpToKey("path", true);
            for (int p = 0; p < lineup.pathCount; p++) {
                IntToString(p, key, sizeof(key));
                vec[0] = lineup.path[p * 3];
                vec[1] = lineup.path[p * 3 + 1];
                vec[2] = lineup.path[p * 3 + 2];
                kv.SetVector(key, vec);
            }
            kv.GoBack();
        }
        kv.GoBack();
    }

    kv.Rewind();
    bool ok = kv.ExportToFile(g_LineupsFile);
    delete kv;
    if (!ok) {
        LogError("[nadepractice] Cannot write %s", g_LineupsFile);
    }
    LogDebug("lineups: saved %d to %s (ok=%d)", g_Lineups.Length, g_LineupsFile, ok);
    return ok;
}

// ---------------------------------------------------------------------------
// Lookup and access
// ---------------------------------------------------------------------------

int Lineups_IndexById(int id) {
    if (id <= 0) {
        return -1;
    }
    Lineup lineup;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        if (lineup.id == id) {
            return i;
        }
    }
    return -1;
}

// Exact name match (case-insensitive), otherwise the only partial match.
// Returns the index, -1 (not found) or -2 (several match).
int Lineups_IndexByName(const char[] name) {
    int partial = -1;
    int partialCount = 0;
    Lineup lineup;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        if (StrEqual(lineup.name, name, false)) {
            return i;
        }
        if (StrContains(lineup.name, name, false) != -1) {
            partial = i;
            partialCount++;
        }
    }
    if (partialCount == 1) {
        return partial;
    }
    return (partialCount == 0) ? -1 : -2;
}

// Lineup from the command argument, or the selected one. Tells the player about errors itself.
int Lineups_Resolve(int client, int args) {
    if (args < 1) {
        int index = Lineups_IndexById(g_SelectedLineup[client]);
        if (index == -1) {
            NP_Print(client, "%t", "No Lineup Selected");
        }
        return index;
    }
    char name[64];
    GetCmdArgString(name, sizeof(name));
    StripQuotes(name);
    TrimString(name);
    int index = Lineups_IndexByName(name);
    if (index == -1) {
        NP_Print(client, "%t", "Lineup Not Found", name);
    } else if (index == -2) {
        NP_Print(client, "%t", "Lineup Ambiguous", name);
        index = -1;
    }
    return index;
}

bool Lineups_CanEdit(int client, bool tell = true) {
    // sm_nadepractice_edit_access 1: admins only (generic flag; can be overridden
    // through admin_overrides for "sm_nadepractice_edit").
    if (g_cvEditAccess.IntValue == 0 || CheckCommandAccess(client, "sm_nadepractice_edit", ADMFLAG_GENERIC)) {
        return true;
    }
    if (tell) {
        NP_Print(client, "%t", "No Edit Access");
    }
    return false;
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

void Lineups_Goto(int client, int index) {
    if (!CanPractice(client)) {
        return;
    }
    Lineup lineup;
    g_Lineups.GetArray(index, lineup);

    float origin[3], angles[3];
    origin = lineup.origin;
    angles = lineup.angles;
    angles[2] = 0.0;
    TeleportEntity(client, origin, angles, view_as<float>({ 0.0, 0.0, 0.0 }));

    if (FindWeaponByClass(client, g_NadeWeapon[lineup.nade]) == -1 && !Practice_IsThrowing(client)) {
        GivePlayerItem(client, g_NadeWeapon[lineup.nade]);
    }
    Practice_SwitchToNade(client, lineup.nade, "goto");

    Hints_Select(client, lineup.id);
    char nadeName[48], throwName[48];
    NadeName(client, lineup.nade, nadeName, sizeof(nadeName));
    ThrowName(client, lineup.throwType, throwName, sizeof(throwName));
    NP_Print(client, "%t", "Lineup Goto", lineup.name, nadeName, throwName);
    if (lineup.desc[0] != '\0') {
        NP_Print(client, "%s", lineup.desc);
    }
}

void Lineups_Show(int client, int index) {
    if (!CanPractice(client)) {
        return;
    }
    Lineup lineup;
    g_Lineups.GetArray(index, lineup);

    float pos[3], vel[3];
    float path[MAX_PATH_POINTS * 3];
    pos = lineup.projOrigin;
    vel = lineup.projVelocity;
    path = lineup.path;
    if (Replay_Request(client, lineup.nade, pos, vel, lineup.hasProj, path, lineup.pathCount)) {
        NP_Print(client, "%t", "Lineup Show", lineup.name);
    }
}

void Lineups_Delete(int client, int index) {
    Lineup lineup;
    g_Lineups.GetArray(index, lineup);
    g_Lineups.Erase(index);
    Lineups_Save();

    for (int i = 1; i <= MaxClients; i++) {
        if (g_SelectedLineup[i] == lineup.id) {
            Hints_Deselect(i);
        }
    }
    LogDebug("lineups: %N deleted \"%s\"", client, lineup.name);
    NP_Print(client, "%t", "Lineup Deleted", lineup.name);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

public Action Command_Save(int client, int args) {
    if (!CanPractice(client) || !Lineups_CanEdit(client)) {
        return Plugin_Handled;
    }
    if (args < 1) {
        NP_Print(client, "%t", "Usage Save");
        return Plugin_Handled;
    }
    if (!g_LastThrow[client].valid || !g_LastThrow[client].hasProj) {
        NP_Print(client, "%t", "No Last Throw");
        return Plugin_Handled;
    }
    if (!g_LastThrow[client].hasDetonation) {
        NP_Print(client, "%t", "Wait Detonation");
        return Plugin_Handled;
    }

    char name[64];
    GetCmdArgString(name, sizeof(name));
    StripQuotes(name);
    TrimString(name);
    if (name[0] == '\0') {
        NP_Print(client, "%t", "Usage Save");
        return Plugin_Handled;
    }
    Lineup other;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, other);
        if (StrEqual(other.name, name, false)) {
            NP_Print(client, "%t", "Lineup Exists", name);
            return Plugin_Handled;
        }
    }

    Lineup lineup;
    lineup.id = g_NextLineupId++;
    strcopy(lineup.name, sizeof(Lineup::name), name);
    lineup.nade = g_LastThrow[client].nade;
    lineup.throwType = g_LastThrow[client].throwType;
    lineup.origin = g_LastThrow[client].origin;
    lineup.angles = g_LastThrow[client].angles;
    lineup.eye = g_LastThrow[client].eye;
    lineup.hasProj = true;
    lineup.projOrigin = g_LastThrow[client].projOrigin;
    lineup.projVelocity = g_LastThrow[client].projVelocity;
    lineup.hasDetonation = true;
    lineup.detonation = g_LastThrow[client].detonation;
    lineup.pathCount = g_LastThrow[client].pathCount;
    lineup.path = g_LastThrow[client].path;
    GetClientName(client, lineup.author, sizeof(Lineup::author));
    lineup.desc[0] = '\0';

    g_Lineups.PushArray(lineup);
    Lineups_Save();
    Hints_Select(client, lineup.id);

    LogDebug("lineups: %N saved \"%s\" nade=%s type=%s path=%d", client, name, g_NadeKey[lineup.nade], g_ThrowKey[lineup.throwType], lineup.pathCount);
    char nadeName[48], throwName[48];
    NadeName(client, lineup.nade, nadeName, sizeof(nadeName));
    ThrowName(client, lineup.throwType, throwName, sizeof(throwName));
    NP_Print(client, "%t", "Lineup Saved", name, nadeName, throwName);
    return Plugin_Handled;
}

public Action Command_Lineups(int client, int args) {
    if (CanPractice(client)) {
        // Opened by command: no Back button.
        g_bMenuFromPractice[client] = false;
        Lineups_ShowMainMenu(client);
    }
    return Plugin_Handled;
}

public Action Command_Goto(int client, int args) {
    if (!CanPractice(client)) {
        return Plugin_Handled;
    }
    if (args < 1 && Lineups_IndexById(g_SelectedLineup[client]) == -1) {
        g_bMenuFromPractice[client] = false;
        Lineups_ShowMainMenu(client);
        return Plugin_Handled;
    }
    int index = Lineups_Resolve(client, args);
    if (index != -1) {
        Lineups_Goto(client, index);
    }
    return Plugin_Handled;
}

public Action Command_Show(int client, int args) {
    if (!CanPractice(client)) {
        return Plugin_Handled;
    }
    int index = Lineups_Resolve(client, args);
    if (index != -1) {
        Lineups_Show(client, index);
    }
    return Plugin_Handled;
}

public Action Command_Delete(int client, int args) {
    if (!CanPractice(client) || !Lineups_CanEdit(client)) {
        return Plugin_Handled;
    }
    int index = Lineups_Resolve(client, args);
    if (index != -1) {
        Lineups_Delete(client, index);
    }
    return Plugin_Handled;
}

public Action Command_Rename(int client, int args) {
    if (!CanPractice(client) || !Lineups_CanEdit(client)) {
        return Plugin_Handled;
    }
    if (args < 1) {
        NP_Print(client, "%t", "Usage Rename");
        return Plugin_Handled;
    }
    int index = Lineups_Resolve(client, 0);
    if (index == -1) {
        return Plugin_Handled;
    }

    char name[64];
    GetCmdArgString(name, sizeof(name));
    StripQuotes(name);
    TrimString(name);
    Lineup lineup;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        if (i != index && StrEqual(lineup.name, name, false)) {
            NP_Print(client, "%t", "Lineup Exists", name);
            return Plugin_Handled;
        }
    }
    if (name[0] == '\0') {
        NP_Print(client, "%t", "Usage Rename");
        return Plugin_Handled;
    }

    g_Lineups.GetArray(index, lineup);
    char oldName[64];
    strcopy(oldName, sizeof(oldName), lineup.name);
    strcopy(lineup.name, sizeof(Lineup::name), name);
    g_Lineups.SetArray(index, lineup);
    Lineups_Save();
    NP_Print(client, "%t", "Lineup Renamed", oldName, name);
    return Plugin_Handled;
}

public Action Command_Desc(int client, int args) {
    if (!CanPractice(client) || !Lineups_CanEdit(client)) {
        return Plugin_Handled;
    }
    int index = Lineups_Resolve(client, 0);
    if (index == -1) {
        return Plugin_Handled;
    }
    Lineup lineup;
    g_Lineups.GetArray(index, lineup);
    GetCmdArgString(lineup.desc, sizeof(Lineup::desc));
    StripQuotes(lineup.desc);
    TrimString(lineup.desc);
    g_Lineups.SetArray(index, lineup);
    Lineups_Save();
    NP_Print(client, "%t", "Lineup Desc Set", lineup.name);
    return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// Menus
// ---------------------------------------------------------------------------

int Lineups_CountByNade(int nade) {
    int count = 0;
    Lineup lineup;
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        if (nade == NADE_NONE || lineup.nade == nade) {
            count++;
        }
    }
    return count;
}

// Top lineup menu. Has a Back button to !practice only if it was opened from there
// (g_bMenuFromPractice); the flag is kept while the player moves inside the lineup menus.
void Lineups_ShowMainMenu(int client) {
    Menu menu = new Menu(MenuHandler_LineupsMain);
    menu.SetTitle("%T", "Lineups Title", client, g_Lineups.Length);
    menu.ExitBackButton = g_bMenuFromPractice[client];

    char text[96], info[8];
    FormatEx(text, sizeof(text), "%T (%d)", "Lineups Nearest", client, Lineups_CountByNade(NADE_NONE));
    menu.AddItem("-1", text);
    for (int nade = 0; nade < NADE_COUNT; nade++) {
        IntToString(nade, info, sizeof(info));
        FormatEx(text, sizeof(text), "%T (%d)", g_NadePhrase[nade], client, Lineups_CountByNade(nade));
        menu.AddItem(info, text);
    }
    if (Lineups_IndexById(g_SelectedLineup[client]) != -1) {
        Menu_AddPhrase(menu, client, "deselect", "Lineups Deselect");
    }
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_LineupsMain(Menu menu, MenuAction action, int client, int item) {
    if (action == MenuAction_End) {
        delete menu;
    } else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && g_bActive) {
        LogDebug("menu: %N back from lineups to !practice (item %d)", client, g_PracticeMenuPos[client]);
        Practice_ShowMenu(client, g_PracticeMenuPos[client]);
    } else if (action == MenuAction_Select && g_bActive) {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        if (StrEqual(info, "deselect")) {
            Hints_Deselect(client);
            Lineups_ShowMainMenu(client);
        } else {
            g_MenuFilter[client] = StringToInt(info);
            Lineups_ShowListMenu(client);
        }
    }
    return 0;
}

// Lineup list, nearest to the player first. firstItem: page to open (after Back from a lineup card).
void Lineups_ShowListMenu(int client, int firstItem = 0) {
    int filter = g_MenuFilter[client];
    float origin[3], spot[3];
    GetClientAbsOrigin(client, origin);

    ArrayList order = new ArrayList(2);
    Lineup lineup;
    any entry[2];
    for (int i = 0; i < g_Lineups.Length; i++) {
        g_Lineups.GetArray(i, lineup);
        if (filter != NADE_NONE && lineup.nade != filter) {
            continue;
        }
        spot = lineup.origin;
        entry[0] = GetVectorDistance(origin, spot);
        entry[1] = i;
        order.PushArray(entry);
    }
    if (order.Length == 0) {
        delete order;
        NP_Print(client, "%t", "Lineups Empty");
        Lineups_ShowMainMenu(client);
        return;
    }
    order.Sort(Sort_Ascending, Sort_Float);

    Menu menu = new Menu(MenuHandler_LineupsList);
    menu.SetTitle("%T", "Lineups List Title", client);
    menu.ExitBackButton = true;

    char text[128], info[16];
    for (int i = 0; i < order.Length; i++) {
        order.GetArray(i, entry);
        g_Lineups.GetArray(entry[1], lineup);
        IntToString(lineup.id, info, sizeof(info));
        FormatEx(text, sizeof(text), "%s [%T, %T] %d u", lineup.name, g_NadePhrase[lineup.nade], client,
            g_ThrowPhrase[lineup.throwType], client, RoundToNearest(view_as<float>(entry[0])));
        menu.AddItem(info, text);
    }
    delete order;
    if (firstItem >= menu.ItemCount) {
        firstItem = 0;
    }
    menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int MenuHandler_LineupsList(Menu menu, MenuAction action, int client, int item) {
    if (action == MenuAction_End) {
        delete menu;
    } else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack && g_bActive) {
        Lineups_ShowMainMenu(client);
    } else if (action == MenuAction_Select && g_bActive) {
        char info[16];
        menu.GetItem(item, info, sizeof(info));
        g_MenuLineup[client] = StringToInt(info);
        g_ListMenuPos[client] = menu.Selection;
        Lineups_ShowItemMenu(client);
    }
    return 0;
}

void Lineups_ShowItemMenu(int client) {
    int index = Lineups_IndexById(g_MenuLineup[client]);
    if (index == -1) {
        NP_Print(client, "%t", "Lineup Gone");
        Lineups_ShowMainMenu(client);
        return;
    }
    Lineup lineup;
    g_Lineups.GetArray(index, lineup);

    Menu menu = new Menu(MenuHandler_LineupsItem);
    menu.SetTitle("%s\n%T, %T\n%T: %s\n%s", lineup.name, g_NadePhrase[lineup.nade], client,
        g_ThrowPhrase[lineup.throwType], client, "Lineup Author", client, lineup.author, lineup.desc);
    menu.ExitBackButton = true;

    Menu_AddPhrase(menu, client, "goto", "Lineup Menu Goto");
    Menu_AddPhrase(menu, client, "show", "Lineup Menu Show");
    Menu_AddPhrase(menu, client, "select", "Lineup Menu Select");
    if (Lineups_CanEdit(client, false)) {
        Menu_AddPhrase(menu, client, "delete", "Lineup Menu Delete");
    }
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_LineupsItem(Menu menu, MenuAction action, int client, int item) {
    if (action == MenuAction_End) {
        delete menu;
        return 0;
    }
    if (!g_bActive) {
        return 0;
    }
    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack) {
        Lineups_ShowListMenu(client, g_ListMenuPos[client]);
        return 0;
    }
    if (action != MenuAction_Select) {
        return 0;
    }

    int index = Lineups_IndexById(g_MenuLineup[client]);
    if (index == -1) {
        NP_Print(client, "%t", "Lineup Gone");
        Lineups_ShowMainMenu(client);
        return 0;
    }

    char info[16];
    menu.GetItem(item, info, sizeof(info));
    if (StrEqual(info, "goto")) {
        Lineups_Goto(client, index);
    } else if (StrEqual(info, "show")) {
        Lineups_Show(client, index);
    } else if (StrEqual(info, "select")) {
        Hints_Select(client, g_MenuLineup[client]);
        NP_Print(client, "%t", "Lineup Selected");
    } else if (StrEqual(info, "delete")) {
        if (Lineups_CanEdit(client)) {
            Lineups_Delete(client, index);
        }
        // Back to the same list page (falls back to the top menu if the list is now empty).
        Lineups_ShowListMenu(client, g_ListMenuPos[client]);
        return 0;
    }
    Lineups_ShowItemMenu(client);
    return 0;
}
