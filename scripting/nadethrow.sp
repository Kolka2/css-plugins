/*
 * nadethrow - grenade throws of different strength: left click is strong,
 * left + right click is medium, right click is light.
 *
 * Layer:   service
 * Owns:    right click handling while the player holds a grenade;
 *          initial velocity and position of the projectile for throws weaker than 1.0;
 *          m_flNextPrimaryAttack of the grenade while a right click throw is being held
 * Reads:   player buttons, active weapon, player velocity
 * Uses:    nothing (sdktools and sdkhooks only)
 * API:     include/nadethrow.inc
 *
 * How CS:S throws a grenade (weapon_basecsgrenade.cpp):
 *  - left click pulls the pin (m_bPinPulled); the throw starts in the tick IN_ATTACK is released;
 *  - the projectile is created 0.1 s later (m_fThrowTime) from ItemPostFrame, that is, while
 *    the player's command is being processed;
 *  - projectile velocity = direction * force + player velocity at the moment it is created.
 * So the throw strength is latched in the tick the buttons are released, and the player
 * velocity is read when the projectile spawns.
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <nadethrow>

#define PLUGIN_VERSION "1.1.5"

#define STRENGTH_NONE   -1.0
#define STRENGTH_FULL   1.0
#define STRENGTH_MEDIUM 0.5
#define STRENGTH_LIGHT  0.0

#define THROW_BUTTONS (IN_ATTACK | IN_ATTACK2)

// How long a latched strength waits for the projectile after the buttons are released
// (the game creates it 0.1 s later).
#define THROW_LATCH_LIFETIME 0.5
// Half the side of the box used to check the lowered release point (same as the CS:S throw code).
#define TRACE_HULL_SIZE 2.0
// How far ahead m_flNextPrimaryAttack is kept while a right click throw is held.
#define ATTACK_BLOCK_TIME 0.5

public Plugin myinfo = {
    name        = "[CS:S] Nade throw strength",
    author      = "Kolka2",
    description = "Left / left+right / right click grenade throws of different strength",
    version     = PLUGIN_VERSION,
    url         = ""
};

ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvMinScale;
ConVar g_cvZOffset;
ConVar g_cvBots;
ConVar g_cvReleaseGrace;
ConVar g_cvAnnounce;

GlobalForward g_fwdOnGrenadeThrown;

char g_DebugLogPath[PLATFORM_MAX_PATH];

// --- Input (per player) ---
// Active weapon the state below was computed for.
int g_iWeaponRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
bool g_bGrenadeInHand[MAXPLAYERS + 1];
// Buttons the strength is currently derived from (0 = none held).
int g_iHeldMask[MAXPLAYERS + 1];
// A release of one of two buttons that is not applied yet (see sm_nadethrow_release_grace).
int g_iPendingMask[MAXPLAYERS + 1];
float g_fPendingMaskTime[MAXPLAYERS + 1];
// Strength at the moment of the throw, waiting for the projectile.
bool g_bThrowLatched[MAXPLAYERS + 1];
float g_fThrowStrength[MAXPLAYERS + 1];
float g_fThrowTime[MAXPLAYERS + 1];
// Right click has been held at some point of the current hold.
bool g_bRightClickUsed[MAXPLAYERS + 1];

// --- Projectile (per owner) ---
// Projectile that has spawned and waits for the adjustment.
int g_iProjectileRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
// Last processed projectile (so the RequestFrame fallback does not process it again).
int g_iDoneRef[MAXPLAYERS + 1] = { INVALID_ENT_REFERENCE, ... };
float g_fProjectileStrength[MAXPLAYERS + 1];
// Player velocity at the moment the projectile spawned.
float g_vecPlayerVel[MAXPLAYERS + 1][3];

// userid that has already seen the chat announcement. A userid survives map changes,
// so the message is shown once per connection, not once per map.
int g_iAnnouncedUserId[MAXPLAYERS + 1];

// Missing property / phrase messages are logged once.
bool g_bLoggedNoPinProp;
bool g_bLoggedNoVelProp;
bool g_bLoggedNoOwnerProp;
bool g_bLoggedNoPhrase;

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    if (GetEngineVersion() != Engine_CSS) {
        strcopy(error, err_max, "This plugin supports Counter-Strike: Source only.");
        return APLRes_Failure;
    }

    CreateNative("Nadethrow_GetApiVersion", Native_GetApiVersion);
    CreateNative("Nadethrow_IsEnabled", Native_IsEnabled);
    CreateNative("Nadethrow_GetThrowStrength", Native_GetThrowStrength);
    CreateNative("Nadethrow_GetMinScale", Native_GetMinScale);
    CreateNative("Nadethrow_GetZOffset", Native_GetZOffset);
    RegPluginLibrary(NADETHROW_LIBRARY);
    return APLRes_Success;
}

public void OnPluginStart() {
    LoadTranslations("nadethrow.phrases");

    CreateConVar("sm_nadethrow_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvEnabled      = CreateConVar("sm_nadethrow_enabled", "1", "Enable throws of different strength (left / left+right / right click)", _, true, 0.0, true, 1.0);
    g_cvDebug        = CreateConVar("sm_nadethrow_debug", "0", "Verbose log in logs/nadethrow_debug.log", _, true, 0.0, true, 1.0);
    g_cvMinScale     = CreateConVar("sm_nadethrow_min_scale", "0.35", "Fraction of the throw's own speed at strength 0.0 (right click)", _, true, 0.0, true, 1.0);
    g_cvZOffset      = CreateConVar("sm_nadethrow_z_offset", "12.0", "How many units lower the grenade is released at strength 0.0 (right click)", _, true, 0.0, true, 64.0);
    g_cvBots         = CreateConVar("sm_nadethrow_bots", "0", "Process bot input", _, true, 0.0, true, 1.0);
    g_cvReleaseGrace = CreateConVar("sm_nadethrow_release_grace", "0.1", "Seconds during which releasing one of two held buttons does not change the strength (0 = strictly the last tick)", _, true, 0.0, true, 0.5);
    g_cvAnnounce     = CreateConVar("sm_nadethrow_announce", "1", "Tell each player in chat, once per connection, how to throw with different strength", _, true, 0.0, true, 1.0);
    AutoExecConfig(true, "nadethrow");

    g_cvEnabled.AddChangeHook(OnEnabledChanged);

    g_fwdOnGrenadeThrown = new GlobalForward("Nadethrow_OnGrenadeThrown", ET_Ignore, Param_Cell, Param_Cell, Param_Float);

    BuildPath(Path_SM, g_DebugLogPath, sizeof(g_DebugLogPath), "logs/nadethrow_debug.log");

    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("player_spawn", Event_PlayerSpawn);

    // Late load: nothing is hooked per player, a clean state is enough.
    ResetAll();
}

public void OnAllPluginsLoaded() {
    LogMessage("[nadethrow] %s, optional libraries: none", PLUGIN_VERSION);
}

public void OnMapStart() {
    ResetAll();
}

public void OnMapEnd() {
    ResetAll();
}

public void OnClientDisconnect(int client) {
    ResetClient(client);
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    ResetAll();
    LogDebug("enabled changed: %s -> %s", oldValue, newValue);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
    int client = GetClientOfUserId(event.GetInt("userid"));
    if (client != 0) {
        ResetInput(client);
    }
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    int userid = event.GetInt("userid");
    int client = GetClientOfUserId(userid);
    if (client == 0) {
        return;
    }
    ResetInput(client);
    Announce(client, userid);
}

void ResetAll() {
    for (int client = 1; client <= MaxClients; client++) {
        ResetClient(client);
    }
}

void ResetClient(int client) {
    ResetInput(client);
    g_iProjectileRef[client] = INVALID_ENT_REFERENCE;
    g_iDoneRef[client] = INVALID_ENT_REFERENCE;
}

// Resets everything related to input: weapon switch, death, disconnect, map change.
// A projectile that is already out and waits for the adjustment stays: its strength is decided.
void ResetInput(int client) {
    g_iWeaponRef[client] = INVALID_ENT_REFERENCE;
    g_bGrenadeInHand[client] = false;
    g_iHeldMask[client] = 0;
    g_iPendingMask[client] = 0;
    g_bRightClickUsed[client] = false;
    g_bThrowLatched[client] = false;
}

// One chat message per connection, on the first spawn in a team.
void Announce(int client, int userid) {
    if (g_iAnnouncedUserId[client] == userid
        || !g_cvEnabled.BoolValue || !g_cvAnnounce.BoolValue
        || IsFakeClient(client) || GetClientTeam(client) < CS_TEAM_T || !IsPlayerAlive(client)) {
        return;
    }
    g_iAnnouncedUserId[client] = userid;

    // A missing phrase would throw; the translation files are easy to forget when installing.
    if (!TranslationPhraseExists("Announce")) {
        if (!g_bLoggedNoPhrase) {
            g_bLoggedNoPhrase = true;
            LogError("Phrase \"Announce\" not found: install translations/nadethrow.phrases.txt");
        }
        return;
    }
    PrintToChat(client, "\x01[\x04NadeThrow\x01] %t", "Announce");
}

// ---------------------------------------------------------------------------
// Input and throw strength
// ---------------------------------------------------------------------------

// Whether the plugin processes this player's input. Humans always, bots by convar.
bool IsHandledClient(int client) {
    return !IsFakeClient(client) || g_cvBots.BoolValue;
}

public Action OnPlayerRunCmd(int client, int &buttons) {
    if (!g_cvEnabled.BoolValue || !IsHandledClient(client)) {
        return Plugin_Continue;
    }
    if (!IsPlayerAlive(client)) {
        if (g_iWeaponRef[client] != INVALID_ENT_REFERENCE) {
            ResetInput(client);
        }
        return Plugin_Continue;
    }

    int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
    int weaponRef = (weapon > 0) ? EntIndexToEntRef(weapon) : INVALID_ENT_REFERENCE;
    if (weaponRef != g_iWeaponRef[client]) {
        // A weapon switch cancels both the hold and an unfinished throw.
        ResetInput(client);
        g_iWeaponRef[client] = weaponRef;
        g_bGrenadeInHand[client] = (weapon > 0) && IsGrenadeWeapon(weapon);
    }
    if (!g_bGrenadeInHand[client]) {
        return Plugin_Continue;
    }

    int mask = buttons & THROW_BUTTONS;
    if (mask == 0) {
        if (g_iHeldMask[client] != 0) {
            OnThrowButtonsReleased(client, weapon);
        }
        return Plugin_Continue;
    }

    UpdateHeldMask(client, mask);
    if (mask & IN_ATTACK2) {
        g_bRightClickUsed[client] = true;
    }

    // Left click only, from press to release: nothing is touched at all, a normal throw stays normal.
    if (!g_bRightClickUsed[client]) {
        return Plugin_Continue;
    }

    // Right click has been part of this hold. Keep the block until the throw, even if only
    // left click is held now: the client still believes the pin is not pulled.
    BlockPredictedPinPull(weapon);
    if (mask == IN_ATTACK) {
        return Plugin_Continue;
    }

    // The first person pin pull animation is fine with this, and other players see the normal
    // pin pull pose. The thrower's own client believes the pin is not pulled while only right
    // click is held, so in its own third person view the player model drops the arm.
    buttons = (buttons | IN_ATTACK) & ~IN_ATTACK2;
    return Plugin_Changed;
}

// The client does not know that right click holds the pin: it predicts a throw as soon as
// its own IN_ATTACK is up, and then predicts a new pin pull (animation and sound) on every
// left click press while right click is still held. Keeping m_flNextPrimaryAttack slightly
// in the future stops the client from predicting that attack. The server does not need
// PrimaryAttack while the pin is pulled, and the throw itself sets the property again.
// The throw does not depend on m_flNextPrimaryAttack, so it is not delayed.
void BlockPredictedPinPull(int weapon) {
    // Only once the pin is pulled, otherwise the block would prevent pulling it.
    if (!IsPinPulled(weapon) || !HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack")) {
        return;
    }
    SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", GetGameTime() + ATTACK_BLOCK_TIME);
}

// Updates the buttons the strength is derived from. An added button applies at once.
// A release of one of two buttons applies only if the other one stays held longer than
// sm_nadethrow_release_grace: fingers rarely release both buttons in the same tick, and
// without this a medium throw would turn into a strong or a light one.
void UpdateHeldMask(int client, int mask) {
    int held = g_iHeldMask[client];
    if (mask == held) {
        g_iPendingMask[client] = 0;
        return;
    }

    bool released = (mask & ~held) == 0;  // no new buttons, one of two was released
    float grace = g_cvReleaseGrace.FloatValue;
    if (released && grace > 0.0) {
        float now = GetGameTime();
        if (g_iPendingMask[client] != mask) {
            g_iPendingMask[client] = mask;
            g_fPendingMaskTime[client] = now;
        }
        if (now - g_fPendingMaskTime[client] < grace) {
            return;
        }
    }

    g_iHeldMask[client] = mask;
    g_iPendingMask[client] = 0;
    LogDebug("%N: holding, strength %.1f", client, MaskToStrength(mask));
}

// Both buttons are released: the game starts the throw in this tick if the pin is pulled.
void OnThrowButtonsReleased(int client, int weapon) {
    float strength = MaskToStrength(g_iHeldMask[client]);
    g_iHeldMask[client] = 0;
    g_iPendingMask[client] = 0;
    g_bRightClickUsed[client] = false;

    // The button may have been pressed and released while the pin cannot be pulled (drawing
    // the grenade, right after the previous throw): there is no throw and nothing to latch.
    if (!IsPinPulled(weapon)) {
        LogDebug("%N: released, pin not pulled, no throw", client);
        return;
    }

    g_bThrowLatched[client] = true;
    g_fThrowStrength[client] = strength;
    g_fThrowTime[client] = GetGameTime();
    LogDebug("%N: released, throw strength %.1f", client, strength);
}

// Takes the strength for a spawned projectile. No fresh latched throw means a normal throw.
float ConsumeThrowStrength(int client) {
    if (!g_bThrowLatched[client]) {
        return STRENGTH_FULL;
    }
    g_bThrowLatched[client] = false;
    if (GetGameTime() - g_fThrowTime[client] > THROW_LATCH_LIFETIME) {
        return STRENGTH_FULL;
    }
    return g_fThrowStrength[client];
}

float MaskToStrength(int mask) {
    if (mask == THROW_BUTTONS) {
        return STRENGTH_MEDIUM;
    }
    if (mask == IN_ATTACK) {
        return STRENGTH_FULL;
    }
    if (mask == IN_ATTACK2) {
        return STRENGTH_LIGHT;
    }
    return STRENGTH_NONE;
}

bool IsGrenadeWeapon(int weapon) {
    char classname[32];
    if (!GetEntityClassname(weapon, classname, sizeof(classname))) {
        return false;
    }
    return StrEqual(classname, "weapon_hegrenade")
        || StrEqual(classname, "weapon_flashbang")
        || StrEqual(classname, "weapon_smokegrenade");
}

// Whether the pin is pulled. Without the property the pin counts as pulled while a button is held.
bool IsPinPulled(int weapon) {
    if (weapon <= 0 || !IsValidEntity(weapon)) {
        return false;
    }
    if (!HasEntProp(weapon, Prop_Send, "m_bPinPulled")) {
        if (!g_bLoggedNoPinProp) {
            g_bLoggedNoPinProp = true;
            LogError("m_bPinPulled not found on grenade weapon, assuming the pin is pulled while a button is held");
        }
        return true;
    }
    return GetEntProp(weapon, Prop_Send, "m_bPinPulled") != 0;
}

// ---------------------------------------------------------------------------
// Projectile
// ---------------------------------------------------------------------------

public void OnEntityCreated(int entity, const char[] classname) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    if (StrEqual(classname, "hegrenade_projectile")
        || StrEqual(classname, "flashbang_projectile")
        || StrEqual(classname, "smokegrenade_projectile")) {
        SDKHook(entity, SDKHook_SpawnPost, OnProjectileSpawnPost);
    }
}

public void OnProjectileSpawnPost(int entity) {
    if (!g_cvEnabled.BoolValue) {
        return;
    }
    int ref = EntIndexToEntRef(entity);

    // At SpawnPost the owner is already known through m_hOwnerEntity (the game sets m_hThrower
    // later). If it is not, the owner is looked up in the next frame, see Frame_Projectile.
    int client = GetProjectileOwner(entity);
    if (client != 0) {
        RegisterProjectile(client, ref);
    }

    // The game sets the projectile velocity after Spawn, so the adjustment happens later:
    // in the owner's OnPlayerRunCmdPost (same tick) or, failing that, in the next frame.
    RequestFrame(Frame_Projectile, ref);
}

// Binds the projectile to its owner: throw strength and player velocity at this moment.
void RegisterProjectile(int client, int ref) {
    g_iProjectileRef[client] = ref;
    g_fProjectileStrength[client] = ConsumeThrowStrength(client);
    GetEntPropVector(client, Prop_Data, "m_vecAbsVelocity", g_vecPlayerVel[client]);
}

// The projectile is created while the player's command is processed, so here it already has
// its initial velocity but has not moved a single tick and has not been sent to clients:
// the adjustment causes no visible jerk. Debug log: "via cmdpost".
public void OnPlayerRunCmdPost(int client, int buttons) {
    if (g_iProjectileRef[client] != INVALID_ENT_REFERENCE) {
        FinishProjectile(client, true);
    }
}

// Fallback: the frame after the projectile spawned. Debug log: "via frame".
public void Frame_Projectile(int ref) {
    int entity = EntRefToEntIndex(ref);
    if (entity == INVALID_ENT_REFERENCE) {
        return;
    }

    for (int client = 1; client <= MaxClients; client++) {
        if (g_iDoneRef[client] == ref) {
            LogProjectileState(entity, "next frame");
            return;
        }
        if (g_iProjectileRef[client] == ref) {
            FinishProjectile(client, false);
            return;
        }
    }

    // The owner was not known when the projectile spawned.
    int client = GetProjectileOwner(entity);
    if (client == 0) {
        LogDebug("projectile %d: owner not found, left unchanged", entity);
        return;
    }
    RegisterProjectile(client, ref);
    FinishProjectile(client, false);
}

void FinishProjectile(int client, bool fromCmdPost) {
    int ref = g_iProjectileRef[client];
    int entity = EntRefToEntIndex(ref);
    if (entity == INVALID_ENT_REFERENCE || !IsClientInGame(client)) {
        g_iProjectileRef[client] = INVALID_ENT_REFERENCE;
        return;
    }

    float strength = g_fProjectileStrength[client];
    if (strength < STRENGTH_FULL) {
        if (!AdjustProjectile(entity, client, strength, fromCmdPost)) {
            if (fromCmdPost) {
                // No velocity yet: the fallback will try again in the next frame.
                return;
            }
            // Could not adjust: the projectile stays normal, and that is what gets reported.
            strength = STRENGTH_FULL;
        }
    } else {
        LogDebug("%N: projectile %d, strength 1.0, unchanged", client, entity);
    }

    g_iProjectileRef[client] = INVALID_ENT_REFERENCE;
    g_iDoneRef[client] = ref;
    LogProjectileState(entity, "thrown");

    Call_StartForward(g_fwdOnGrenadeThrown);
    Call_PushCell(client);
    Call_PushCell(entity);
    Call_PushFloat(strength);
    Call_Finish();
}

// Recomputes the velocity and the release point of the projectile. false = left unchanged.
bool AdjustProjectile(int entity, int client, float strength, bool fromCmdPost) {
    if (!HasEntProp(entity, Prop_Data, "m_vecAbsVelocity")) {
        if (!g_bLoggedNoVelProp) {
            g_bLoggedNoVelProp = true;
            LogError("m_vecAbsVelocity not found on grenade projectile, throws are not adjusted");
        }
        return false;
    }

    float pos[3], vel[3];
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
    GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vel);
    if (GetVectorLength(vel, true) < 1.0) {
        LogDebug("%N: projectile %d has no velocity yet (%s)", client, entity, fromCmdPost ? "cmdpost" : "frame");
        return false;
    }

    // Velocity: only the throw's own part is scaled, the player's velocity is kept.
    // CS:S adds the full player velocity to the throw (vForward * flVel + GetAbsVelocity()),
    // taken when the projectile is created.
    float k = g_cvMinScale.FloatValue + (1.0 - g_cvMinScale.FloatValue) * strength;
    float newVel[3];
    for (int i = 0; i < 3; i++) {
        newVel[i] = (vel[i] - g_vecPlayerVel[client][i]) * k + g_vecPlayerVel[client][i];
    }

    // Position: lower by (1 - strength) * zOffset unless something is in the way.
    float newPos[3];
    newPos = pos;
    float drop = (1.0 - strength) * g_cvZOffset.FloatValue;
    bool lowered = false;
    if (drop > 0.0) {
        newPos[2] -= drop;
        float mins[3] = { -TRACE_HULL_SIZE, -TRACE_HULL_SIZE, -TRACE_HULL_SIZE };
        float maxs[3] = { TRACE_HULL_SIZE, TRACE_HULL_SIZE, TRACE_HULL_SIZE };
        Handle trace = TR_TraceHullFilterEx(pos, newPos, mins, maxs, MASK_SOLID, TraceFilter_NoPlayers, entity);
        lowered = !TR_DidHit(trace) && !TR_StartSolid(trace);
        delete trace;
        if (!lowered) {
            newPos = pos;
        }
    }

    // The game does not overwrite the velocity after this.
    // The position is passed only when it changes. A teleport to a new position marks the
    // entity as "teleported" for clients (m_ubInterpolationFrame 0 -> 1), and clients then
    // draw the first moments of the flight at the unscaled speed. The server state is correct
    // either way, so the mark is undone (confirmed with a SourceTV demo).
    if (lowered) {
        bool hasInterpFrame = HasEntProp(entity, Prop_Send, "m_ubInterpolationFrame");
        int interpFrame = hasInterpFrame ? GetEntProp(entity, Prop_Send, "m_ubInterpolationFrame") : 0;
        TeleportEntity(entity, newPos, NULL_VECTOR, newVel);
        if (hasInterpFrame) {
            SetEntProp(entity, Prop_Send, "m_ubInterpolationFrame", interpFrame);
        }
    } else {
        TeleportEntity(entity, NULL_VECTOR, NULL_VECTOR, newVel);
    }

    // The client builds the start of the trajectory from m_vInitialVelocity; keep it consistent.
    if (HasEntProp(entity, Prop_Send, "m_vInitialVelocity")) {
        SetEntPropVector(entity, Prop_Send, "m_vInitialVelocity", newVel);
    }

    LogDebug("%N: projectile %d via %s, strength %.2f, k %.2f, player vel (%.1f %.1f %.1f), vel (%.1f %.1f %.1f) -> (%.1f %.1f %.1f), pos (%.1f %.1f %.1f) -> (%.1f %.1f %.1f)%s",
        client, entity, fromCmdPost ? "cmdpost" : "frame", strength, k,
        g_vecPlayerVel[client][0], g_vecPlayerVel[client][1], g_vecPlayerVel[client][2],
        vel[0], vel[1], vel[2], newVel[0], newVel[1], newVel[2],
        pos[0], pos[1], pos[2], newPos[0], newPos[1], newPos[2],
        (drop > 0.0 && !lowered) ? " (blocked, position kept)" : "");
    return true;
}

// Everything except players and the projectile itself counts as an obstacle.
public bool TraceFilter_NoPlayers(int entity, int contentsMask, any projectile) {
    return entity > MaxClients && entity != projectile;
}

// The player who threw the projectile, or 0.
int GetProjectileOwner(int entity) {
    bool hasThrower = HasEntProp(entity, Prop_Send, "m_hThrower");
    bool hasOwner = HasEntProp(entity, Prop_Send, "m_hOwnerEntity");
    if (!hasThrower && !hasOwner && !g_bLoggedNoOwnerProp) {
        g_bLoggedNoOwnerProp = true;
        LogError("Neither m_hThrower nor m_hOwnerEntity found on grenade projectile, throws are not adjusted");
    }

    int owner = hasThrower ? GetEntPropEnt(entity, Prop_Send, "m_hThrower") : -1;
    if (!IsValidClientIndex(owner) && hasOwner) {
        owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
    }
    if (!IsValidClientIndex(owner) || !IsClientInGame(owner)) {
        return 0;
    }
    return owner;
}

bool IsValidClientIndex(int client) {
    return client >= 1 && client <= MaxClients;
}

// ---------------------------------------------------------------------------
// Natives
// ---------------------------------------------------------------------------

public int Native_GetApiVersion(Handle plugin, int numParams) {
    return NADETHROW_API_VERSION;
}

public int Native_IsEnabled(Handle plugin, int numParams) {
    return g_cvEnabled.BoolValue;
}

public any Native_GetThrowStrength(Handle plugin, int numParams) {
    int client = GetNativeCell(1);
    if (!IsValidClientIndex(client) || !IsClientInGame(client)) {
        return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is invalid or not in game", client);
    }

    if (g_iHeldMask[client] == 0 || !IsPinPulled(EntRefToEntIndex(g_iWeaponRef[client]))) {
        return STRENGTH_NONE;
    }
    return MaskToStrength(g_iHeldMask[client]);
}

public any Native_GetMinScale(Handle plugin, int numParams) {
    return g_cvMinScale.FloatValue;
}

public any Native_GetZOffset(Handle plugin, int numParams) {
    return g_cvZOffset.FloatValue;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// Debug only: what the server actually has for the projectile (right after the throw is
// processed and one frame later), to tell server side jerks from client interpolation.
void LogProjectileState(int entity, const char[] when) {
    if (!g_cvDebug.BoolValue || !HasEntProp(entity, Prop_Data, "m_vecAbsVelocity")) {
        return;
    }
    float pos[3], vel[3], initial[3];
    GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);
    GetEntPropVector(entity, Prop_Data, "m_vecAbsVelocity", vel);
    if (HasEntProp(entity, Prop_Send, "m_vInitialVelocity")) {
        GetEntPropVector(entity, Prop_Send, "m_vInitialVelocity", initial);
    }
    LogDebug("projectile %d state (%s, tick %d): pos (%.1f %.1f %.1f), vel (%.1f %.1f %.1f), initial vel (%.1f %.1f %.1f)",
        entity, when, GetGameTickCount(),
        pos[0], pos[1], pos[2], vel[0], vel[1], vel[2], initial[0], initial[1], initial[2]);
}

void LogDebug(const char[] format, any ...) {
    if (!g_cvDebug.BoolValue) {
        return;
    }
    char buffer[512];
    VFormat(buffer, sizeof(buffer), format, 2);
    LogToFileEx(g_DebugLogPath, "%s", buffer);
}
