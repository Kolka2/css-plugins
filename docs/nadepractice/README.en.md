# nadepractice — grenade practice mode for CS:S

Русская версия: [README.md](README.md)

A SourceMod 1.12 plugin for Counter-Strike: Source: infinite grenades with no damage, a tracer for real throws, a per-map lineup database, "where to stand / where to aim" hints, throw replay and a trajectory preview before the throw. Everything drawn is visible to its owner only, so several players can practise at once.

> **Status.** The code compiles without warnings but has never been run on a server: no CS:S server was available during development. Everything that depends on engine behaviour is marked `CSS-VERIFY` in the code and listed in [TEST_CHECKLIST.md](TEST_CHECKLIST.md). Treat in-game behaviour as unverified until the checklist is done.

- Layer (per `ARCHITECTURE.md`): **mode**. No dependencies, no gamedata/DHooks, no third-party libraries.
- Owns (while active): players' money, grenades and damage, the bot count (`bot_quota 0`), its temporary cvars, the lineup database.

## Installation

1. `build/nadepractice.smx` → `addons/sourcemod/plugins/`
2. `translations/nadepractice.phrases.txt` → `addons/sourcemod/translations/`, `translations/ru/nadepractice.phrases.txt` → `addons/sourcemod/translations/ru/`
3. Reload the map. `cfg/sourcemod/nadepractice.cfg` is generated.
4. Start the mode with `sm_nadepractice_start` (admin, changemap flag) or set `sm_nadepractice_autostart 1`.

The plugin creates `addons/sourcemod/configs/nadepractice/lineups/` on the first `!save`.

## What the mode changes

Temporary cvars are set on start and restored on stop (command, map change, plugin unload, `sm_nadepractice_enabled 0`): `mp_freezetime 0`, `mp_roundtime 9`, `mp_ignore_round_win_conditions 1`, `mp_timelimit 0`, `mp_maxrounds 0`, `mp_winlimit 0`, `mp_fraglimit 0`, `mp_buytime 9999`, `mp_startmoney 16000`, `mp_limitteams 0`, `mp_autoteambalance 0`, `bot_quota 0`. `sv_cheats` is not touched.

## Player commands

| Command | Action |
|---|---|
| `!practice`, `!nadepractice` | main menu |
| `!noclip` | toggle noclip |
| `!back` | return to the position and angles of the last throw |
| `!last` | replay the last throw |
| `!clear` | clear your trajectories |
| `!tracer` | toggle the throw tracer |
| `!preview` | toggle the trajectory preview while holding a grenade |
| `!preverror` | preview accuracy for the session |
| `!noflash` | toggle flash immunity |
| `!hints` | toggle hints for the selected lineup |
| `!save <name>` | save the last throw as a lineup (after it detonates) |
| `!lineups` | lineup menu: by grenade type, nearest first |
| `!goto <name>` | teleport to the lineup, equip the grenade, show hints |
| `!show <name>` | replay the lineup throw |
| `!delete [name]` | delete a lineup (no name: the selected one) |
| `!rename <new name>` | rename the selected lineup |
| `!desc <text>` | set the description of the selected lineup |

A partial name works in `!goto`, `!show`, `!delete` when it matches exactly one lineup.

Admin commands: `sm_nadepractice_start`, `sm_nadepractice_stop` (changemap flag).

## Cvars

