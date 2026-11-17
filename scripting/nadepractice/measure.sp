/*
 * measure.sp - grenade measurements (stage 12):
 *   - flash check (!flash): a check point; after a real flashbang throw the player is moved
 *     there, sees the grenade arrive, gets flashed and is told for how long; then moved back;
 *   - HE damage: how much an HE would have done (the damage is seen before it is blocked);
 *   - air time: time to detonation, time to the first contact, bounces, in the air or not.
 *
 * The flash check follows the idea of ".flash" in splewis/csgo-practice-mode (GPL-3.0);
 * the code is written anew for CS:S.
 */

#define CHECK_FLASH    0    // the check point is used by flashbangs
#define CHECK_FLASH_HE 1    // by flashbangs and HE grenades

#define MAX_BLIND_PER_TICK 64

// A player_blind seen this tick, read before !noflash resets it.
enum struct BlindRec {
    int userid;
    int tick;
    float duration;     // m_flFlashDuration
    float alpha;        // m_flFlashMaxAlpha (0-255)
    float eye[3];
}

// HE damage seen in OnTakeDamage (before blocking), sent one frame later in one message.
enum struct HeHit {
    int attacker;       // userid
    int victim;         // userid
    float damage;
    int armor;          // victim armor at that moment
}

ArrayList g_Blinds;
ArrayList g_HeHits;
ArrayList g_HeDetonations;      // userids of HE throwers whose grenade went off this frame
bool g_bHeFlushQueued;
int g_FlashTick;                // tick of the last flashbang_detonate
int g_FlashesThisTick;          // flashbang_detonate events in that tick

void Measure_Init() {
    RegConsoleCmd("sm_flash", Command_Flash, "!flash - flash check point here; !flash off - turn it off");

    g_Blinds = new ArrayList(sizeof(BlindRec));
    g_HeHits = new ArrayList(sizeof(HeHit));
    g_HeDetonations = new ArrayList();

    // The tracer hooks the same events; several callbacks per event are fine.
    HookEventEx("flashbang_detonate", Event_MeasureFlash, EventHookMode_Post);
    HookEventEx("hegrenade_detonate", Event_MeasureHe, EventHookMode_Post);
}

void Measure_ResetClient(int client) {
    g_bCheckOn[client] = false;
    g_CheckMode[client] = CHECK_FLASH;
    g_bCheckReturn[client] = g_cvFlashReturn.BoolValue;
    g_bHeReport[client] = g_cvHeReport.BoolValue;
    g_bAirtimeReport[client] = g_cvAirtimeReport.BoolValue;
    g_bReturnPending[client] = false;
}

void Measure_ResetAll() {
    g_Blinds.Clear();
    g_HeHits.Clear();
    g_HeDetonations.Clear();
    g_bHeFlushQueued = false;
    g_FlashTick = 0;
    g_FlashesThisTick = 0;
}

// ---------------------------------------------------------------------------
// Check point and moving the player
// ---------------------------------------------------------------------------

void Measure_SetPoint(int client) {
    if (!CanPractice(client)) {
        return;
    }
    GetClientAbsOrigin(client, g_CheckPos[client]);
    GetClientEyeAngles(client, g_CheckAng[client]);
    g_CheckAng[client][2] = 0.0;
    g_bCheckOn[client] = true;
    LogDebug("flash check: %N point at (%.1f %.1f %.1f)", client, g_CheckPos[client][0], g_CheckPos[client][1], g_CheckPos[client][2]);
    NP_Print(client, "%t", (g_CheckMode[client] == CHECK_FLASH_HE) ? "Check Set HE" : "Check Set");
    Measure_TellNoFlash(client);
}

void Measure_Off(int client) {
    g_bCheckOn[client] = false;
    g_bReturnPending[client] = false;
    LogDebug("flash check: %N off", client);
    NP_Print(client, "%t", "Check Off");
}

void Measure_TellNoFlash(int client) {
    if (g_bNoFlash[client] && PhraseExists("Check NoFlash On")) {
        NP_Print(client, "%t", "Check NoFlash On");
    }
}

bool Measure_UsesCheck(int client, int nade) {
    if (!g_bCheckOn[client]) {
        return false;
    }
    return nade == NADE_FLASH || (nade == NADE_HE && g_CheckMode[client] == CHECK_FLASH_HE);
}

