/*
 * practice.sp — основа тренировки: выдача и бесконечные гранаты, урон,
 * команды игрока (!noclip, !back, !last, !noflash) и главное меню.
 */

void Practice_Init() {
    RegConsoleCmd("sm_nadepractice", Command_Menu, "Меню тренировки гранат");
    RegConsoleCmd("sm_practice", Command_Menu, "Меню тренировки гранат");
    RegConsoleCmd("sm_back", Command_Back, "Вернуться в позицию последнего броска");
    RegConsoleCmd("sm_last", Command_Last, "Повторить последний бросок");
    RegConsoleCmd("sm_noflash", Command_NoFlash, "Не слепнуть от флешек (вкл/выкл)");

    // sm_noclip может быть занят админской командой funcommands. Слушатель команды
    // срабатывает раньше обработчиков, поэтому в активном режиме !noclip — наш,
    // а вне режима команда достаётся funcommands.
    // CSS-VERIFY: при загруженном funcommands.smx !noclip в режиме переключает наш noclip один раз.
    RegConsoleCmd("sm_noclip", Command_NoclipFallback, "Noclip в режиме тренировки");
    AddCommandListener(Listener_Noclip, "sm_noclip");

    HookEvent("player_blind", Event_PlayerBlind, EventHookMode_Post);
}

// Режим остановлен: вернуть игрокам то, что режим у них изменил.
void Practice_Stop() {
    for (int client = 1; client <= MaxClients; client++) {
        if (g_bNoclip[client] && IsClientInGame(client)) {
            SetEntityMoveType(client, MOVETYPE_WALK);
        }
        g_bNoclip[client] = false;
    }
}

// Выдача при появлении: все три гранаты и деньги.
void Practice_Equip(int client) {
    if (!IsPlayerAlive(client) || GetClientTeam(client) < CS_TEAM_T) {
        return;
    }
    g_bNoclip[client] = false;

    if (HasEntProp(client, Prop_Send, "m_iAccount")) {
        SetEntProp(client, Prop_Send, "m_iAccount", 16000);
    }
    if (!g_cvGiveOnSpawn.BoolValue) {
        return;
    }
    for (int nade = 0; nade < NADE_COUNT; nade++) {
        if (FindWeaponByClass(client, g_NadeWeapon[nade]) == -1) {
            GivePlayerItem(client, g_NadeWeapon[nade]);
        }
    }
}

// ---------------------------------------------------------------------------
// Бесконечные гранаты
// ---------------------------------------------------------------------------

// Вызывается на кадр позже появления снаряда.
void Practice_OnThrow(int client, int nade) {
    if (!g_cvInfinite.BoolValue) {
        return;
    }

    // Способ 1: вернуть патрон, пока игра не убрала гранату из рук, — тогда она
    // просто достаётся снова.
    // CSS-VERIFY: после броска с восстановленным запасом игрок остаётся с той же гранатой в руках.
    int weapon = FindWeaponByClass(client, g_NadeWeapon[nade]);
    if (weapon != -1 && HasEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType")) {
        int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
        if (ammoType >= 0 && ammoType < GetEntPropArraySize(client, Prop_Send, "m_iAmmo")
            && GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType) < 1) {
            SetEntProp(client, Prop_Send, "m_iAmmo", 1, _, ammoType);
        }
    }

    // Способ 2 (подстраховка): если граната всё же пропала — выдать новую.
    DataPack pack;
    CreateDataTimer(1.2, Timer_Refill, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(nade);
}

public Action Timer_Refill(Handle timer, DataPack pack) {
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int nade = pack.ReadCell();
    if (client == 0 || !g_bActive || !IsHuman(client) || !IsPlayerAlive(client)) {
        return Plugin_Stop;
    }
    if (FindWeaponByClass(client, g_NadeWeapon[nade]) == -1) {
        GivePlayerItem(client, g_NadeWeapon[nade]);
        LogDebug("refill: %N got %s by timer (ammo restore did not keep the weapon)", client, g_NadeWeapon[nade]);
        if (GetActiveNade(client) == NADE_NONE) {
            FakeClientCommand(client, "use %s", g_NadeWeapon[nade]);
        }
    }
    return Plugin_Stop;
}

