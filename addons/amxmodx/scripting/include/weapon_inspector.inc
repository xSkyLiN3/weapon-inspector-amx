#if defined _weapon_inspector_included
    #endinput
#endif
#define _weapon_inspector_included

/*
 * Weapon Inspector - Developer Include
 * -----------------------------------
 *
 * This include exposes the public API for the Weapon Inspector plugin.
 *
 * Notes:
 * - All functions are server-side.
 * - The plugin is safe to call even if a weapon model does not support inspect;
 *   it will return false / do nothing.
 * - "force" means: bypass cooldown / rate-limit checks, but still respects
 *   safety rules (alive, not scoped, not reloading/deploying/attacking, etc.).
 *
 * Library name:
 *   "weapon_inspector"
 *
 * To use:
 *   #include <weapon_inspector>
 */

// ========================================================================
//  NATIVES
// ========================================================================

/**
 * Returns whether the player is currently inspecting.
 *
 * @param id            Player index (1..32).
 * @return              true if inspecting, false otherwise.
 */
native bool:wi_is_inspecting( const id );

/**
 * Tries to start an inspect for the player, bypassing cooldown and rate limiting.
 * Still respects safety conditions (alive, not scoped, not attacking, etc.).
 *
 * Typical usage:
 * - Admin commands / special rewards
 * - Testing and debugging
 *
 * @param id            Player index (1..32).
 * @return              true if inspect started, false otherwise.
 */
native bool:wi_force_inspect( const id );

/**
 * Blocks inspecting for a period of time (seconds).
 *
 * If the player is currently inspecting, the plugin will cancel inspect softly
 * and restore an idle animation to return to a natural state.
 *
 * Typical usage:
 * - Minigames / special events
 * - Menu interactions where you do not want inspect to interfere
 *
 * @param id            Player index (1..32).
 * @param duration      Block time in seconds (>= 0.0).
 * @return              1 on success, 0 on invalid player.
 */
native wi_block_inspect( const id, const Float:duration );

/**
 * Returns remaining inspect time (seconds).
 *
 * @param id            Player index (1..32).
 * @return              Remaining time if inspecting, otherwise 0.0.
 */
native Float:wi_get_inspect_timeleft( const id );

// ========================================================================
//  FORWARDS
// ========================================================================

/**
 * Called before inspect starts.
 *
 * You can block inspect by returning PLUGIN_HANDLED or higher.
 * (The plugin uses ET_STOP for this forward.)
 *
 * @param id            Player index.
 * @param weapon        Active weapon entity.
 * @param seq           Selected inspect sequence index.
 * @return              PLUGIN_CONTINUE to allow, PLUGIN_HANDLED+ to block.
 */
forward wi_inspect_start_pre( const id, const weapon, const seq );

/**
 * Called when inspect starts (after it is actually launched).
 *
 * @param id            Player index.
 * @param weapon        Active weapon entity.
 * @param seq           Selected inspect sequence index.
 */
forward wi_inspect_start( const id, const weapon, const seq );

/**
 * Called when inspect ends (naturally or cancelled).
 *
 * @param id            Player index.
 */
forward wi_inspect_end( const id );