| Cvar | Default | Description |
|---|---|---|
| `sm_nadepractice_version` | 0.1.0 | Plugin version |
| `sm_nadepractice_enabled` | 1 | Mode allowed (0: cannot be started, a running mode stops) |
| `sm_nadepractice_debug` | 0 | Verbose log to logs/nadepractice_debug.log |
| `sm_nadepractice_autostart` | 0 | Start the mode automatically on every map |
| `sm_nadepractice_restart_on_start` | 1 | Restart the round (mp_restartgame 1) when the mode starts |
| `sm_nadepractice_te_per_frame` | 24 | Temp entities (beams, rings, sprites) sent to one player per frame |
| `sm_nadepractice_infinite` | 1 | Infinite grenades: the same grenade is given back after a throw |
| `sm_nadepractice_give_on_spawn` | 1 | Give HE, flash and smoke on spawn |
| `sm_nadepractice_block_damage` | 1 | Block all damage to players |
| `sm_nadepractice_block_self_nade_damage` | 1 | Block damage from own grenades (matters when block_damage is 0) |
| `sm_nadepractice_replay_mode` | 1 | Throw replay: 0 = draw the saved trajectory only, 1 = real projectile |
| `sm_nadepractice_replay_engine_fuse` | 0 | HE/flash replay detonation: 0 = by the plugin (effect only), 1 = try the engine think (experimental) |
| `sm_nadepractice_replay_visible_all` | 0 | Show replay projectiles to everyone instead of the owner only |
| `sm_nadepractice_replay_cooldown` | 0.5 | Minimum interval between replays per player, s |
| `sm_nadepractice_replay_smoke_time` | 18.0 | Lifetime of a replay smoke cloud, s |
| `sm_nadepractice_sim_gravity` | 0.4 | sv_gravity multiplier for a grenade |
| `sm_nadepractice_sim_elasticity` | 0.45 | Grenade elasticity (speed kept after a bounce) |
| `sm_nadepractice_sim_friction` | 0.2 | Grenade friction (set on replay projectiles; unused by the flight model) |
| `sm_nadepractice_sim_fuse` | 1.5 | HE and flash fuse time, s |
| `sm_nadepractice_sim_smoke_fuse` | 1.5 | Minimum time before a smoke pops, s (then: when it stops) |
| `sm_nadepractice_sim_think` | 0.2 | Engine fuse check step, s (0 = detonate exactly on the fuse) |
| `sm_nadepractice_trace_count` | 5 | How many last trajectories are kept and shown per player |
| `sm_nadepractice_trace_sample` | 0.05 | Trajectory sampling step, s (bounces are always recorded) |
| `sm_nadepractice_trace_redraw` | 2.0 | Redraw period of stored trajectories, s |
| `sm_nadepractice_trace_max_segments` | 24 | Max beam segments per trajectory (bounces are never skipped) |
| `sm_nadepractice_trace_width` | 1.5 | Trajectory line width |
| `sm_nadepractice_trace_max_time` | 12.0 | Max seconds one projectile is recorded |
| `sm_nadepractice_trace_bounce_dv` | 25.0 | Bounce = per-tick velocity change beyond gravity, units/s |
| `sm_nadepractice_edit_access` | 0 | Who may change the lineup database: 0 = everyone, 1 = admins (access sm_nadepractice_edit, generic flag by default) |
| `sm_nadepractice_hint_interval` | 0.25 | Hint refresh period, s |
| `sm_nadepractice_hint_pos_radius` | 6.0 | Position tolerance, horizontal units |
| `sm_nadepractice_hint_angle_tolerance` | 0.5 | Aim tolerance, degrees |
| `sm_nadepractice_hint_mode` | 0 | Hint output: 0 = KeyHintText (right panel), 1 = HintText, 2 = HUD text (coloured) |
| `sm_nadepractice_hint_unicode` | 1 | Arrows: 1 = Unicode, 0 = ASCII |
| `sm_nadepractice_hint_look_distance` | 300.0 | Distance from the eyes to the "look here" marker (closer if a wall is in the way) |
| `sm_nadepractice_preview_default` | 1 | Trajectory preview is on by default |
| `sm_nadepractice_preview_interval` | 0.1 | Preview refresh period, s |
| `sm_nadepractice_preview_max_segments` | 14 | Max segments of the preview line |
| `sm_nadepractice_sim_max_steps` | 400 | Max model steps per run |
| `sm_nadepractice_sim_max_bounces` | 20 | Max bounces in the model |
| `sm_nadepractice_sim_tick_mult` | 1 | Model step in server ticks (1 = most accurate) |
| `sm_nadepractice_sim_stop_speed` | 30.0 | Speed after a bounce below which the grenade stops |
| `sm_nadepractice_sim_throw_speed_max` | 750.0 | Max initial throw speed |
| `sm_nadepractice_sim_throw_speed_factor` | 6.0 | Throw speed = (90 - pitch) * factor |
| `sm_nadepractice_sim_throw_pitch_offset` | -10.0 | Throw pitch lift relative to a level view, degrees (negative = up) |
| `sm_nadepractice_sim_throw_forward` | 16.0 | How far in front of the eyes the projectile spawns |
| `sm_nadepractice_sim_hull` | 2.0 | Half-size of the projectile hull for collision traces |
| `sm_nadepractice_sim_player_velocity` | 1.0 | Fraction of the player velocity added to the throw |

The `sm_nadepractice_sim_*` cvars are the physical constants of the flight model; tune them on the server using `!preverror` and the debug log.

## Lineup file

`addons/sourcemod/configs/nadepractice/lineups/<map>.cfg`, KeyValues. The file is rewritten on every change; section numbers carry no meaning.

```
"Lineups"
{
    "1"
    {
        "name"                 "xbox smoke"
        "type"                 "smoke"            // he | flash | smoke
        "throw"                "jump"             // stand | crouch | jump | run | runjump
        "origin"               "-300.0 1200.5 64.03"   // player position (feet) at the throw
        "angles"               "-12.4 87.3 0.0"        // view angles: pitch yaw roll
        "eye"                  "-300.0 1200.5 128.03"  // eye position at the throw
        "has_projectile"       "1"
        "projectile_origin"    "..."              // initial projectile position
        "projectile_velocity"  "..."              // initial projectile velocity
        "has_detonation"       "1"
        "detonation"           "..."              // detonation point
        "author"               "player name"
        "description"          "free text"
        "path"                                    // simplified trajectory, up to 32 points
        {
            "0"    "x y z"
            "1"    "x y z"
        }
    }
}
```

The throw type is detected when the projectile spawns: airborne = jump, on the ground and ducked = crouch, horizontal speed above 60 = running.

## API

`scripting/include/nadepractice.inc`, library `nadepractice`, API version 1: `Nadepractice_IsActive()`, `Nadepractice_GetApiVersion()`.

## Known limitations

- **Replay without gamedata.** The plugin cannot trigger the stock detonation of a projectile it created. Replayed HE and flash grenades "detonate" as an effect and a sound with no damage or blindness; the replay smoke cloud is spawned by the plugin. Flight and bounces are computed by the engine.
- The replay smoke cloud is visible to everyone; the replay projectile only to its owner.
- Real throws affect everyone: flashes blind nearby players (each can enable `!noflash`), smoke blocks vision.
- The preview model is approximate: the CS:S grenade source is not in the public SDK; players, moving objects and breakable glass are ignored.
- Running lineups store the position where the grenade left the hand, not where the run started.
- Cleared trajectories fade within about 2 s, not instantly.
- While the mode is active `!noclip` is intercepted before the funcommands admin command.
- `!save`, `!goto`, `!show`, `!delete`, `!back`, `!last`, `!clear` may clash with third-party plugins.
- A green "ready" text exists only in `hint_mode 2`; otherwise the ground ring turns green and a READY line appears.

## Build

`./build.sh` compiles `scripting/*.sp` into `build/`. A warning fails the build.