// ---------------------------------------------------------------------------
// Урон и ослепление
// ---------------------------------------------------------------------------

public Action Practice_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
    if (!g_bActive) {
        return Plugin_Continue;
    }
    if (g_cvBlockDamage.BoolValue) {
        return Plugin_Handled;
    }
    if (g_cvBlockSelfNade.BoolValue && attacker == victim
        && inflictor > MaxClients && inflictor <= MAX_EDICTS && g_bProjectileEnt[inflictor]) {
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public void Event_PlayerBlind(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client == 0 || !g_bNoFlash[client] || !IsClientInGame(client)) {
        return;
    }
    // CSS-VERIFY: обнуление этих свойств в player_blind убирает ослепление.
    if (HasEntProp(client, Prop_Send, "m_flFlashMaxAlpha") && HasEntProp(client, Prop_Send, "m_flFlashDuration")) {
        SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
        SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 0.0);
    } else {
        LogMissingProp("m_flFlashMaxAlpha/m_flFlashDuration");
    }
}

// ---------------------------------------------------------------------------
// Команды
// ---------------------------------------------------------------------------

void Practice_ToggleNoclip(int client) {
    if (!CanPractice(client)) {
        return;
    }
    g_bNoclip[client] = !g_bNoclip[client];
    SetEntityMoveType(client, g_bNoclip[client] ? MOVETYPE_NOCLIP : MOVETYPE_WALK);
    NP_Print(client, "%t", g_bNoclip[client] ? "Noclip On" : "Noclip Off");
}

public Action Listener_Noclip(int client, const char[] command, int argc) {
    if (!g_bActive || !IsHuman(client)) {
        return Plugin_Continue;
    }
    Practice_ToggleNoclip(client);
    return Plugin_Stop;
}

// До этого обработчика дело доходит, только когда режим не активен.
public Action Command_NoclipFallback(int client, int args) {
    return Plugin_Continue;
}

void Practice_Back(int client) {
    if (!CanPractice(client)) {
        return;
    }
    if (!g_LastThrow[client].valid) {
        NP_Print(client, "%t", "No Last Throw");
        return;
    }
    float origin[3], angles[3];
    origin = g_LastThrow[client].origin;
    angles = g_LastThrow[client].angles;
    angles[2] = 0.0;
    TeleportEntity(client, origin, angles, view_as<float>({ 0.0, 0.0, 0.0 }));
    char throwName[48];
    ThrowName(client, g_LastThrow[client].throwType, throwName, sizeof(throwName));
    NP_Print(client, "%t", "Returned Back", throwName);
}

void Practice_Last(int client) {
    if (!CanPractice(client)) {
        return;
    }
    if (!g_LastThrow[client].valid) {
        NP_Print(client, "%t", "No Last Throw");
        return;
    }
    float pos[3], vel[3];
    float path[MAX_PATH_POINTS * 3];
    pos = g_LastThrow[client].projOrigin;
    vel = g_LastThrow[client].projVelocity;
    path = g_LastThrow[client].path;
    Replay_Request(client, g_LastThrow[client].nade, pos, vel, g_LastThrow[client].hasProj,
        path, g_LastThrow[client].pathCount);
}

public Action Command_Back(int client, int args) {
    Practice_Back(client);
    return Plugin_Handled;
}

public Action Command_Last(int client, int args) {
    Practice_Last(client);
    return Plugin_Handled;
}

public Action Command_NoFlash(int client, int args) {
    if (IsHuman(client)) {
        g_bNoFlash[client] = !g_bNoFlash[client];
        Practice_TellOption(client, "Menu Noflash", g_bNoFlash[client]);
    }
    return Plugin_Handled;
}