// After the snapshot of a real throw (it stays at the throw position): move the player to
// the check point and remember where to return.
void Measure_OnThrow(int client, int nade) {
    if (!Measure_UsesCheck(client, nade) || !IsPlayerAlive(client)) {
        return;
    }
    g_ReturnPos[client] = g_LastThrow[client].hasStart ? g_LastThrow[client].startOrigin : g_LastThrow[client].origin;
    g_ReturnAng[client] = g_LastThrow[client].angles;
    g_ReturnAng[client][2] = 0.0;
    g_bReturnPending[client] = true;
    Timer_OnPluginTeleport(client, "flash check");
    TeleportEntity(client, g_CheckPos[client], g_CheckAng[client], view_as<float>({ 0.0, 0.0, 0.0 }));
    Movement_Clear(client);
    LogDebug("flash check: %N moved to the check point after a %s throw", client, g_NadeKey[nade]);
}

// A replay of a flashbang: it only blinds when the replay detonation is real (stage 14.2).
void Measure_OnReplay(int client, int nade) {
    if (!Measure_UsesCheck(client, nade)) {
        return;
    }
    if (!Gamedata_RealReplay(nade)) {
        if (nade == NADE_FLASH) {
            NP_Print(client, "%t", "Check Replay No Blind");
        }
        return;
    }
    // Back to where the replay was started from.
    GetClientAbsOrigin(client, g_ReturnPos[client]);
    GetClientEyeAngles(client, g_ReturnAng[client]);
    g_ReturnAng[client][2] = 0.0;
    g_bReturnPending[client] = true;
    Timer_OnPluginTeleport(client, "flash check");
    TeleportEntity(client, g_CheckPos[client], g_CheckAng[client], view_as<float>({ 0.0, 0.0, 0.0 }));
    Movement_Clear(client);
    LogDebug("flash check: %N moved to the check point after a %s replay", client, g_NadeKey[nade]);
}

// Moves the player back to the throw position after the measurement.
void Measure_ScheduleReturn(int client, float delay) {
    if (!g_bReturnPending[client]) {
        return;
    }
    if (!g_cvFlashReturn.BoolValue || !g_bCheckReturn[client]) {
        g_bReturnPending[client] = false;
        LogDebug("flash check: %N stays at the check point (return is off)", client);
        return;
    }
    CreateTimer(delay, Timer_CheckReturn, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_CheckReturn(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client == 0 || !g_bActive || !g_bReturnPending[client] || !IsPlayerAlive(client)) {
        return Plugin_Stop;
    }
    g_bReturnPending[client] = false;
    Timer_OnPluginTeleport(client, "flash check return");
    TeleportEntity(client, g_ReturnPos[client], g_ReturnAng[client], view_as<float>({ 0.0, 0.0, 0.0 }));
    Movement_Clear(client);
    LogDebug("flash check: %N returned to the throw position", client);
    return Plugin_Stop;
}

// ---------------------------------------------------------------------------
// Flash blindness
// ---------------------------------------------------------------------------

// player_blind: read the values before !noflash resets them.
void Measure_OnBlind(int client) {
    if (!HasEntProp(client, Prop_Send, "m_flFlashDuration") || !HasEntProp(client, Prop_Send, "m_flFlashMaxAlpha")) {
        return;
    }
    int tick = GetGameTickCount();
    // Old records are useless: keep only this tick.
    BlindRec rec;
    for (int i = g_Blinds.Length - 1; i >= 0; i--) {
        g_Blinds.GetArray(i, rec);
        if (rec.tick != tick && rec.tick != g_FlashTick) {
            g_Blinds.Erase(i);
        }
    }
    if (g_Blinds.Length >= MAX_BLIND_PER_TICK) {
        return;
    }
    rec.userid = GetClientUserId(client);
    rec.tick = tick;
    rec.duration = GetEntPropFloat(client, Prop_Send, "m_flFlashDuration");
    rec.alpha = GetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha");
    GetClientEyePosition(client, rec.eye);
    g_Blinds.PushArray(rec);
    LogDebug("blind: %N duration %.2f alpha %.0f (tick %d)", client, rec.duration, rec.alpha, tick);
}

public void Event_MeasureFlash(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }
    int tick = GetGameTickCount();
    if (g_FlashTick != tick) {
        g_FlashTick = tick;
        g_FlashesThisTick = 0;
    }
    g_FlashesThisTick++;

    // The game fires player_blind for every flashed player right before flashbang_detonate,
    // in the same tick; the report is built in the next frame, when all of them are known.
    DataPack pack = new DataPack();
    pack.WriteCell(event.GetInt("userid"));
    pack.WriteCell(tick);
    pack.WriteFloat(event.GetFloat("x"));
    pack.WriteFloat(event.GetFloat("y"));
    pack.WriteFloat(event.GetFloat("z"));
    RequestFrame(Frame_FlashReport, pack);
}

