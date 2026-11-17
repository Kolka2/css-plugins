/*
 * practice.sp - practice basics: equipment and infinite grenades, damage,
 * player commands (!noclip, !back, !last, !noflash) and the main menu.
 */

void Practice_Init() {
    RegConsoleCmd("sm_nadepractice", Command_Menu, "Grenade practice menu");
    RegConsoleCmd("sm_practice", Command_Menu, "Grenade practice menu");
    RegConsoleCmd("sm_back", Command_Back, "Return to the position of the last throw");
    RegConsoleCmd("sm_last", Command_Last, "Replay the last throw");
    RegConsoleCmd("sm_noflash", Command_NoFlash, "Do not get flashed (toggle)");
    RegConsoleCmd("sm_hands", Command_Hands, "Bring back the first person weapon and hands model");

    // sm_noclip may be taken by the funcommands admin command. A command listener runs
    // before the handlers, so while the mode is active !noclip (without arguments) is ours,
    // and outside the mode, or with a target argument, the command goes to funcommands.
    // Confirmed on the server: in the mode !noclip answers with the NadePractice prefix.
    RegConsoleCmd("sm_noclip", Command_NoclipFallback, "Noclip in the practice mode");
    AddCommandListener(Listener_Noclip, "sm_noclip");
    // The engine console command "noclip" (often bound to a key) goes through the same code
    // while the mode is active, so it works without sv_cheats and !noclip never disagrees with it.
    AddCommandListener(Listener_Noclip, "noclip");

    HookEvent("player_blind", Event_PlayerBlind, EventHookMode_Post);
    HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
    HookEvent("player_team", Event_PlayerTeam, EventHookMode_Post);
    // A player who joined a team mid-round picks a class and stays dead until the round ends,
    // which never happens in this mode.
    AddCommandListener(Listener_JoinClass, "joinclass");
}

// The mode stopped: give players back what the mode changed. Noclip is turned off for
// everyone who has it, no matter whether it came from !noclip or the console command.
void Practice_Stop() {
    for (int client = 1; client <= MaxClients; client++) {
        if (IsClientInGame(client) && IsPlayerAlive(client) && GetEntityMoveType(client) == MOVETYPE_NOCLIP) {
            SetEntityMoveType(client, MOVETYPE_WALK);
            LogDebug("noclip: %N turned off (mode stop)", client);
        }
    }
    Practice_RestoreNoclipCommand();
}

// The "noclip" console command is a cheat command: with sv_cheats 0 the engine may refuse it
// before any plugin sees it. While the mode runs the cheat flag is removed (our listener
// handles the command anyway) and restored when the mode stops.
// CSS-VERIFY: with sv_cheats 0 a bound "noclip" key works in the mode and prints the NadePractice message.
void Practice_AllowNoclipCommand() {
    int flags = GetCommandFlags("noclip");
    if (flags == INVALID_FCVAR_FLAGS) {
        LogDebug("noclip: console command not found");
        return;
    }
    if (g_NoclipCmdFlags == -1) {
        g_NoclipCmdFlags = flags;
    }
    SetCommandFlags("noclip", flags & ~FCVAR_CHEAT);
    LogDebug("noclip: command flags %d -> %d", flags, flags & ~FCVAR_CHEAT);
}

void Practice_RestoreNoclipCommand() {
    if (g_NoclipCmdFlags != -1) {
        SetCommandFlags("noclip", g_NoclipCmdFlags);
        LogDebug("noclip: command flags restored to %d", g_NoclipCmdFlags);
        g_NoclipCmdFlags = -1;
    }
}

bool Practice_HasNoclip(int client) {
    return GetEntityMoveType(client) == MOVETYPE_NOCLIP;
}

