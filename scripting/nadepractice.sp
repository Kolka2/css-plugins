/*
 * nadepractice - grenade lineup practice mode for CS:S.
 *
 * Layer:   mode
 * Owns:    practice state of every player (noclip, last throw, trajectories,
 *          selected lineup), the lineup database
 *          (configs/nadepractice/lineups/<map>.cfg), players' money, grenades and
 *          damage while the mode is active, the bot count (bot_quota 0),
 *          its own temporary cvars (listed in Mode_Start).
 * Reads:   game events (player_spawn, *_detonate, player_blind), sv_gravity.
 * Uses:    nothing (warmup integration is planned for later).
 * API:     include/nadepractice.inc
 *
 * Parts (scripting/nadepractice/):
 *   util.sp     - logging, temporary cvars, client checks, drawing, chat
 *   throws.sp   - throw detection and the "last throw" snapshot
 *   replay.sp   - throw replay (projectile creation and detonation)
 *   practice.sp - infinite grenades, damage, player commands, main menu
 *   tracer.sp   - recording and drawing real throw trajectories
 *   lineups.sp  - lineup database: file, commands, menus
 *   hints.sp    - hints for the selected lineup
 *   preview.sp  - flight model, preview before the throw, prediction check
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <nadepractice>

#define PLUGIN_VERSION "0.1.0"

public Plugin myinfo = {
    name        = "[CS:S] Nade Practice",
    author      = "css-plugins",
    description = "Grenade lineup practice mode",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

#define NADE_NONE  -1
#define NADE_HE     0
#define NADE_FLASH  1
#define NADE_SMOKE  2
#define NADE_COUNT  3

#define THROW_STAND   0
#define THROW_CROUCH  1
#define THROW_JUMP    2
#define THROW_RUN     3
#define THROW_RUNJUMP 4
#define THROW_COUNT   5

// Trajectory point kinds: normal, bounce, detonation.
#define PT_NORMAL   0
#define PT_BOUNCE   1
#define PT_DETONATE 2

#define MAX_EDICTS       2048
#define MAX_PATH_POINTS  32     // points of the simplified trajectory in a lineup
#define MAX_TRAJ         10     // upper limit of sm_nadepractice_trace_count
#define MAX_TRAJ_POINTS  256    // points in one recorded trajectory
#define RUN_SPEED        60.0   // horizontal speed above which a throw counts as "running"

// Chat prefix: brackets in the default color, the plugin name in green (CLAUDE.md).
#define CHAT_PREFIX "\x01[\x04NadePractice\x01] "

char g_NadeWeapon[NADE_COUNT][] = { "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade" };
char g_NadeProjectile[NADE_COUNT][] = { "hegrenade_projectile", "flashbang_projectile", "smokegrenade_projectile" };
char g_NadeKey[NADE_COUNT][] = { "he", "flash", "smoke" };
char g_NadePhrase[NADE_COUNT][] = { "Nade HE", "Nade Flash", "Nade Smoke" };
int g_NadeColor[NADE_COUNT][4] = { { 255, 70, 50, 255 }, { 90, 170, 255, 255 }, { 70, 255, 100, 255 } };

char g_ThrowKey[THROW_COUNT][] = { "stand", "crouch", "jump", "run", "runjump" };
char g_ThrowPhrase[THROW_COUNT][] = { "Throw Stand", "Throw Crouch", "Throw Jump", "Throw Run", "Throw RunJump" };

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

// Throw snapshot: player state at the moment the projectile appears, and the projectile.
enum struct ThrowInfo {
    bool valid;
    int serial;             // unique throw number
    int nade;
    float origin[3];        // player position (feet)
    float eye[3];           // eye position
    float angles[3];        // view angles
    float velocity[3];      // player velocity
    int buttons;
    int flags;
    int throwType;
    bool hasProj;
    float projOrigin[3];    // initial projectile position
    float projVelocity[3];  // initial projectile velocity
    bool hasDetonation;
    float detonation[3];
    int pathCount;
    float path[MAX_PATH_POINTS * 3];
}

// Replay projectile driven by the plugin.
enum struct ReplayEnt {
    int ref;
    int userid;
    int nade;
    float detonateAt;
    float nextCheck;
    float killAt;
}

// Projectile followed by the tracer.
enum struct Tracked {
    int ref;
    int userid;
    int nade;
    int slot;               // trajectory slot of the owner
    int serial;             // trajectory serial (the slot may have been reused)
    int throwSerial;        // throw serial in g_LastThrow, or 0 (replay)
    bool replay;
    float spawnTime;
    float nextSample;
    float lastPos[3];
    float lastPoint[3];     // last recorded point
    float lastVel[3];
    bool hasVel;
    bool hasPrediction;
    float predicted[3];     // where the model expects the detonation
}

// Lineup from the database.
enum struct Lineup {
    int id;                 // id for the current map (not written to the file)
    char name[64];
    int nade;
    int throwType;
    float origin[3];
    float angles[3];
    float eye[3];
    bool hasProj;
    float projOrigin[3];
    float projVelocity[3];
    bool hasDetonation;
    float detonation[3];
    char author[64];
    char desc[128];
    int pathCount;
    float path[MAX_PATH_POINTS * 3];
}

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

ConVar g_cvEnabled;
ConVar g_cvDebug;
ConVar g_cvAutostart;
ConVar g_cvRestartOnStart;
ConVar g_cvTeBudget;

// practice
ConVar g_cvInfinite;
ConVar g_cvGiveOnSpawn;
ConVar g_cvBlockDamage;
ConVar g_cvBlockSelfNade;

// replay
ConVar g_cvReplayMode;
ConVar g_cvReplayEngineFuse;
ConVar g_cvReplayVisibleAll;
ConVar g_cvReplayCooldown;
ConVar g_cvReplaySmokeTime;

// grenade physics (shared by replay and the preview model)
ConVar g_cvSimGravity;
ConVar g_cvSimElasticity;
ConVar g_cvSimFriction;
ConVar g_cvSimFuse;
ConVar g_cvSimSmokeFuse;
ConVar g_cvSimThink;

// tracer
ConVar g_cvTraceCount;
ConVar g_cvTraceSample;
ConVar g_cvTraceRedraw;
ConVar g_cvTraceMaxSeg;
ConVar g_cvTraceWidth;
ConVar g_cvTraceMaxTime;
ConVar g_cvTraceBounceDv;

// lineups
ConVar g_cvEditAccess;

// hints
ConVar g_cvHintInterval;
ConVar g_cvHintPosRadius;
ConVar g_cvHintAngleTol;
ConVar g_cvHintMode;
ConVar g_cvHintUnicode;
ConVar g_cvHintLookDist;

// preview and flight model
ConVar g_cvPrevDefault;
ConVar g_cvPrevInterval;
ConVar g_cvPrevMaxSeg;
ConVar g_cvSimMaxSteps;
ConVar g_cvSimMaxBounces;
ConVar g_cvSimTickMult;
ConVar g_cvSimStopSpeed;
ConVar g_cvSimThrowMax;
ConVar g_cvSimThrowFactor;
ConVar g_cvSimPitchOffset;
ConVar g_cvSimForward;
ConVar g_cvSimHull;
ConVar g_cvSimPlayerVel;

ConVar g_cvGravity;     // sv_gravity (read only)

StringMap g_SavedCvars;
StringMap g_MissingPhrases;     // phrases already reported as missing
char g_DebugLogPath[PLATFORM_MAX_PATH];

bool g_bActive;
bool g_bLateLoad;

int g_BeamSprite = -1;
int g_HaloSprite = -1;
int g_GlowSprite = -1;
int g_ExplosionSprite = -1;

// temp entity budget per frame
int g_TeTick[MAXPLAYERS + 1];
int g_TeLeft[MAXPLAYERS + 1];

// player state
bool g_bNoclip[MAXPLAYERS + 1];
bool g_bNoFlash[MAXPLAYERS + 1];
ThrowInfo g_LastThrow[MAXPLAYERS + 1];
int g_PendingThrowRef[MAXPLAYERS + 1];
float g_NextReplay[MAXPLAYERS + 1];

// throws
int g_ThrowSerial;
bool g_bProjectileEnt[MAX_EDICTS + 1];
bool g_bLoggedMissingProp;

// replay
bool g_bReplaySpawning;
int g_ReplayOwner[MAX_EDICTS + 1];
ArrayList g_ReplayEnts;
ArrayList g_ReplayEffects;

// tracer
ArrayList g_Tracked;
ArrayList g_TrajPoints[MAXPLAYERS + 1][MAX_TRAJ];
int g_TrajNade[MAXPLAYERS + 1][MAX_TRAJ];
int g_TrajSerial[MAXPLAYERS + 1][MAX_TRAJ];
int g_TrajNext[MAXPLAYERS + 1];
int g_TrajSerialCounter;
bool g_bTracer[MAXPLAYERS + 1];
int g_DrawSlot[MAXPLAYERS + 1];
int g_DrawIdx[MAXPLAYERS + 1];
float g_DrawLife[MAXPLAYERS + 1];
float g_DrawNextCycle[MAXPLAYERS + 1];
float g_NextDraw[MAXPLAYERS + 1];

// lineups
ArrayList g_Lineups;
int g_NextLineupId = 1;
char g_LineupsFile[PLATFORM_MAX_PATH];
int g_MenuFilter[MAXPLAYERS + 1];
int g_MenuLineup[MAXPLAYERS + 1];
bool g_bMenuFromPractice[MAXPLAYERS + 1];   // lineup menu opened from !practice: has a Back button
int g_PracticeMenuPos[MAXPLAYERS + 1];      // first item of the !practice page to return to
int g_ListMenuPos[MAXPLAYERS + 1];          // first item of the lineup list page to return to

// hints
Handle g_HudSync;
bool g_bHints[MAXPLAYERS + 1];
int g_SelectedLineup[MAXPLAYERS + 1];
float g_NextHint[MAXPLAYERS + 1];
float g_NextHintDraw[MAXPLAYERS + 1];
bool g_bHintShown[MAXPLAYERS + 1];
float g_HintGround[MAXPLAYERS + 1][3];
float g_HintMarker[MAXPLAYERS + 1][3];

// preview and prediction check
ArrayList g_SimPath;
bool g_bPreview[MAXPLAYERS + 1];
float g_NextPreview[MAXPLAYERS + 1];
int g_ErrCount[MAXPLAYERS + 1];
float g_ErrSum[MAXPLAYERS + 1];
float g_ErrMax[MAXPLAYERS + 1];
float g_ErrLast[MAXPLAYERS + 1];

#include "nadepractice/util.sp"
#include "nadepractice/throws.sp"
#include "nadepractice/replay.sp"
#include "nadepractice/practice.sp"
#include "nadepractice/tracer.sp"
#include "nadepractice/lineups.sp"
#include "nadepractice/hints.sp"
#include "nadepractice/preview.sp"

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
    if (GetEngineVersion() != Engine_CSS) {
        strcopy(error, err_max, "This plugin supports Counter-Strike: Source only.");
        return APLRes_Failure;
    }

    g_bLateLoad = late;
    CreateNative("Nadepractice_IsActive", Native_IsActive);
    CreateNative("Nadepractice_GetApiVersion", Native_GetApiVersion);
    RegPluginLibrary(NADEPRACTICE_LIBRARY);
    return APLRes_Success;
}

public void OnPluginStart() {
    LoadTranslations("nadepractice.phrases");

    CreateConVar("sm_nadepractice_version", PLUGIN_VERSION, "Plugin version", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvEnabled        = CreateConVar("sm_nadepractice_enabled", "1", "Whether the mode is allowed (0 = cannot be started, a running mode stops)", _, true, 0.0, true, 1.0);
    g_cvDebug          = CreateConVar("sm_nadepractice_debug", "0", "Verbose log in logs/nadepractice_debug.log", _, true, 0.0, true, 1.0);
    g_cvAutostart      = CreateConVar("sm_nadepractice_autostart", "0", "Start the mode automatically on every map", _, true, 0.0, true, 1.0);
    g_cvRestartOnStart = CreateConVar("sm_nadepractice_restart_on_start", "1", "Restart the round when the mode starts (mp_restartgame 1) so round cvars apply at once", _, true, 0.0, true, 1.0);
    g_cvTeBudget       = CreateConVar("sm_nadepractice_te_per_frame", "24", "How many temp entities (beams, rings, sprites) may be sent to one player per frame", _, true, 4.0, true, 31.0);

    g_cvInfinite      = CreateConVar("sm_nadepractice_infinite", "1", "Infinite grenades: the same grenade is given back after a throw", _, true, 0.0, true, 1.0);
    g_cvGiveOnSpawn   = CreateConVar("sm_nadepractice_give_on_spawn", "1", "Give HE, flashbang and smoke on spawn", _, true, 0.0, true, 1.0);
    g_cvBlockDamage   = CreateConVar("sm_nadepractice_block_damage", "1", "Block all damage to players", _, true, 0.0, true, 1.0);
    g_cvBlockSelfNade = CreateConVar("sm_nadepractice_block_self_nade_damage", "1", "Block damage from your own grenades (useful with block_damage 0)", _, true, 0.0, true, 1.0);

    g_cvReplayMode       = CreateConVar("sm_nadepractice_replay_mode", "1", "Throw replay: 0 = draw the saved trajectory only, 1 = real projectile", _, true, 0.0, true, 1.0);
    g_cvReplayEngineFuse = CreateConVar("sm_nadepractice_replay_engine_fuse", "0", "HE/flash replay detonation: 0 = by the plugin (effect without damage or blindness), 1 = try to start the engine timer (experimental)", _, true, 0.0, true, 1.0);
    g_cvReplayVisibleAll = CreateConVar("sm_nadepractice_replay_visible_all", "0", "Show replay projectiles to all players, not only the owner", _, true, 0.0, true, 1.0);
    g_cvReplayCooldown   = CreateConVar("sm_nadepractice_replay_cooldown", "0.5", "Minimum interval between replays of one player, seconds", _, true, 0.0, true, 10.0);
    g_cvReplaySmokeTime  = CreateConVar("sm_nadepractice_replay_smoke_time", "18.0", "How many seconds a replay smoke lasts", _, true, 2.0, true, 30.0);

    g_cvSimGravity    = CreateConVar("sm_nadepractice_sim_gravity", "0.4", "sv_gravity multiplier for grenades", _, true, 0.0, true, 5.0);
    g_cvSimElasticity = CreateConVar("sm_nadepractice_sim_elasticity", "0.45", "Grenade elasticity (fraction of speed kept after a bounce)", _, true, 0.0, true, 0.9);
    g_cvSimFriction   = CreateConVar("sm_nadepractice_sim_friction", "0.2", "Grenade friction (set on replay projectiles; not used by the flight model)", _, true, 0.0, true, 10.0);
    g_cvSimFuse       = CreateConVar("sm_nadepractice_sim_fuse", "1.5", "Fuse time of HE and flashbang, seconds", _, true, 0.1, true, 10.0);
    g_cvSimSmokeFuse  = CreateConVar("sm_nadepractice_sim_smoke_fuse", "1.5", "Minimum time before a smoke pops, seconds (after that, when the grenade stops)", _, true, 0.1, true, 10.0);
    g_cvSimThink      = CreateConVar("sm_nadepractice_sim_think", "0.2", "Engine detonation check interval, seconds (0 = exactly at the fuse time)", _, true, 0.0, true, 1.0);

    g_cvTraceCount    = CreateConVar("sm_nadepractice_trace_count", "5", "How many recent trajectories to keep and show per player", _, true, 1.0, true, float(MAX_TRAJ));
    g_cvTraceSample   = CreateConVar("sm_nadepractice_trace_sample", "0.05", "Trajectory sampling step, seconds (bounces are always recorded)", _, true, 0.015, true, 0.5);
    g_cvTraceRedraw   = CreateConVar("sm_nadepractice_trace_redraw", "2.0", "Redraw period of saved trajectories, seconds", _, true, 0.5, true, 20.0);
    g_cvTraceMaxSeg   = CreateConVar("sm_nadepractice_trace_max_segments", "24", "Maximum segments per drawn trajectory (bounces are never skipped)", _, true, 4.0, true, 128.0);
    g_cvTraceWidth    = CreateConVar("sm_nadepractice_trace_width", "1.5", "Trajectory line width", _, true, 0.5, true, 10.0);
    g_cvTraceMaxTime  = CreateConVar("sm_nadepractice_trace_max_time", "12.0", "Maximum recording time of one projectile, seconds", _, true, 2.0, true, 60.0);
    g_cvTraceBounceDv = CreateConVar("sm_nadepractice_trace_bounce_dv", "25.0", "Bounce detection: velocity change per tick beyond gravity, units/s", _, true, 1.0, true, 500.0);

    g_cvEditAccess = CreateConVar("sm_nadepractice_edit_access", "0", "Who may change the lineup database: 0 = all players, 1 = admins only (override sm_nadepractice_edit, generic flag by default)", _, true, 0.0, true, 1.0);

    g_cvHintInterval  = CreateConVar("sm_nadepractice_hint_interval", "0.25", "Hint update period, seconds", _, true, 0.05, true, 2.0);
    g_cvHintPosRadius = CreateConVar("sm_nadepractice_hint_pos_radius", "6.0", "Position tolerance, horizontal units", _, true, 1.0, true, 64.0);
    g_cvHintAngleTol  = CreateConVar("sm_nadepractice_hint_angle_tolerance", "0.5", "Aim tolerance, degrees", _, true, 0.05, true, 10.0);
    g_cvHintMode      = CreateConVar("sm_nadepractice_hint_mode", "0", "Hint output: 0 = KeyHintText (right panel), 1 = HintText, 2 = HUD text (colored)", _, true, 0.0, true, 2.0);
    g_cvHintUnicode   = CreateConVar("sm_nadepractice_hint_unicode", "1", "Arrows in hints: 1 = unicode, 0 = ASCII", _, true, 0.0, true, 1.0);
    g_cvHintLookDist  = CreateConVar("sm_nadepractice_hint_look_distance", "300.0", "Distance from the eyes of the aim marker (closer if a wall is in the way)", _, true, 32.0, true, 4000.0);

    g_cvPrevDefault    = CreateConVar("sm_nadepractice_preview_default", "1", "Trajectory preview is on for players by default", _, true, 0.0, true, 1.0);
    g_cvPrevInterval   = CreateConVar("sm_nadepractice_preview_interval", "0.1", "Preview update period, seconds", _, true, 0.05, true, 1.0);
    g_cvPrevMaxSeg     = CreateConVar("sm_nadepractice_preview_max_segments", "14", "Maximum segments of the preview line", _, true, 4.0, true, 28.0);
    g_cvSimMaxSteps    = CreateConVar("sm_nadepractice_sim_max_steps", "400", "Maximum model steps per simulation", _, true, 20.0, true, 2000.0);
    g_cvSimMaxBounces  = CreateConVar("sm_nadepractice_sim_max_bounces", "20", "Maximum bounces in the model", _, true, 1.0, true, 100.0);
    g_cvSimTickMult    = CreateConVar("sm_nadepractice_sim_tick_mult", "1", "Model step in server ticks (1 = most accurate, more = cheaper)", _, true, 1.0, true, 8.0);
    g_cvSimStopSpeed   = CreateConVar("sm_nadepractice_sim_stop_speed", "30.0", "Speed after a bounce below which the grenade stops", _, true, 0.0, true, 200.0);
    g_cvSimThrowMax    = CreateConVar("sm_nadepractice_sim_throw_speed_max", "750.0", "Maximum initial throw speed", _, true, 100.0, true, 3000.0);
    g_cvSimThrowFactor = CreateConVar("sm_nadepractice_sim_throw_speed_factor", "6.0", "Throw speed = (90 - angle) * factor", _, true, 0.1, true, 50.0);
    g_cvSimPitchOffset = CreateConVar("sm_nadepractice_sim_throw_pitch_offset", "-10.0", "Throw pitch offset when looking at the horizon, degrees (negative = up)", _, true, -45.0, true, 45.0);
    g_cvSimForward     = CreateConVar("sm_nadepractice_sim_throw_forward", "16.0", "How many units in front of the eyes the projectile appears", _, true, 0.0, true, 64.0);
    g_cvSimHull        = CreateConVar("sm_nadepractice_sim_hull", "2.0", "Half size of the projectile for collision traces", _, true, 0.5, true, 16.0);
    g_cvSimPlayerVel   = CreateConVar("sm_nadepractice_sim_player_velocity", "1.0", "Fraction of the player velocity added to the throw", _, true, 0.0, true, 2.0);

    AutoExecConfig(true, "nadepractice");

    g_cvGravity = FindConVar("sv_gravity");
    g_cvEnabled.AddChangeHook(OnEnabledChanged);

    g_SavedCvars = new StringMap();
    g_MissingPhrases = new StringMap();
    g_ReplayEnts = new ArrayList(sizeof(ReplayEnt));
    g_ReplayEffects = new ArrayList();
    g_Tracked = new ArrayList(sizeof(Tracked));
    g_Lineups = new ArrayList(sizeof(Lineup));
    g_SimPath = new ArrayList(4);
    BuildPath(Path_SM, g_DebugLogPath, sizeof(g_DebugLogPath), "logs/nadepractice_debug.log");

    RegAdminCmd("sm_nadepractice_start", Command_Start, ADMFLAG_CHANGEMAP, "Start the grenade practice mode");
    RegAdminCmd("sm_nadepractice_stop", Command_Stop, ADMFLAG_CHANGEMAP, "Stop the grenade practice mode");

    Practice_Init();
    Tracer_Init();
    Lineups_Init();
    Hints_Init();
    Preview_Init();

    // A mode reacts to game events in Post (ARCHITECTURE.md, section 4).
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    // Late load: process players that are already on the server.
    if (g_bLateLoad) {
        PrecacheAssets();
        Lineups_Load();
        for (int client = 1; client <= MaxClients; client++) {
            if (IsClientInGame(client)) {
                OnClientPutInServer(client);
            }
        }
    }
}

public void OnAllPluginsLoaded() {
    // Load report (ARCHITECTURE.md, section 12).
    LogMessage("[nadepractice] %s, dependencies: none", PLUGIN_VERSION);
}

public void OnMapStart() {
    PrecacheAssets();
    ResetAllState();
    Lineups_Load();
}

public void OnConfigsExecuted() {
    if (g_cvAutostart.BoolValue) {
        Mode_Start();
    }
}

public void OnMapEnd() {
    Mode_Stop(false);
    ResetAllState();
}

public void OnPluginEnd() {
    Mode_Stop(false);
}

public void OnClientPutInServer(int client) {
    ResetClientState(client);
    SDKHook(client, SDKHook_OnTakeDamage, Practice_OnTakeDamage);
}

public void OnClientDisconnect(int client) {
    ResetClientState(client);
}

public void OnEntityCreated(int entity, const char[] classname) {
    Throws_OnEntityCreated(entity, classname);
}

public void OnEntityDestroyed(int entity) {
    if (g_bActive) {
        Tracer_OnEntityDestroyed(entity);
    }
    Throws_OnEntityDestroyed(entity);
}

public void OnGameFrame() {
    if (!g_bActive) {
        return;
    }
    float now = GetGameTime();
    Replay_Frame(now);
    Tracer_Frame(now);

    for (int client = 1; client <= MaxClients; client++) {
        if (!IsClientInGame(client) || IsFakeClient(client)) {
            continue;
        }
        // Order = priority in the per-frame temp entity budget.
        Preview_Frame(client, now);
        Hints_Frame(client, now);
        Tracer_DrawClient(client, now);
    }
}

void PrecacheAssets() {
    // CSS-VERIFY: these materials exist in CS:S and beams/rings/sprites are drawn.
    g_BeamSprite = PrecacheModel("materials/sprites/laser.vmt", true);
    g_HaloSprite = PrecacheModel("materials/sprites/halo01.vmt", true);
    g_GlowSprite = PrecacheModel("materials/sprites/glow01.vmt", true);
    g_ExplosionSprite = PrecacheModel("sprites/zerogxplode.spr", true);
    PrecacheSound(REPLAY_FLASH_SOUND, true);
    PrecacheSound(REPLAY_SMOKE_SOUND, true);
}

void ResetClientState(int client) {
    g_bNoclip[client] = false;
    g_bNoFlash[client] = false;
    g_LastThrow[client].valid = false;
    g_LastThrow[client].hasProj = false;
    g_LastThrow[client].hasDetonation = false;
    g_LastThrow[client].pathCount = 0;
    g_PendingThrowRef[client] = 0;
    g_NextReplay[client] = 0.0;
    g_TeTick[client] = 0;
    g_TeLeft[client] = 0;
    g_MenuFilter[client] = NADE_NONE;
    g_MenuLineup[client] = 0;
    g_bMenuFromPractice[client] = false;
    g_PracticeMenuPos[client] = 0;
    g_ListMenuPos[client] = 0;
    Tracer_ResetClient(client);
    Hints_ResetClient(client);
    Preview_ResetClient(client);
}

// State must not survive a map change.
void ResetAllState() {
    for (int client = 1; client <= MaxClients; client++) {
        ResetClientState(client);
    }
    for (int i = 0; i <= MAX_EDICTS; i++) {
        g_bProjectileEnt[i] = false;
        g_ReplayOwner[i] = 0;
    }
    g_ReplayEnts.Clear();
    g_ReplayEffects.Clear();
    g_bReplaySpawning = false;
    g_Tracked.Clear();
}

// ---------------------------------------------------------------------------
// Mode start and stop
// ---------------------------------------------------------------------------

bool Mode_Start() {
    if (g_bActive || !g_cvEnabled.BoolValue) {
        return false;
    }
    g_bActive = true;

    // Temporary cvars of the mode. All of them are restored in Mode_Stop.
    // CSS-VERIFY: each of these cvars exists in CS:S and works as described in the README.
    SetCvarTemporarily("mp_freezetime", "0");
    SetCvarTemporarily("mp_roundtime", "9");
    SetCvarTemporarily("mp_ignore_round_win_conditions", "1");
    SetCvarTemporarily("mp_timelimit", "0");
    SetCvarTemporarily("mp_maxrounds", "0");
    SetCvarTemporarily("mp_winlimit", "0");
    SetCvarTemporarily("mp_fraglimit", "0");
    SetCvarTemporarily("mp_buytime", "9999");
    SetCvarTemporarily("mp_startmoney", "16000");
    SetCvarTemporarily("mp_limitteams", "0");
    SetCvarTemporarily("mp_autoteambalance", "0");
    SetCvarTemporarily("bot_quota", "0");

    LogDebug("mode start");

    for (int client = 1; client <= MaxClients; client++) {
        if (IsHuman(client)) {
            Practice_Equip(client);
        }
    }

    if (g_cvRestartOnStart.BoolValue) {
        // mp_restartgame is a one-shot cvar that resets itself to 0; not saved.
        ConVar restart = FindConVar("mp_restartgame");
        if (restart != null) {
            restart.SetInt(1);
        }
    }

    PrintToChatAll(CHAT_PREFIX ... "%t", "Mode Started");
    return true;
}

// announce = false: silent stop (map change, unload).
void Mode_Stop(bool announce) {
    if (!g_bActive) {
        return;
    }
    g_bActive = false;

    Practice_Stop();
    Replay_Stop();
    g_Tracked.Clear();
    for (int client = 1; client <= MaxClients; client++) {
        Tracer_ClearClient(client);
        if (IsClientInGame(client)) {
            Hints_Deselect(client);
        }
    }
    RestoreCvars();
    LogDebug("mode stop (announce=%d)", announce);

    if (announce) {
        PrintToChatAll(CHAT_PREFIX ... "%t", "Mode Stopped");
    }
}

public void OnEnabledChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
    if (!convar.BoolValue) {
        Mode_Stop(true);
    }
}

public Action Command_Start(int client, int args) {
    if (!g_cvEnabled.BoolValue) {
        ReplyToCommand(client, "[NadePractice] sm_nadepractice_enabled is 0.");
    } else if (!Mode_Start()) {
        ReplyToCommand(client, "[NadePractice] Already active.");
    }
    return Plugin_Handled;
}

public Action Command_Stop(int client, int args) {
    if (!g_bActive) {
        ReplyToCommand(client, "[NadePractice] Not active.");
    } else {
        Mode_Stop(true);
    }
    return Plugin_Handled;
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
    if (!g_bActive) {
        return;
    }
    // Equip a moment after the spawn: by then the game has handed out its own items.
    CreateTimer(0.1, Timer_Equip, event.GetInt("userid"), TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_Equip(Handle timer, int userid) {
    int client = GetClientOfUserId(userid);
    if (client != 0 && g_bActive && IsHuman(client)) {
        Practice_Equip(client);
    }
    return Plugin_Stop;
}

// ---------------------------------------------------------------------------
// Natives
// ---------------------------------------------------------------------------

public int Native_IsActive(Handle plugin, int numParams) {
    return g_bActive;
}

public int Native_GetApiVersion(Handle plugin, int numParams) {
    return NADEPRACTICE_API_VERSION;
}