public void Frame_FlashReport(DataPack pack) {
    pack.Reset();
    int thrower = GetClientOfUserId(pack.ReadCell());
    int tick = pack.ReadCell();
    float pos[3];
    pos[0] = pack.ReadFloat();
    pos[1] = pack.ReadFloat();
    pos[2] = pack.ReadFloat();
    delete pack;
    if (!g_bActive) {
        return;
    }

    bool ambiguous = (g_FlashTick == tick && g_FlashesThisTick > 1);
    BlindRec rec;
    float selfDuration = 0.0;
    bool selfBlinded = false;
    char others[192], part[64], name[MAX_NAME_LENGTH];
    others[0] = '\0';

    for (int i = 0; i < g_Blinds.Length; i++) {
        g_Blinds.GetArray(i, rec);
        if (rec.tick != tick) {
            continue;
        }
        int victim = GetClientOfUserId(rec.userid);
        LogDebug("flash report: thrower %d, victim %d, duration %.2f, alpha %.0f, distance %.0f%s", thrower, victim,
            rec.duration, rec.alpha, GetVectorDistance(pos, rec.eye), ambiguous ? " (several flashes this tick)" : "");
        if (ambiguous || victim == 0 || thrower == 0) {
            continue;
        }
        if (victim == thrower) {
            selfBlinded = true;
            selfDuration = rec.duration;
            if (PhraseExists("Flash Self") && PhraseExists("Flash Self Would")) {
                NP_Print(thrower, "%t", g_bNoFlash[thrower] ? "Flash Self Would" : "Flash Self",
                    rec.duration, RoundToNearest(rec.alpha / 255.0 * 100.0), RoundToNearest(GetVectorDistance(pos, rec.eye)));
            }
        } else if (strlen(others) < sizeof(others) - 48) {
            GetClientName(victim, name, sizeof(name));
            FormatEx(part, sizeof(part), "%s%s: %.1f s", (others[0] != '\0') ? ", " : "", name, rec.duration);
            StrCat(others, sizeof(others), part);
        }
    }
    if (ambiguous || thrower == 0 || !IsHuman(thrower)) {
        return;
    }
    if (others[0] != '\0' && PhraseExists("Flash Others")) {
        NP_Print(thrower, "%t", "Flash Others", others);
    }
    if (g_bReturnPending[thrower] && g_bCheckOn[thrower]) {
        if (!selfBlinded && PhraseExists("Flash Not Blinded")) {
            float eye[3];
            GetClientEyePosition(thrower, eye);
            NP_Print(thrower, "%t", "Flash Not Blinded", RoundToNearest(GetVectorDistance(pos, eye)));
        }
        if (selfBlinded) {
            Measure_TellNoFlash(thrower);
        }
        Measure_ScheduleReturn(thrower, (selfBlinded ? selfDuration : 0.0) + 0.5);
    }
}

// ---------------------------------------------------------------------------
// HE damage
// ---------------------------------------------------------------------------

// Called from OnTakeDamage before any blocking: what the grenade would have done.
void Measure_OnDamage(int victim, int attacker, int inflictor, float damage) {
    if (inflictor <= MaxClients || inflictor > MAX_EDICTS || !g_bProjectileEnt[inflictor] || !IsValidEntity(inflictor)) {
        return;
    }
    char classname[32];
    GetEntityClassname(inflictor, classname, sizeof(classname));
    if (!StrEqual(classname, "hegrenade_projectile") || attacker <= 0 || attacker > MaxClients || !IsClientInGame(attacker)) {
        return;
    }
    HeHit hit;
    hit.attacker = GetClientUserId(attacker);
    hit.victim = GetClientUserId(victim);
    hit.damage = damage;
    hit.armor = HasEntProp(victim, Prop_Send, "m_ArmorValue") ? GetEntProp(victim, Prop_Send, "m_ArmorValue") : 0;
    g_HeHits.PushArray(hit);
    Measure_QueueHeFlush();
}