// Spawn equipment: all three grenades and money.
void Practice_Equip(int client) {
    if (!IsPlayerAlive(client) || GetClientTeam(client) < CS_TEAM_T) {
        return;
    }

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
// Respawn. The round never ends (mp_ignore_round_win_conditions 1), so without
// this a dead player would only come back by changing teams.
// ---------------------------------------------------------------------------

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (!IsHuman(client)) {
        return;
    }
    char weapon[32];
    event.GetString("weapon", weapon, sizeof(weapon));
    int attacker = GetClientOfUserId(event.GetInt("attacker"));

    GetClientAbsOrigin(client, g_DeathPos[client]);
    GetClientEyeAngles(client, g_DeathAng[client]);
    g_bHasDeathPos[client] = g_cvRespawnAtDeath.BoolValue;

    float delay = g_cvRespawnDelay.FloatValue;
    LogDebug("death: %N, attacker %d, weapon \"%s\", at (%.1f %.1f %.1f), respawn in %.1f s%s", client, attacker, weapon,
        g_DeathPos[client][0], g_DeathPos[client][1], g_DeathPos[client][2], delay,
        (delay > 0.0) ? "" : " (disabled)");
    if (delay > 0.0) {
        CreateTimer(delay, Timer_Respawn, userid, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action Timer_Respawn(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client != 0) {
        Practice_TryRespawn(client, "death");
    }
    return Plugin_Stop;
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive || event.GetBool("disconnect")) {
        return;
    }
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (client == 0) {
        return;
    }
    // A team change cancels a pending return to the death point.
    g_bHasDeathPos[client] = false;
    if (event.GetInt("team") >= CS_TEAM_T) {
        // The event fires before the team actually changes: check in the next frame.
        RequestFrame(Frame_RespawnAfterTeam, userid);
    }
}

public Action Listener_JoinClass(int client, const char[] command, int argc) {
    if (g_bActive && IsHuman(client)) {
        // The class is applied after this command: check in the next frame.
        RequestFrame(Frame_RespawnAfterTeam, GetClientUserId(client));
    }
    return Plugin_Continue;
}

public void Frame_RespawnAfterTeam(int userid) {
    int client = GetClientOfUserId(userid);
    if (client != 0) {
        Practice_TryRespawn(client, "joined team");
    }
}

// Respawns a dead human in T/CT. The usual equipment follows from player_spawn.
// CSS-VERIFY: CS_RespawnPlayer right after player_team (before the class is picked) gives a
// normal player model; if not, the respawn after joinclass is the one that matters.
void Practice_TryRespawn(int client, const char[] reason) {
    if (!g_bActive || g_cvRespawnDelay.FloatValue <= 0.0 || !IsHuman(client)
        || GetClientTeam(client) < CS_TEAM_T || IsPlayerAlive(client)) {
        return;
    }
    CS_RespawnPlayer(client);
    if (!IsPlayerAlive(client)) {
        LogDebug("respawn: %N (%s) failed, still dead", client, reason);
        return;
    }
    Movement_Clear(client);
    if (g_bHasDeathPos[client]) {
        float angles[3];
        angles = g_DeathAng[client];
        angles[2] = 0.0;
        TeleportEntity(client, g_DeathPos[client], angles, view_as<float>({ 0.0, 0.0, 0.0 }));
    }
    LogDebug("respawn: %N (%s)%s", client, reason, g_bHasDeathPos[client] ? ", at the death point" : "");
    g_bHasDeathPos[client] = false;
}

// ---------------------------------------------------------------------------
// Infinite grenades
// ---------------------------------------------------------------------------

// Called one frame after the projectile appeared. At this moment the thrown grenade is
// playing its throw animation (m_bRedraw) with 0 ammo; when the animation ends the game
// either draws it again (ammo > 0) or removes it. Ammo is given back only while the weapon
// still belongs to the player and is not being removed, so the two never race.
void Practice_OnThrow(int client, int nade) {
    if (!g_cvInfinite.BoolValue) {
        return;
    }
    Practice_LogViewModel(client, "throw");

    // Way 1: give the ammo back before the game removes the grenade from the hands,
    // so it is simply drawn again. Confirmed on the server: no "refill" lines in the log.
    int weapon = FindWeaponByClass(client, g_NadeWeapon[nade]);
    if (weapon != -1 && Practice_WeaponKept(client, weapon) && HasEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType")) {
        int ammoType = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
        if (ammoType >= 0 && ammoType < GetEntPropArraySize(client, Prop_Send, "m_iAmmo")
            && GetEntProp(client, Prop_Send, "m_iAmmo", _, ammoType) < 1) {
            SetEntProp(client, Prop_Send, "m_iAmmo", 1, _, ammoType);
        }
    } else {
        LogDebug("refill: %N %s is gone or being removed, waiting for the timer", client, g_NadeWeapon[nade]);
    }

    // Way 2 (fallback): if the grenade is gone anyway, give a new one.
    Practice_StartRefillTimer(client, nade, 1.2, 0);
}

void Practice_StartRefillTimer(int client, int nade, float delay, int attempt) {
    DataPack pack;
    CreateDataTimer(delay, Timer_Refill, pack, TIMER_FLAG_NO_MAPCHANGE);
    pack.WriteCell(GetClientUserId(client));
    pack.WriteCell(nade);
    pack.WriteCell(attempt);
}

public Action Timer_Refill(Handle timer, DataPack pack) {
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    int nade = pack.ReadCell();
    int attempt = pack.ReadCell();
    if (client == 0 || !g_bActive || !IsHuman(client) || !IsPlayerAlive(client)) {
        return Plugin_Stop;
    }
    if (FindWeaponByClass(client, g_NadeWeapon[nade]) != -1) {
        return Plugin_Stop;
    }
    // Do not hand out weapons in the middle of another throw: try again a bit later.
    if (Practice_IsThrowing(client) && attempt < 5) {
        Practice_StartRefillTimer(client, nade, 0.5, attempt + 1);
        return Plugin_Stop;
    }
    GivePlayerItem(client, g_NadeWeapon[nade]);
    LogDebug("refill: %N got %s by timer (ammo restore did not keep the weapon)", client, g_NadeWeapon[nade]);
    if (GetActiveNade(client) == NADE_NONE) {
        FakeClientCommand(client, "use %s", g_NadeWeapon[nade]);
    }
    Practice_LogViewModel(client, "refill");
    return Plugin_Stop;
}

// The weapon still belongs to the player and is not marked for removal.
bool Practice_WeaponKept(int client, int weapon) {
    return GetEntPropEnt(weapon, Prop_Data, "m_hOwnerEntity") == client && !(GetEntityFlags(weapon) & FL_KILLME);
}

// The active weapon is a grenade that is being thrown: pin pulled, throw scheduled or
// the throw animation still playing.
bool Practice_IsThrowing(int client) {
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon) || GetActiveNade(client) == NADE_NONE) {
        return false;
    }
    if (HasEntProp(weapon, Prop_Send, "m_bPinPulled") && GetEntProp(weapon, Prop_Send, "m_bPinPulled")) {
        return true;
    }
    if (HasEntProp(weapon, Prop_Send, "m_fThrowTime") && GetEntPropFloat(weapon, Prop_Send, "m_fThrowTime") > 0.0) {
        return true;
    }
    return HasEntProp(weapon, Prop_Send, "m_bRedraw") && GetEntProp(weapon, Prop_Send, "m_bRedraw") != 0;
}

