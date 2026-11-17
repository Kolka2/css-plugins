/*
 * nadepractice — режим тренировки раскидки гранат для CS:S.
 *
 * Слой:        режим
 * Владеет:     состоянием тренировки каждого игрока (noclip, последний бросок,
 *              трассеры, выбранный лайнап), базой лайнапов
 *              (configs/nadepractice/lineups/<map>.cfg), деньгами, гранатами и
 *              уроном игроков, пока режим активен, числом ботов (bot_quota 0),
 *              своими временными кварами (список — в Mode_Start).
 * Читает:      события игры (player_spawn, *_detonate, player_blind), sv_gravity.
 * Использует:  ничего (интеграция с warmup — позже).
 * API:         include/nadepractice.inc
 *
 * Части (scripting/nadepractice/):
 *   util.sp     — лог, временные квары, проверки клиентов, отрисовка, сообщения
 *   throws.sp   — обнаружение бросков и снимок «последнего броска»
 *   replay.sp   — повтор броска (создание снаряда и его детонация)
 *   practice.sp — бесконечные гранаты, урон, команды игрока, главное меню
 *   tracer.sp   — запись и отрисовка траекторий реальных бросков
 *   lineups.sp  — база лайнапов: файл, команды, меню
 *   hints.sp    — подсказки по выбранному лайнапу
 *   preview.sp  — модель полёта, предпросмотр до броска и сверка с фактом
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
    description = "Режим тренировки раскидки гранат",
    version     = PLUGIN_VERSION,
    url         = ""
};

// ---------------------------------------------------------------------------
// Константы
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

// Точки траектории: обычная, отскок, детонация.
#define PT_NORMAL   0
#define PT_BOUNCE   1
#define PT_DETONATE 2

#define MAX_EDICTS       2048
#define MAX_PATH_POINTS  32     // точек упрощённой траектории в лайнапе
#define MAX_TRAJ         10     // предел sm_nadepractice_trace_count
#define MAX_TRAJ_POINTS  256    // точек в одной записанной траектории
#define RUN_SPEED        60.0   // горизонтальная скорость, с которой бросок считается «с бега»

char g_NadeWeapon[NADE_COUNT][] = { "weapon_hegrenade", "weapon_flashbang", "weapon_smokegrenade" };
char g_NadeProjectile[NADE_COUNT][] = { "hegrenade_projectile", "flashbang_projectile", "smokegrenade_projectile" };
char g_NadeKey[NADE_COUNT][] = { "he", "flash", "smoke" };
char g_NadePhrase[NADE_COUNT][] = { "Nade HE", "Nade Flash", "Nade Smoke" };
int g_NadeColor[NADE_COUNT][4] = { { 255, 70, 50, 255 }, { 90, 170, 255, 255 }, { 70, 255, 100, 255 } };

char g_ThrowKey[THROW_COUNT][] = { "stand", "crouch", "jump", "run", "runjump" };
char g_ThrowPhrase[THROW_COUNT][] = { "Throw Stand", "Throw Crouch", "Throw Jump", "Throw Run", "Throw RunJump" };

// ---------------------------------------------------------------------------
// Типы
// ---------------------------------------------------------------------------

// Снимок броска: состояние игрока в момент появления снаряда и сам снаряд.
enum struct ThrowInfo {
    bool valid;
    int serial;             // уникальный номер броска
    int nade;
    float origin[3];        // позиция игрока (ноги)
    float eye[3];           // позиция глаз
    float angles[3];        // углы взгляда
    float velocity[3];      // скорость игрока
    int buttons;
    int flags;
    int throwType;
    bool hasProj;
    float projOrigin[3];    // начальная позиция снаряда
    float projVelocity[3];  // начальная скорость снаряда
    bool hasDetonation;
    float detonation[3];
    int pathCount;
    float path[MAX_PATH_POINTS * 3];
}

// Снаряд повтора, которым управляет плагин.
enum struct ReplayEnt {
    int ref;
    int userid;
    int nade;
    float detonateAt;
    float nextCheck;
    float killAt;
}

// Снаряд, за которым следит трассер.
enum struct Tracked {
    int ref;
    int userid;
    int nade;
    int slot;               // слот траектории владельца
    int serial;             // номер траектории (слот мог быть перезаписан)
    int throwSerial;        // номер броска в g_LastThrow или 0 (повтор)
    bool replay;
    float spawnTime;
    float nextSample;
    float lastPos[3];
    float lastPoint[3];     // последняя записанная точка
    float lastVel[3];
    bool hasVel;
    bool hasPrediction;
    float predicted[3];     // где модель ждёт детонацию
}

// Лайнап из базы.
enum struct Lineup {
    int id;                 // номер на время карты (в файл не пишется)
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
// Глобальные переменные
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

// физика гранаты (общая для повтора и модели предпросмотра)
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

// preview и модель полёта
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

ConVar g_cvGravity;     // sv_gravity (только чтение)

StringMap g_SavedCvars;
char g_DebugLogPath[PLATFORM_MAX_PATH];

bool g_bActive;
bool g_bLateLoad;

int g_BeamSprite = -1;
int g_HaloSprite = -1;
int g_GlowSprite = -1;
int g_ExplosionSprite = -1;

// бюджет временных сущностей на кадр
int g_TeTick[MAXPLAYERS + 1];
int g_TeLeft[MAXPLAYERS + 1];

// состояние игрока
bool g_bNoclip[MAXPLAYERS + 1];
bool g_bNoFlash[MAXPLAYERS + 1];
ThrowInfo g_LastThrow[MAXPLAYERS + 1];
int g_PendingThrowRef[MAXPLAYERS + 1];
float g_NextReplay[MAXPLAYERS + 1];

// броски
int g_ThrowSerial;
bool g_bProjectileEnt[MAX_EDICTS + 1];
bool g_bLoggedMissingProp;

// повтор
bool g_bReplaySpawning;
int g_ReplayOwner[MAX_EDICTS + 1];
ArrayList g_ReplayEnts;
ArrayList g_ReplayEffects;

// трассер
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

// лайнапы
ArrayList g_Lineups;
int g_NextLineupId = 1;
char g_LineupsFile[PLATFORM_MAX_PATH];
int g_MenuFilter[MAXPLAYERS + 1];
int g_MenuLineup[MAXPLAYERS + 1];

// подсказки
Handle g_HudSync;
bool g_bHints[MAXPLAYERS + 1];
int g_SelectedLineup[MAXPLAYERS + 1];
float g_NextHint[MAXPLAYERS + 1];
float g_NextHintDraw[MAXPLAYERS + 1];
bool g_bHintShown[MAXPLAYERS + 1];
float g_HintGround[MAXPLAYERS + 1][3];
float g_HintMarker[MAXPLAYERS + 1][3];

// предпросмотр и сверка
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
// Загрузка
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

    CreateConVar("sm_nadepractice_version", PLUGIN_VERSION, "Версия плагина", FCVAR_NOTIFY | FCVAR_DONTRECORD);
    g_cvEnabled        = CreateConVar("sm_nadepractice_enabled", "1", "Разрешён ли режим (0 — режим нельзя запустить, запущенный останавливается)", _, true, 0.0, true, 1.0);
    g_cvDebug          = CreateConVar("sm_nadepractice_debug", "0", "Подробный лог в logs/nadepractice_debug.log", _, true, 0.0, true, 1.0);
    g_cvAutostart      = CreateConVar("sm_nadepractice_autostart", "0", "Запускать режим автоматически на каждой карте", _, true, 0.0, true, 1.0);
    g_cvRestartOnStart = CreateConVar("sm_nadepractice_restart_on_start", "1", "При запуске режима перезапускать раунд (mp_restartgame 1), чтобы квары раунда применились сразу", _, true, 0.0, true, 1.0);
    g_cvTeBudget       = CreateConVar("sm_nadepractice_te_per_frame", "24", "Сколько временных сущностей (лучи, кольца, спрайты) можно отправить одному игроку за кадр", _, true, 4.0, true, 31.0);

    g_cvInfinite      = CreateConVar("sm_nadepractice_infinite", "1", "Бесконечные гранаты: после броска выдаётся такая же", _, true, 0.0, true, 1.0);
    g_cvGiveOnSpawn   = CreateConVar("sm_nadepractice_give_on_spawn", "1", "Выдавать HE, флешку и дым при появлении", _, true, 0.0, true, 1.0);
    g_cvBlockDamage   = CreateConVar("sm_nadepractice_block_damage", "1", "Блокировать любой урон игрокам", _, true, 0.0, true, 1.0);
    g_cvBlockSelfNade = CreateConVar("sm_nadepractice_block_self_nade_damage", "1", "Блокировать урон от своих гранат (имеет смысл при block_damage 0)", _, true, 0.0, true, 1.0);

    g_cvReplayMode       = CreateConVar("sm_nadepractice_replay_mode", "1", "Повтор броска: 0 — только отрисовка сохранённой траектории, 1 — настоящий снаряд", _, true, 0.0, true, 1.0);
    g_cvReplayEngineFuse = CreateConVar("sm_nadepractice_replay_engine_fuse", "0", "Детонация HE/флешки повтора: 0 — плагином (эффект без урона и ослепления), 1 — попытаться запустить таймер движка (экспериментально)", _, true, 0.0, true, 1.0);
    g_cvReplayVisibleAll = CreateConVar("sm_nadepractice_replay_visible_all", "0", "Показывать снаряды повтора всем игрокам, а не только владельцу", _, true, 0.0, true, 1.0);
    g_cvReplayCooldown   = CreateConVar("sm_nadepractice_replay_cooldown", "0.5", "Минимальный интервал между повторами одного игрока, с", _, true, 0.0, true, 10.0);
    g_cvReplaySmokeTime  = CreateConVar("sm_nadepractice_replay_smoke_time", "18.0", "Сколько секунд живёт дым повтора", _, true, 2.0, true, 30.0);

    g_cvSimGravity    = CreateConVar("sm_nadepractice_sim_gravity", "0.4", "Множитель sv_gravity для гранаты", _, true, 0.0, true, 5.0);
    g_cvSimElasticity = CreateConVar("sm_nadepractice_sim_elasticity", "0.45", "Упругость гранаты (доля скорости после отскока)", _, true, 0.0, true, 0.9);
    g_cvSimFriction   = CreateConVar("sm_nadepractice_sim_friction", "0.2", "Трение гранаты (выставляется снаряду повтора; в модели полёта не участвует)", _, true, 0.0, true, 10.0);
    g_cvSimFuse       = CreateConVar("sm_nadepractice_sim_fuse", "1.5", "Время до детонации HE и флешки, с", _, true, 0.1, true, 10.0);
    g_cvSimSmokeFuse  = CreateConVar("sm_nadepractice_sim_smoke_fuse", "1.5", "Минимальное время до срабатывания дыма, с (дальше — когда граната остановится)", _, true, 0.1, true, 10.0);
    g_cvSimThink      = CreateConVar("sm_nadepractice_sim_think", "0.2", "Шаг проверки таймера детонации в движке, с (0 — детонация ровно по таймеру)", _, true, 0.0, true, 1.0);

    g_cvTraceCount    = CreateConVar("sm_nadepractice_trace_count", "5", "Сколько последних траекторий хранить и показывать на игрока", _, true, 1.0, true, float(MAX_TRAJ));
    g_cvTraceSample   = CreateConVar("sm_nadepractice_trace_sample", "0.05", "Шаг записи точек траектории, с (отскоки записываются всегда)", _, true, 0.015, true, 0.5);
    g_cvTraceRedraw   = CreateConVar("sm_nadepractice_trace_redraw", "2.0", "Период перерисовки сохранённых траекторий, с", _, true, 0.5, true, 20.0);
    g_cvTraceMaxSeg   = CreateConVar("sm_nadepractice_trace_max_segments", "24", "Максимум отрезков на одну траекторию при отрисовке (отскоки не пропускаются)", _, true, 4.0, true, 128.0);
    g_cvTraceWidth    = CreateConVar("sm_nadepractice_trace_width", "1.5", "Толщина линии траектории", _, true, 0.5, true, 10.0);
    g_cvTraceMaxTime  = CreateConVar("sm_nadepractice_trace_max_time", "12.0", "Сколько секунд максимум записывается один снаряд", _, true, 2.0, true, 60.0);
    g_cvTraceBounceDv = CreateConVar("sm_nadepractice_trace_bounce_dv", "25.0", "Отскок: изменение скорости за тик сверх гравитации, юнитов/с", _, true, 1.0, true, 500.0);

    g_cvEditAccess = CreateConVar("sm_nadepractice_edit_access", "0", "Кто меняет базу лайнапов: 0 — все игроки, 1 — только админы (доступ sm_nadepractice_edit, по умолчанию флаг generic)", _, true, 0.0, true, 1.0);

    g_cvHintInterval  = CreateConVar("sm_nadepractice_hint_interval", "0.25", "Период обновления подсказки, с", _, true, 0.05, true, 2.0);
    g_cvHintPosRadius = CreateConVar("sm_nadepractice_hint_pos_radius", "6.0", "Допуск позиции, юнитов по горизонтали", _, true, 1.0, true, 64.0);
    g_cvHintAngleTol  = CreateConVar("sm_nadepractice_hint_angle_tolerance", "0.5", "Допуск прицела, градусов", _, true, 0.05, true, 10.0);
    g_cvHintMode      = CreateConVar("sm_nadepractice_hint_mode", "0", "Куда выводить подсказку: 0 — KeyHintText (панель справа), 1 — HintText, 2 — HUD-текст (цветной)", _, true, 0.0, true, 2.0);
    g_cvHintUnicode   = CreateConVar("sm_nadepractice_hint_unicode", "1", "Стрелки в подсказке: 1 — юникод, 0 — ASCII", _, true, 0.0, true, 1.0);
    g_cvHintLookDist  = CreateConVar("sm_nadepractice_hint_look_distance", "300.0", "На каком расстоянии от глаз ставить метку «куда смотреть» (ближе, если мешает стена)", _, true, 32.0, true, 4000.0);

    g_cvPrevDefault    = CreateConVar("sm_nadepractice_preview_default", "1", "Предпросмотр траектории включён у игрока по умолчанию", _, true, 0.0, true, 1.0);
    g_cvPrevInterval   = CreateConVar("sm_nadepractice_preview_interval", "0.1", "Период обновления предпросмотра, с", _, true, 0.05, true, 1.0);
    g_cvPrevMaxSeg     = CreateConVar("sm_nadepractice_preview_max_segments", "14", "Максимум отрезков линии предпросмотра", _, true, 4.0, true, 28.0);
    g_cvSimMaxSteps    = CreateConVar("sm_nadepractice_sim_max_steps", "400", "Максимум шагов модели на один расчёт", _, true, 20.0, true, 2000.0);
    g_cvSimMaxBounces  = CreateConVar("sm_nadepractice_sim_max_bounces", "20", "Максимум отскоков в модели", _, true, 1.0, true, 100.0);
    g_cvSimTickMult    = CreateConVar("sm_nadepractice_sim_tick_mult", "1", "Шаг модели в тиках сервера (1 — точнее, больше — дешевле)", _, true, 1.0, true, 8.0);
    g_cvSimStopSpeed   = CreateConVar("sm_nadepractice_sim_stop_speed", "30.0", "Скорость после отскока, ниже которой граната останавливается", _, true, 0.0, true, 200.0);
    g_cvSimThrowMax    = CreateConVar("sm_nadepractice_sim_throw_speed_max", "750.0", "Максимальная начальная скорость броска", _, true, 100.0, true, 3000.0);
    g_cvSimThrowFactor = CreateConVar("sm_nadepractice_sim_throw_speed_factor", "6.0", "Скорость броска = (90 - угол) * множитель", _, true, 0.1, true, 50.0);
    g_cvSimPitchOffset = CreateConVar("sm_nadepractice_sim_throw_pitch_offset", "-10.0", "Подъём броска относительно взгляда в горизонт, градусов (отрицательное — вверх)", _, true, -45.0, true, 45.0);
    g_cvSimForward     = CreateConVar("sm_nadepractice_sim_throw_forward", "16.0", "На сколько юнитов впереди глаз появляется снаряд", _, true, 0.0, true, 64.0);
    g_cvSimHull        = CreateConVar("sm_nadepractice_sim_hull", "2.0", "Половина размера снаряда для проверки столкновений", _, true, 0.5, true, 16.0);
    g_cvSimPlayerVel   = CreateConVar("sm_nadepractice_sim_player_velocity", "1.0", "Какая доля скорости игрока добавляется к броску", _, true, 0.0, true, 2.0);

    AutoExecConfig(true, "nadepractice");

    g_cvGravity = FindConVar("sv_gravity");
    g_cvEnabled.AddChangeHook(OnEnabledChanged);

    g_SavedCvars = new StringMap();
    g_ReplayEnts = new ArrayList(sizeof(ReplayEnt));
    g_ReplayEffects = new ArrayList();
    g_Tracked = new ArrayList(sizeof(Tracked));
    g_Lineups = new ArrayList(sizeof(Lineup));
    g_SimPath = new ArrayList(4);
    BuildPath(Path_SM, g_DebugLogPath, sizeof(g_DebugLogPath), "logs/nadepractice_debug.log");

    RegAdminCmd("sm_nadepractice_start", Command_Start, ADMFLAG_CHANGEMAP, "Запустить режим тренировки гранат");
    RegAdminCmd("sm_nadepractice_stop", Command_Stop, ADMFLAG_CHANGEMAP, "Остановить режим тренировки гранат");

    Practice_Init();
    Tracer_Init();
    Lineups_Init();
    Hints_Init();
    Preview_Init();

    // Режим реагирует на события игры в Post (ARCHITECTURE.md, раздел 4).
    HookEvent("player_spawn", Event_PlayerSpawn, EventHookMode_Post);

    // Поздняя загрузка: обработать игроков и снаряды, которые уже на сервере.
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
    // Отчёт при загрузке (ARCHITECTURE.md, раздел 12).
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
        // Порядок = приоритет в бюджете временных сущностей кадра.
        Preview_Frame(client, now);
        Hints_Frame(client, now);
        Tracer_DrawClient(client, now);
    }
}

void PrecacheAssets() {
    // CSS-VERIFY: эти материалы есть в CS:S и лучи/кольца/спрайты рисуются.
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
    Tracer_ResetClient(client);
    Hints_ResetClient(client);
    Preview_ResetClient(client);
}

// Состояние не должно переживать смену карты.
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
// Режим: запуск и остановка
// ---------------------------------------------------------------------------

bool Mode_Start() {
    if (g_bActive || !g_cvEnabled.BoolValue) {
        return false;
    }
    g_bActive = true;

    // Временные квары режима. Все восстанавливаются в Mode_Stop.
    // CSS-VERIFY: каждый из этих кваров существует в CS:S и действует как описано в README.
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
        // mp_restartgame — одноразовая команда-квар, сама возвращается в 0; не запоминаем.
        ConVar restart = FindConVar("mp_restartgame");
        if (restart != null) {
            restart.SetInt(1);
        }
    }

    PrintToChatAll("\x04[NadePractice]\x01 %t", "Mode Started");
    return true;
}

// announce = false — тихая остановка (смена карты, выгрузка).
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
        PrintToChatAll("\x04[NadePractice]\x01 %t", "Mode Stopped");
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
    // Выдача в следующий момент после появления: к этому времени игра уже раздала своё.
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
// Нативы
// ---------------------------------------------------------------------------

public int Native_IsActive(Handle plugin, int numParams) {
    return g_bActive;
}

public int Native_GetApiVersion(Handle plugin, int numParams) {
    return NADEPRACTICE_API_VERSION;
}