public void Event_MeasureHe(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }
    g_HeDetonations.Push(event.GetInt("userid"));
    Measure_QueueHeFlush();
}

void Measure_QueueHeFlush() {
    if (!g_bHeFlushQueued) {
        g_bHeFlushQueued = true;
        RequestFrame(Frame_HeFlush);
    }
}

// Health damage of an HE hit on a player with full armor, by the CS:S armor rules: the
// health takes damage * ratio, the armor takes half of the rest; armor absorbs no more than
// it has. CSS-VERIFY: compare with the real damage at block_damage 0 with and without armor.
int Measure_ArmoredDamage(float damage) {
    float ratio = g_cvHeArmorRatio.FloatValue;
    float toHealth = damage * ratio;
    float toArmor = (damage - toHealth) * 0.5;
    float armor = 100.0;
    if (toArmor > armor) {
        toHealth = damage - armor / 0.5;
    }
    return RoundToNearest(toHealth);
}

public void Frame_HeFlush() {
    g_bHeFlushQueued = false;
    if (!g_bActive) {
        g_HeHits.Clear();
        g_HeDetonations.Clear();
        return;
    }
    HeHit hit;
    char line[224], part[80], name[MAX_NAME_LENGTH];

    for (int attackerIdx = 1; attackerIdx <= MaxClients; attackerIdx++) {
        if (!IsHuman(attackerIdx)) {
            continue;
        }
        int attackerUserid = GetClientUserId(attackerIdx);
        line[0] = '\0';
        int hits = 0;
        for (int i = 0; i < g_HeHits.Length; i++) {
            g_HeHits.GetArray(i, hit);
            if (hit.attacker != attackerUserid) {
                continue;
            }
            int victim = GetClientOfUserId(hit.victim);
            if (victim == 0) {
                continue;
            }
            hits++;
            LogDebug("he damage: %N -> %N %.1f (armor %d, armored estimate %d)", attackerIdx, victim, hit.damage, hit.armor,
                Measure_ArmoredDamage(hit.damage));
            GetClientName(victim, name, sizeof(name));
            if (strlen(line) < sizeof(line) - 64) {
                FormatEx(part, sizeof(part), "%s%s - %d (%T %d)", (line[0] != '\0') ? ", " : "", name,
                    RoundToNearest(hit.damage), "He Armored", attackerIdx, Measure_ArmoredDamage(hit.damage));
                StrCat(line, sizeof(line), part);
            }
            // The victim learns who hit them and how hard (not themselves).
            if (victim != attackerIdx && IsHuman(victim) && g_bHeReport[victim] && PhraseExists("He Victim")) {
                GetClientName(attackerIdx, name, sizeof(name));
                NP_Print(victim, "%t", "He Victim", name, RoundToNearest(hit.damage));
            }
        }
        bool detonated = g_HeDetonations.FindValue(attackerUserid) != -1;
        if (hits > 0 && g_bHeReport[attackerIdx] && PhraseExists("He Report") && PhraseExists("He Armored")) {
            NP_Print(attackerIdx, "%t", "He Report", line);
        } else if (hits == 0 && detonated && g_bReturnPending[attackerIdx] && g_bCheckOn[attackerIdx]
            && g_CheckMode[attackerIdx] == CHECK_FLASH_HE && PhraseExists("He No Hits")) {
            NP_Print(attackerIdx, "%t", "He No Hits");
        }
        // An HE thrown with the check point: back to the throw position after it went off.
        if (detonated && g_bReturnPending[attackerIdx] && g_CheckMode[attackerIdx] == CHECK_FLASH_HE) {
            Measure_ScheduleReturn(attackerIdx, 0.5);
        }
    }
    g_HeHits.Clear();
    g_HeDetonations.Clear();
}