// Switches to a grenade only when that cannot break a throw: the player holds no grenade,
// or holds another grenade that is idle.
void Practice_SwitchToNade(int client, int nade, const char[] where) {
    int active = GetActiveNade(client);
    Practice_LogViewModel(client, where);
    if (active == nade) {
        return;
    }
    if (active != NADE_NONE && Practice_IsThrowing(client)) {
        LogDebug("%s: %N is throwing a grenade, no weapon switch", where, client);
        return;
    }
    FakeClientCommand(client, "use %s", g_NadeWeapon[nade]);
}

// ---------------------------------------------------------------------------
// Viewmodel (first person weapon and hands). The owner once lost it after dying from
// their own HE and coming back by changing teams; it came back after a reconnect.
// ---------------------------------------------------------------------------

// Debug log: everything that decides whether the first person model is drawn.
void Practice_LogViewModel(int client, const char[] where) {
    if (!g_cvDebug.BoolValue || !IsClientInGame(client)) {
        return;
    }
    char classname[32] = "none";
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    int pin = -1, redraw = -1;
    float throwTime = -1.0;
    if (weapon > MaxClients && IsValidEntity(weapon)) {
        GetEntityClassname(weapon, classname, sizeof(classname));
        if (HasEntProp(weapon, Prop_Send, "m_bPinPulled")) {
            pin = GetEntProp(weapon, Prop_Send, "m_bPinPulled");
            redraw = GetEntProp(weapon, Prop_Send, "m_bRedraw");
            throwTime = GetEntPropFloat(weapon, Prop_Send, "m_fThrowTime");
        }
    }
    int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel", 0);
    int vmEffects = (vm > MaxClients && IsValidEntity(vm)) ? GetEntProp(vm, Prop_Send, "m_fEffects") : -1;
    int draw = HasEntProp(client, Prop_Send, "m_bDrawViewmodel") ? GetEntProp(client, Prop_Send, "m_bDrawViewmodel") : -1;
    int observer = HasEntProp(client, Prop_Send, "m_iObserverMode") ? GetEntProp(client, Prop_Send, "m_iObserverMode") : -1;
    LogDebug("viewmodel [%s]: %N alive=%d team=%d observer=%d weapon=%s(%d) pin=%d throwtime=%.2f redraw=%d vm=%d drawviewmodel=%d vm_effects=%d nodraw=%d",
        where, client, IsPlayerAlive(client), GetClientTeam(client), observer, classname, weapon, pin, throwTime, redraw,
        vm, draw, vmEffects, (vmEffects != -1 && (vmEffects & NP_EF_NODRAW)) ? 1 : 0);
}

