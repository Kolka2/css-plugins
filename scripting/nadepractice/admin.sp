/*
 * admin.sp - server menu for admins (stage 16): start/stop the mode and toggle the plugin's own
 * cvars from the game, like ".prac" of splewis/csgo-practice-mode (the code is written anew).
 *
 * Access: sm_nadepractice_admin (changemap flag by default, can be overridden in admin_overrides).
 * Opened with !prac / .prac / sm_nadepractice_admin and from !practice ("Server"). It is a menu of
 * its own, so it can later be split from !practice completely, as splewis has it.
 *
 * Changes last until the map changes: the next map runs cfg/sourcemod/nadepractice.cfg again.
 * sv_cheats is changed only as a temporary cvar of the mode (restored when the mode stops).
 */

#define ADMIN_ACCESS "sm_nadepractice_admin"

// Boolean cvars of the plugin offered in the menu: cvar index in Admin_Cvar(), info key, phrase.
#define ADMIN_TOGGLES 7
char g_AdminToggleKey[ADMIN_TOGGLES][] = { "buy", "money", "nades", "give", "dmg", "selfdmg", "auto" };
char g_AdminTogglePhrase[ADMIN_TOGGLES][] = { "Admin Buy Anywhere", "Admin Infinite Money", "Admin Infinite Nades",
    "Admin Give On Spawn", "Admin Block Damage", "Admin Block Self Damage", "Admin Autostart" };

// g_bAdminFromPractice (Back returns to !practice) is declared in nadepractice.sp.

void Admin_Init() {
    RegAdminCmd("sm_nadepractice_admin", Command_Admin, ADMFLAG_CHANGEMAP, "Server menu of the grenade practice mode");
    RegConsoleCmd("sm_prac", Command_Admin, "Server menu of the grenade practice mode (admins)");
}

ConVar Admin_Cvar(int index) {
    switch (index) {
        case 0: { return g_cvBuyAnywhere; }
        case 1: { return g_cvInfiniteMoney; }
        case 2: { return g_cvInfinite; }
        case 3: { return g_cvGiveOnSpawn; }
        case 4: { return g_cvBlockDamage; }
        case 5: { return g_cvBlockSelfNade; }
    }
    return g_cvAutostart;
}

bool Admin_HasAccess(int client) {
    return IsHuman(client) && CheckCommandAccess(client, ADMIN_ACCESS, ADMFLAG_CHANGEMAP);
}

public Action Command_Admin(int client, int args) {
    if (!IsHuman(client)) {
        ReplyToCommand(client, "[NadePractice] In-game only.");
        return Plugin_Handled;
    }
    if (!Admin_HasAccess(client)) {
        NP_Print(client, "%t", "Admin No Access");
        return Plugin_Handled;
    }
    g_bAdminFromPractice[client] = false;
    Admin_ShowMenu(client);
    return Plugin_Handled;
}

