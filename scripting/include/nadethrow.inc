#if defined _nadethrow_included
    #endinput
#endif
#define _nadethrow_included

#define NADETHROW_LIBRARY     "nadethrow"
#define NADETHROW_API_VERSION 1

/**
 * Версия API загруженного плагина (сравнивать с NADETHROW_API_VERSION).
 */
native int Nadethrow_GetApiVersion();

/**
 * Включён ли плагин (sm_nadethrow_enabled).
 *
 * Если выключен, броски не меняются, а Nadethrow_OnGrenadeThrown не вызывается.
 */
native bool Nadethrow_IsEnabled();

/**
 * Текущая сила броска игрока.
 *
 * @param client    Индекс игрока (должен быть в игре).
 * @return          0.0–1.0, пока игрок держит гранату с выдернутой чекой
 *                  (1.0 — ЛКМ, 0.5 — ЛКМ+ПКМ, 0.0 — ПКМ); иначе -1.0.
 *                  Для игроков, которых плагин не обрабатывает (боты при
 *                  sm_nadethrow_bots 0), всегда -1.0.
 * @error           Неверный индекс или игрок не в игре.
 */
native float Nadethrow_GetThrowStrength(int client);

/**
 * Доля «собственной» скорости броска при силе 0.0 (sm_nadethrow_min_scale).
 *
 * Плагин пересчитывает скорость снаряда так:
 *   k   = minScale + (1 - minScale) * strength
 *   new = (v - playerVel) * k + playerVel
 * где v — скорость снаряда, заданная игрой, playerVel — скорость игрока в момент броска.
 */
native float Nadethrow_GetMinScale();

/**
 * На сколько юнитов ниже вылетает граната при силе 0.0 (sm_nadethrow_z_offset).
 *
 * Точка вылета опускается на (1 - strength) * zOffset, если по пути нет препятствия.
 */
native float Nadethrow_GetZOffset();

/**
 * Уведомление: игрок бросил гранату. Вызывается после поправки снаряда (если она была),
 * в том числе для бросков с силой 1.0 и для ботов. Не вызывается, если плагин выключен.
 *
 * @param client        Бросивший игрок.
 * @param projectile    Индекс сущности снаряда.
 * @param strength      Сила броска 0.0–1.0 (1.0 — снаряд не менялся).
 */
forward void Nadethrow_OnGrenadeThrown(int client, int projectile, float strength);

public SharedPlugin __pl_nadethrow = {
    name = NADETHROW_LIBRARY,
    file = "nadethrow.smx",
#if defined REQUIRE_PLUGIN
    required = 1,
#else
    required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_nadethrow_SetNTVOptional() {
    MarkNativeAsOptional("Nadethrow_GetApiVersion");
    MarkNativeAsOptional("Nadethrow_IsEnabled");
    MarkNativeAsOptional("Nadethrow_GetThrowStrength");
    MarkNativeAsOptional("Nadethrow_GetMinScale");
    MarkNativeAsOptional("Nadethrow_GetZOffset");
}
#endif