// Restores the first person model. force = also when nothing looks broken (!hands).
// Returns true if something was fixed or a redraw was forced.
// CSS-VERIFY: m_bDrawViewmodel = 1, EF_NODRAW removed from the viewmodel and a weapon switch
// there and back bring the hands back in the scenarios from TEST_CHECKLIST (stage 8.3).
bool Practice_FixHands(int client, bool force, const char[] where) {
    if (!IsHuman(client) || !IsPlayerAlive(client)) {
        return false;
    }
    Practice_LogViewModel(client, where);
    bool broken = false;

    if (HasEntProp(client, Prop_Send, "m_bDrawViewmodel") && GetEntProp(client, Prop_Send, "m_bDrawViewmodel") == 0) {
        SetEntProp(client, Prop_Send, "m_bDrawViewmodel", 1);
        broken = true;
    }
    int vm = GetEntPropEnt(client, Prop_Send, "m_hViewModel", 0);
    if (vm > MaxClients && IsValidEntity(vm)) {
        int effects = GetEntProp(vm, Prop_Send, "m_fEffects");
        if (effects & NP_EF_NODRAW) {
            SetEntProp(vm, Prop_Send, "m_fEffects", effects & ~NP_EF_NODRAW);
            broken = true;
        }
    } else {
        broken = true;      // no viewmodel at all: a weapon switch may recreate it
    }

    if (!broken && !force) {
        return false;
    }
    LogDebug("hands [%s]: %N, broken=%d, switching weapons there and back", where, client, broken);

    // Switch to another weapon and back in the next frame: the deploy redraws the viewmodel.
    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    if (weapon <= MaxClients || !IsValidEntity(weapon) || Practice_IsThrowing(client)) {
        return broken;
    }
    char current[32], other[32];
    GetEntityClassname(weapon, current, sizeof(current));
    if (!Practice_FindOtherWeapon(client, current, other, sizeof(other))) {
        return broken;
    }
    FakeClientCommand(client, "use %s", other);
    DataPack pack = new DataPack();
    pack.WriteCell(GetClientUserId(client));
    pack.WriteString(current);
    RequestFrame(Frame_HandsBack, pack);
    return true;
}