// ---------------------------------------------------------------------------
// Air time
// ---------------------------------------------------------------------------

// A tracked grenade detonated. flight: from the projectile spawn; firstContact: -1 if none.
void Measure_OnDetonated(int client, int nade, float flight, float firstContact, int bounces, bool replay) {
    LogDebug("airtime: %N nade=%s replay=%d detonation %.2f s, first contact %.2f s, bounces %d", client,
        g_NadeKey[nade], replay, flight, firstContact, bounces);
    if (!g_bAirtimeReport[client] || !PhraseExists("Airtime Smoke") || !PhraseExists("Airtime Nade")
        || !PhraseExists("Airtime Contact") || !PhraseExists("Airtime No Contact")
        || !PhraseExists("Airtime In Air") || !PhraseExists("Airtime After Contact")) {
        return;
    }
    char contact[64];
    if (firstContact >= 0.0) {
        FormatEx(contact, sizeof(contact), "%T", "Airtime Contact", client, firstContact, bounces);
    } else {
        FormatEx(contact, sizeof(contact), "%T", "Airtime No Contact", client);
    }
    if (nade == NADE_SMOKE) {
        NP_Print(client, "%t", "Airtime Smoke", flight, contact);
        return;
    }
    // HE and flash have a fixed fuse: what matters is the contact and "in the air or not".
    char where[48], nadeName[32];
    bool inAir = firstContact < 0.0 || firstContact > flight;
    FormatEx(where, sizeof(where), "%T", inAir ? "Airtime In Air" : "Airtime After Contact", client);
    NadeName(client, nade, nadeName, sizeof(nadeName));
    NP_Print(client, "%t", "Airtime Nade", nadeName, flight, contact, where);
}

// ---------------------------------------------------------------------------
// Command and menu
// ---------------------------------------------------------------------------

public Action Command_Flash(int client, int args) {
    if (!CanPractice(client)) {
        return Plugin_Handled;
    }
    char arg[16];
    if (args >= 1) {
        GetCmdArg(1, arg, sizeof(arg));
    }
    if (StrEqual(arg, "off", false)) {
        Measure_Off(client);
    } else {
        Measure_SetPoint(client);
    }
    return Plugin_Handled;
}

void Measure_ShowMenu(int client) {
    Menu menu = new Menu(MenuHandler_Measure);
    menu.SetTitle("%T", "Measure Title", client);
    menu.ExitBackButton = true;
    Menu_AddPhrase(menu, client, "set", "Measure Set Point");
    if (g_bCheckOn[client]) {
        Menu_AddPhrase(menu, client, "off", "Measure Point Off");
    }
    Menu_AddChoice(menu, client, "mode", "Measure Mode", (g_CheckMode[client] == CHECK_FLASH_HE) ? "Measure Mode HE" : "Measure Mode Flash");
    Menu_AddToggle(menu, client, "return", "Measure Return", g_bCheckReturn[client]);
    Menu_AddToggle(menu, client, "he", "Measure He Report", g_bHeReport[client]);
    Menu_AddToggle(menu, client, "airtime", "Measure Airtime", g_bAirtimeReport[client]);
    Menu_AddToggle(menu, client, "noflash", "Menu Noflash", g_bNoFlash[client]);
    menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Measure(Menu menu, MenuAction action, int client, int item) {
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
    char info[16];
    menu.GetItem(item, info, sizeof(info));
    if (StrEqual(info, "set")) {
        Measure_SetPoint(client);
    } else if (StrEqual(info, "off")) {
        Measure_Off(client);
    } else if (StrEqual(info, "mode")) {
        g_CheckMode[client] = (g_CheckMode[client] == CHECK_FLASH) ? CHECK_FLASH_HE : CHECK_FLASH;
    } else if (StrEqual(info, "return")) {
        g_bCheckReturn[client] = !g_bCheckReturn[client];
    } else if (StrEqual(info, "he")) {
        g_bHeReport[client] = !g_bHeReport[client];
    } else if (StrEqual(info, "airtime")) {
        g_bAirtimeReport[client] = !g_bAirtimeReport[client];
    } else if (StrEqual(info, "noflash")) {
        g_bNoFlash[client] = !g_bNoFlash[client];
    }
    Measure_ShowMenu(client);
    return 0;
}
