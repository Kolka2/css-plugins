/*
 * gamedata.sp - everything that uses gamedata (gamedata/nadepractice.games.txt).
 *
 * Owner's decision (stage 14): nadepractice may use gamedata, an exception to rule 5 of
 * section 2 of ARCHITECTURE.md. Conditions:
 *   - every feature is turned on separately; if its signature is not found or a check fails,
 *     only that feature is turned off and the rest of the plugin keeps working with a fallback;
 *   - one honest LogError line per feature, pointing to docs/nadepractice/GAMEDATA.md;
 *   - sm_nadepractice_gamedata shows the state of every feature.
 *
 * Features:
 *   real replay detonation (HE, flashbang, smoke) - replay projectiles are made with the
 *   game's own static Create(), which sets the detonation timer, so they detonate for real
 *   (a flash blinds, an HE explodes - damage is blocked by the mode, a smoke is real).
 *   Fallback: plugin-made detonation (replay.sp).
 *
 * CSS-VERIFY: SDKCall of Create() on the 64-bit builds (SourceMod 1.12 uses 32-bit "pseudo
 * addresses" there; Create needs no raw pointers, but it is not checked yet).
 */

char g_GdCreateName[NADE_COUNT][] = { "CHEGrenadeProjectile::Create", "CFlashbangProjectile::Create", "CSmokeGrenadeProjectile::Create" };
char g_GdFeatureName[NADE_COUNT][] = { "real replay detonation (HE)", "real replay detonation (flashbang)", "real replay detonation (smoke)" };

Handle g_hGdCreate[NADE_COUNT];
char g_GdState[NADE_COUNT][160];    // "ok" or why the feature is off

void Gamedata_Init() {
    RegAdminCmd("sm_nadepractice_gamedata", Command_Gamedata, ADMFLAG_GENERIC, "State of every gamedata feature of nadepractice");

    GameData conf = new GameData("nadepractice.games");
    for (int nade = 0; nade < NADE_COUNT; nade++) {
        if (conf == null) {
            Gamedata_Disable(nade, "gamedata file gamedata/nadepractice.games.txt not found", "Installation");
            continue;
        }
        StartPrepSDKCall(SDKCall_Static);
        if (!PrepSDKCall_SetFromConf(conf, SDKConf_Signature, g_GdCreateName[nade])) {
            char reason[128];
            FormatEx(reason, sizeof(reason), "gamedata is out of date (signature \"%s\" not found)", g_GdCreateName[nade]);
            Gamedata_Disable(nade, reason, g_GdCreateName[nade]);
            continue;
        }
        PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);           // position
        PrepSDKCall_AddParameter(SDKType_QAngle, SDKPass_ByRef);           // angles
        PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);           // velocity
        PrepSDKCall_AddParameter(SDKType_Vector, SDKPass_ByRef);           // angular velocity (AngularImpulse)
        PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);    // owner
        if (nade == NADE_HE) {
            PrepSDKCall_AddParameter(SDKType_Float, SDKPass_Plain);        // timer (the game uses 1.5 anyway)
        }
        PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
        g_hGdCreate[nade] = EndPrepSDKCall();
        if (g_hGdCreate[nade] == null) {
            Gamedata_Disable(nade, "the call could not be prepared", g_GdCreateName[nade]);
            continue;
        }
        strcopy(g_GdState[nade], sizeof(g_GdState[]), "ok");
    }
    delete conf;
}

// Turns a feature off with one honest error line.
void Gamedata_Disable(int nade, const char[] reason, const char[] section) {
    delete g_hGdCreate[nade];
    FormatEx(g_GdState[nade], sizeof(g_GdState[]), "off: %s", reason);
    LogError("[nadepractice] Feature \"%s\" is disabled: %s. Probably the game was updated. The plugin keeps working with plugin-made detonation. How to restore it yourself: docs/nadepractice/GAMEDATA.md, section \"%s\".",
        g_GdFeatureName[nade], reason, section);
}

// Real (engine) detonation of replay projectiles is available for this grenade and allowed.
bool Gamedata_RealReplay(int nade) {
    return nade >= 0 && nade < NADE_COUNT && g_hGdCreate[nade] != null && g_cvReplayReal.BoolValue;
}

// Creates a replay projectile with the game's Create(). Returns the entity or -1 (then the
// feature is turned off if the result does not look right).
int Gamedata_CreateProjectile(int nade, int client, const float pos[3], const float vel[3]) {
    float angles[3];
    // The game spins a thrown grenade with AngularImpulse(600, random(-1200, 1200), 0).
    float angVel[3];
    angVel[0] = 600.0;
    angVel[1] = GetRandomFloat(-1200.0, 1200.0);
    int entity;
    if (nade == NADE_HE) {
        entity = SDKCall(g_hGdCreate[nade], pos, angles, vel, angVel, client, 1.5);
    } else {
        entity = SDKCall(g_hGdCreate[nade], pos, angles, vel, angVel, client);
    }
    char classname[32];
    if (entity <= MaxClients || !IsValidEntity(entity) || !GetEntityClassname(entity, classname, sizeof(classname))
        || !StrEqual(classname, g_NadeProjectile[nade])) {
        char reason[128];
        FormatEx(reason, sizeof(reason), "the check failed (\"%s\" returned entity %d \"%s\")", g_GdCreateName[nade], entity,
            (entity > MaxClients && IsValidEntity(entity)) ? classname : "");
        Gamedata_Disable(nade, reason, g_GdCreateName[nade]);
        return -1;
    }
    return entity;
}

// Short state for the load report, e.g. "he ok, flash ok, smoke off".
void Gamedata_Summary(char[] buffer, int maxlen) {
    buffer[0] = '\0';
    char part[24];
    for (int nade = 0; nade < NADE_COUNT; nade++) {
        FormatEx(part, sizeof(part), "%s%s %s", (nade > 0) ? ", " : "", g_NadeKey[nade], (g_hGdCreate[nade] != null) ? "ok" : "off");
        StrCat(buffer, maxlen, part);
    }
}

public Action Command_Gamedata(int client, int args) {
    ReplyToCommand(client, "[NadePractice] gamedata/nadepractice.games.txt, sm_nadepractice_replay_real %d:", g_cvReplayReal.IntValue);
    for (int nade = 0; nade < NADE_COUNT; nade++) {
        ReplyToCommand(client, "  %s (%s): %s", g_GdFeatureName[nade], g_GdCreateName[nade], g_GdState[nade]);
    }
    ReplyToCommand(client, "  smoke duration: no gamedata needed (env_particlesmokegrenade fade times)");
    return Plugin_Handled;
}