void Admin_AddToggle(Menu menu, int client, const char[] info, const char[] phrase, bool value, bool enabled = true) {
    char text[96], name[64], state[16];
    Menu_Text(client, phrase, name, sizeof(name));
    Menu_Text(client, value ? "On" : "Off", state, sizeof(state));
    FormatEx(text, sizeof(text), "%s: %s", name, state);
    menu.AddItem(info, text, enabled ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
}

void Admin_ShowMenu(int client, int firstItem = 0) {
    Menu menu = new Menu(MenuHandler_Admin);
    char title[128];
    Menu_Text(client, "Admin Title", title, sizeof(title));
    menu.SetTitle(title);
    menu.ExitBackButton = g_bAdminFromPractice[client] && g_bActive;

    Menu_AddPhrase(menu, client, "mode", g_bActive ? "Admin Stop Mode" : "Admin Start Mode");
    for (int i = 0; i < ADMIN_TOGGLES; i++) {
        Admin_AddToggle(menu, client, g_AdminToggleKey[i], g_AdminTogglePhrase[i], Admin_Cvar(i).BoolValue);
    }
    Admin_AddToggle(menu, client, "respawn", "Admin Respawn", g_cvRespawnDelay.FloatValue > 0.0);
    // sv_cheats only as a temporary cvar of a running mode.
    ConVar cheats = FindConVar("sv_cheats");
    if (cheats != null) {
        Admin_AddToggle(menu, client, "cheats", g_bActive ? "Admin Cheats" : "Admin Cheats Inactive", cheats.BoolValue, g_bActive);
    }
    if (firstItem >= menu.ItemCount) {
        firstItem = 0;
    }
    menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int MenuHandler_Admin(Menu menu, MenuAction action, int client, int item) {
    if (action == MenuAction_End) {
        delete menu;
        return 0;
    }
    if (action == MenuAction_Cancel && item == MenuCancel_ExitBack) {
        if (g_bActive) {
            Practice_ShowMenu(client, g_PracticeMenuPos[client]);
        }
        return 0;
    }
    if (action != MenuAction_Select || !Admin_HasAccess(client)) {
        return 0;
    }
    char info[16];
    menu.GetItem(item, info, sizeof(info));
    int pos = menu.Selection;

    if (StrEqual(info, "mode")) {
        if (g_bActive) {
            Mode_Stop(true);
            LogAction(client, -1, "\"%L\" stopped the grenade practice mode", client);
        } else if (Mode_Start()) {
            LogAction(client, -1, "\"%L\" started the grenade practice mode", client);
        } else {
            NP_Print(client, "%t", "Admin Start Failed");
        }
    } else if (StrEqual(info, "respawn")) {
        // Off = 0; on = the default delay (1 s if the default itself is 0).
        bool on = g_cvRespawnDelay.FloatValue <= 0.0;
        char def[16];
        g_cvRespawnDelay.GetDefault(def, sizeof(def));
        if (on) {
            g_cvRespawnDelay.SetFloat(StringToFloat(def) > 0.0 ? StringToFloat(def) : 1.0);
        } else {
            g_cvRespawnDelay.SetFloat(0.0);
        }
        Admin_Announce(client, "Admin Respawn", on);
    } else if (StrEqual(info, "cheats")) {
        ConVar cheats = FindConVar("sv_cheats");
        if (g_bActive && cheats != null) {
            bool on = !cheats.BoolValue;
            // CSS-VERIFY: sv_cheats set from the menu returns to its previous value when the mode stops,
            // and the console noclip still goes through the plugin.
            SetCvarTemporarily("sv_cheats", on ? "1" : "0");     // restored when the mode stops
            Admin_Announce(client, "Admin Cheats", on);
        }
    } else {
        for (int i = 0; i < ADMIN_TOGGLES; i++) {
            if (StrEqual(info, g_AdminToggleKey[i])) {
                ConVar cvar = Admin_Cvar(i);
                bool on = !cvar.BoolValue;
                cvar.SetBool(on);
                Admin_Announce(client, g_AdminTogglePhrase[i], on);
                break;
            }
        }
    }
    Admin_ShowMenu(client, pos);
    return 0;
}

// Tells every admin (in their own language) and logs it.
void Admin_Announce(int admin, const char[] settingPhrase, bool on) {
    char name[MAX_NAME_LENGTH], setting[64], state[16];
    GetClientName(admin, name, sizeof(name));
    LogAction(admin, -1, "\"%L\" set \"%s\" to %s (nadepractice server menu)", admin, settingPhrase, on ? "on" : "off");
    LogDebug("admin: %N set \"%s\" to %s", admin, settingPhrase, on ? "on" : "off");
    if (!PhraseExists("Admin Changed")) {
        return;
    }
    for (int client = 1; client <= MaxClients; client++) {
        if (!Admin_HasAccess(client)) {
            continue;
        }
        Menu_Text(client, settingPhrase, setting, sizeof(setting));
        Menu_Text(client, on ? "On" : "Off", state, sizeof(state));
        NP_Print(client, "%t", "Admin Changed", name, setting, state);
    }
}