// The knife if the player holds something else, otherwise any other weapon.
bool Practice_FindOtherWeapon(int client, const char[] current, char[] other, int maxlen) {
    if (!StrEqual(current, "weapon_knife") && FindWeaponByClass(client, "weapon_knife") != -1) {
        strcopy(other, maxlen, "weapon_knife");
        return true;
    }
    int size = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
    for (int i = 0; i < size; i++) {
        int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
        if (weapon <= MaxClients || !IsValidEntity(weapon)) {
            continue;
        }
        GetEntityClassname(weapon, other, maxlen);
        if (!StrEqual(other, current)) {
            return true;
        }
    }
    return false;
}

public void Frame_HandsBack(DataPack pack) {
    pack.Reset();
    int client = GetClientOfUserId(pack.ReadCell());
    char current[32];
    pack.ReadString(current, sizeof(current));
    delete pack;
    if (client == 0 || !IsHuman(client) || !IsPlayerAlive(client)) {
        return;
    }
    FakeClientCommand(client, "use %s", current);
    Practice_LogViewModel(client, "hands back");
}

// After every spawn: fix the hands if they look broken.
public Action Timer_CheckHands(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client != 0 && g_bActive && Practice_FixHands(client, false, "spawn")) {
        LogDebug("hands: %N fixed after spawn", client);
    }
    return Plugin_Stop;
}

public Action Command_Hands(int client, int args) {
    if (CanPractice(client)) {
        Practice_FixHands(client, true, "!hands");
        NP_Print(client, "%t", "Hands Fixed");
    }
    return Plugin_Handled;
}

// ---------------------------------------------------------------------------
// Damage and blindness
// ---------------------------------------------------------------------------