void Practice_TellOption(int client, const char[] phrase, bool value) {
    NP_Print(client, "%t: %t", phrase, value ? "On" : "Off");
}

// ---------------------------------------------------------------------------
// Главное меню
// ---------------------------------------------------------------------------

public Action Command_Menu(int client, int args) {
    if (!IsHuman(client)) {
        ReplyToCommand(client, "[NadePractice] In-game only.");
        return Plugin_Handled;
    }
    if (!g_bActive) {
        NP_Print(client, "%t", "Mode Inactive");
        return Plugin_Handled;
    }
    Practice_ShowMenu(client);
    return Plugin_Handled;
}

void Menu_AddPhrase(Menu menu, int client, const char[] info, const char[] phrase) {
    char text[96];
    FormatEx(text, sizeof(text), "%T", phrase, client);
    menu.AddItem(info, text);
}

void Menu_AddToggle(Menu menu, int client, const char[] info, const char[] phrase, bool value) {
    char text[96];
    FormatEx(text, sizeof(text), "%T: %T", phrase, client, value ? "On" : "Off", client);
    menu.AddItem(info, text);
}

void Practice_ShowMenu(int client, int firstItem = 0) {
    Menu menu = new Menu(MenuHandler_Practice);
    menu.SetTitle("%T", "Menu Title", client);

    Menu_AddPhrase(menu, client, "lineups", "Menu Lineups");
    Menu_AddPhrase(menu, client, "last", "Menu Last");
    Menu_AddPhrase(menu, client, "back", "Menu Back");
    Menu_AddToggle(menu, client, "noclip", "Menu Noclip", g_bNoclip[client]);
    Menu_AddPhrase(menu, client, "clear", "Menu Clear");
    Menu_AddToggle(menu, client, "tracer", "Menu Tracer", g_bTracer[client]);
    Menu_AddToggle(menu, client, "preview", "Menu Preview", g_bPreview[client]);
    Menu_AddToggle(menu, client, "hints", "Menu Hints", g_bHints[client]);
    Menu_AddToggle(menu, client, "noflash", "Menu Noflash", g_bNoFlash[client]);
    Menu_AddPhrase(menu, client, "preverror", "Menu PrevError");
    Menu_AddPhrase(menu, client, "help", "Menu Help");

    menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int MenuHandler_Practice(Menu menu, MenuAction action, int client, int item) {
    if (action == MenuAction_End) {
        delete menu;
        return 0;
    }
    if (action != MenuAction_Select || !g_bActive) {
        return 0;
    }

    char info[16];
    menu.GetItem(item, info, sizeof(info));
    bool reopen = true;

    if (StrEqual(info, "lineups")) {
        Lineups_ShowMainMenu(client);
        reopen = false;
    } else if (StrEqual(info, "last")) {
        Practice_Last(client);
    } else if (StrEqual(info, "back")) {
        Practice_Back(client);
    } else if (StrEqual(info, "noclip")) {
        Practice_ToggleNoclip(client);
    } else if (StrEqual(info, "clear")) {
        Tracer_ClearClient(client);
        NP_Print(client, "%t", "Traces Cleared");
    } else if (StrEqual(info, "tracer")) {
        g_bTracer[client] = !g_bTracer[client];
    } else if (StrEqual(info, "preview")) {
        g_bPreview[client] = !g_bPreview[client];
    } else if (StrEqual(info, "hints")) {
        Hints_Toggle(client);
    } else if (StrEqual(info, "noflash")) {
        g_bNoFlash[client] = !g_bNoFlash[client];
    } else if (StrEqual(info, "preverror")) {
        Preview_TellStats(client);
    } else if (StrEqual(info, "help")) {
        NP_Print(client, "%t", "Help Line 1");
        NP_Print(client, "%t", "Help Line 2");
        NP_Print(client, "%t", "Help Line 3");
    }

    if (reopen) {
        Practice_ShowMenu(client, menu.Selection);
    }
    return 0;
}