public Action Practice_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype) {
    if (!g_bActive) {
        return Plugin_Continue;
    }
    // Seen before any blocking: what an HE would have done (stage 12.2).
    Measure_OnDamage(victim, attacker, inflictor, damage);
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
    if (client == 0 || !IsClientInGame(client)) {
        return;
    }
    // The measurement reads the values before !noflash resets them (stage 12.1).
    Measure_OnBlind(client);
    if (!g_bNoFlash[client]) {
        return;
    }
    // CSS-VERIFY: resetting these properties in player_blind removes the blindness.
    if (HasEntProp(client, Prop_Send, "m_flFlashMaxAlpha") && HasEntProp(client, Prop_Send, "m_flFlashDuration")) {
        SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
        SetEntPropFloat(client, Prop_Send, "m_flFlashDuration", 0.0);
    } else {
        LogMissingProp("m_flFlashMaxAlpha/m_flFlashDuration");
    }
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

// Toggles by the real move type, so !noclip, the menu and the console command always agree.
void Practice_ToggleNoclip(int client, const char[] source) {
    if (!CanPractice(client)) {
        return;
    }
    bool enable = !Practice_HasNoclip(client);
    SetEntityMoveType(client, enable ? MOVETYPE_NOCLIP : MOVETYPE_WALK);
    LogDebug("noclip: %N %s (%s)", client, enable ? "on" : "off", source);
    NP_Print(client, "%t", enable ? "Noclip On" : "Noclip Off");
}

public Action Listener_Noclip(int client, const char[] command, int argc) {
    if (!g_bActive || !IsHuman(client)) {
        return Plugin_Continue;
    }
    // "sm_noclip <target>" is the funcommands admin command for another player: leave it alone.
    if (argc > 0 && StrEqual(command, "sm_noclip", false)) {
        return Plugin_Continue;
    }
    Practice_ToggleNoclip(client, command);
    return Plugin_Stop;
}

// This handler is reached only when the mode is not active.
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
    // To the start if there is one, with the throw angles.
    float origin[3], angles[3];
    origin = g_LastThrow[client].hasStart ? g_LastThrow[client].startOrigin : g_LastThrow[client].origin;
    angles = g_LastThrow[client].angles;
    angles[2] = 0.0;
    TeleportEntity(client, origin, angles, view_as<float>({ 0.0, 0.0, 0.0 }));
    Movement_Clear(client);
    char throwName[64];
    ThrowNameEx(client, g_LastThrow[client].throwType, g_LastThrow[client].strength, throwName, sizeof(throwName));
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
// Main menu
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

// Menu item "<name>: <current choice>".
void Menu_AddChoice(Menu menu, int client, const char[] info, const char[] phrase, const char[] choicePhrase) {
    char text[96];
    FormatEx(text, sizeof(text), "%T: %T", phrase, client, choicePhrase, client);
    menu.AddItem(info, text);
}

void Practice_ShowMenu(int client, int firstItem = 0) {
    Menu menu = new Menu(MenuHandler_Practice);
    menu.SetTitle("%T", "Menu Title", client);

    Menu_AddPhrase(menu, client, "lineups", "Menu Lineups");
    Menu_AddPhrase(menu, client, "last", "Menu Last");
    Menu_AddPhrase(menu, client, "back", "Menu Back");
    Menu_AddToggle(menu, client, "noclip", "Menu Noclip", IsPlayerAlive(client) && Practice_HasNoclip(client));
    Menu_AddPhrase(menu, client, "clear", "Menu Clear");
    Menu_AddToggle(menu, client, "tracer", "Menu Tracer", g_bTracer[client]);
    Menu_AddToggle(menu, client, "preview", "Menu Preview", g_bPreview[client]);
    Menu_AddToggle(menu, client, "hints", "Menu Hints", g_bHints[client]);
    Menu_AddChoice(menu, client, "marker", "Menu Marker", g_MarkerPhrase[g_HintMarkerStyle[client]]);
    Menu_AddChoice(menu, client, "target", "Menu Target", g_TargetPhrase[g_HintTarget[client]]);
    Menu_AddPhrase(menu, client, "edit", "Menu Edit");
    Menu_AddPhrase(menu, client, "measure", "Menu Measure");
    Menu_AddToggle(menu, client, "noflash", "Menu Noflash", g_bNoFlash[client]);
    Menu_AddPhrase(menu, client, "hands", "Menu Hands");
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
        // The lineup menu gets a Back button that returns to this page.
        g_PracticeMenuPos[client] = menu.Selection;
        g_bMenuFromPractice[client] = true;
        Lineups_ShowMainMenu(client);
        reopen = false;
    } else if (StrEqual(info, "last")) {
        Practice_Last(client);
    } else if (StrEqual(info, "back")) {
        Practice_Back(client);
    } else if (StrEqual(info, "noclip")) {
        Practice_ToggleNoclip(client, "menu");
    } else if (StrEqual(info, "clear")) {
        Tracer_ClearClient(client);
        NP_Print(client, "%t", "Traces Cleared");
    } else if (StrEqual(info, "tracer")) {
        g_bTracer[client] = !g_bTracer[client];
    } else if (StrEqual(info, "preview")) {
        g_bPreview[client] = !g_bPreview[client];
    } else if (StrEqual(info, "hints")) {
        Hints_Toggle(client);
    } else if (StrEqual(info, "marker")) {
        Hints_CycleMarker(client);
    } else if (StrEqual(info, "target")) {
        Hints_CycleTarget(client);
    } else if (StrEqual(info, "measure")) {
        g_PracticeMenuPos[client] = menu.Selection;
        Measure_ShowMenu(client);
        reopen = false;
    } else if (StrEqual(info, "edit")) {
        g_PracticeMenuPos[client] = menu.Selection;
        g_bEditFromCard[client] = false;
        Edit_ShowMenu(client);
        reopen = false;
    } else if (StrEqual(info, "noflash")) {
        g_bNoFlash[client] = !g_bNoFlash[client];
    } else if (StrEqual(info, "hands")) {
        if (CanPractice(client)) {
            Practice_FixHands(client, true, "menu");
            NP_Print(client, "%t", "Hands Fixed");
        }
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
