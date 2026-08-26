/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Cristobal Vergara
 */

/**
 * Weapon Inspector
 *
 * Installation and usage
 * ----------------------------------------------------------------------------
 * 1) Compile and add to plugins.ini:
 *      weapon_inspector.amxx
 *
 * 2) Config files ( auto-created in /configs ):
 *
 *    inspect_list.ini
 *        - Inspect keywords (one per line)
 *
 *    weapon_inspector_models.ini
 *        - Per-model overrides:
 *
 *            AUTO_INSPECT    = 0/1
 *            MANUAL_INSPECT  = 0/1
 *            IDLE_LOOP_TIME  = float
 *            IDLE_SEQ_FORCE  = int
 *
 * 3) Command:
 *
 *        bind "f" "inspect"
 *
 * 4) Optional impulse activation:
 *
 *        wi_impulse_mode 0/1/2
 *
 *
 * ========================================================================
 * Changelog
 * ========================================================================
 *
 * v1.0.0 — Initial Release
 * ----------------------------------------------------------------------------
 *
 * - Server-side inspect system
 * - Automatic inspect detection from model sequences
 * - Real animation duration calculation
 * - Cooldown and anti-spam protection
 * - Safe cancellation on attack, reload, deploy, zoom
 * - Silencer-aware support (USP / M4A1)
 * - Developer API (natives and forwards)
 * - Admin debug and status tools
 *
 *
 * v1.1.0 — Per-Model Rules Update
 * ----------------------------------------------------------------------------
 *
 * - Added per-model rules system (weapon_inspector_models.ini)
 * - Added AUTO_INSPECT and MANUAL_INSPECT controls
 * - Added controlled idle-loop system
 * - Added forced idle sequence support
 * - Improved idle-loop safety and engine compatibility
 * - Fixed shotgun reload compatibility (M3 / XM1014)
 *
 * v1.1.1 — Reliability and Release Update
 * ----------------------------------------------------------------------------
 *
 * - Fixed native registration style for the public API
 * - Enforced ADMIN_RCON checks on every administrative command
 * - Fixed cached Array handle leaks during configuration reloads
 * - Declared the Engine module required by client_impulse
 * - Standardized source and compiled plugin names
 *
 * v1.1.2 — Runtime and Parser Correctness Update
 * ----------------------------------------------------------------------------
 *
 * - Corrected predicted weapon timer semantics
 * - Made the master enable switch stop all runtime hooks
 * - Hardened GoldSrc Studio model parsing and INI bounds checks
 * - Preserved normal weapon behavior for unsupported viewmodels
 * - Corrected bodygroup selection and forced-inspect busy-window handling
 *
 * ========================================================================
 */

#pragma semicolon 1

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <engine>
#include <fakemeta>
#include <hamsandwich>

// ========================================================================
//  PLUGIN INFO
// ========================================================================
new const PLUGIN_NAME[ ]    = "Weapon Inspector";
new const PLUGIN_VERSION[ ] = "1.1.2";
new const PLUGIN_AUTHOR[ ]  = "Cristobal Vergara";

// ========================================================================
//  OFFSETS
// ========================================================================
const XO_WEAPON               = 4;
const XO_PLAYER               = 5;

const m_pPlayer               = 41;
const m_flNextPrimaryAttack   = 46;
const m_flNextSecondaryAttack = 47;
const m_flTimeWeaponIdle      = 48;
const m_fInSpecialReload      = 55;

const m_flNextAttack          = 83;
const m_pActiveItem           = 373;

// ========================================================================
//  CONSTANTS
// ========================================================================
#define MAX_PLAYERS           32

#define SEQ_LABEL_BYTES       32
#define SEQ_NAME_LEN          33
#define MODEL_PATH_LEN        128
#define KEYWORD_MAX_LEN       16

#define MAX_INSPECT_KEYWORDS  32
#define MAX_STUDIO_SEQUENCES  2048
#define MAX_WEAPON_ANIM_SEQ   255

#define STUDIO_MAGIC          0x54534449
#define STUDIO_VERSION        10
#define STUDIO_HEADER_SIZE    244
#define STUDIO_LENGTH_OFFSET  72
#define STUDIO_NUMSEQ_OFFSET  164
#define STUDIO_SEQDESC_SIZE   176
#define STUDIO_SEQDESC_FPS    32
#define STUDIO_SEQDESC_FRAMES 56

#define MIN_MODEL_SIZE        1024
#define MAX_MODEL_SIZE        5242880

#define IDLE_BLOCK_PAD        0.20

#define RULE_DEFAULT_AUTO            1
#define RULE_DEFAULT_MANUAL          1
#define RULE_DEFAULT_LOOP            0.0
#define RULE_DEFAULT_IDLE_SEQ_FORCE  -1

// Weapons that cannot be inspected
const WPNS_NO_INSPECT = ( 1 << CSW_C4 )
                      | ( 1 << CSW_HEGRENADE )
                      | ( 1 << CSW_FLASHBANG )
                      | ( 1 << CSW_SMOKEGRENADE );

// ========================================================================
//  SILENCER ACTION KEYWORDS (Blacklist)
// ========================================================================
new const g_szSilencerActions[ ][ ] =
{
    "add_silencer",
    "attach_silencer",
    "detach_silencer",
    "remove_silencer"
};

// ========================================================================
//  WEAPON CLASS NAMES (for Ham registration)
// ========================================================================
new const g_szWeaponClasses[ ][ ] =
{
    "weapon_p228",
    "weapon_scout",
    "weapon_xm1014",
    "weapon_mac10",
    "weapon_aug",
    "weapon_elite",
    "weapon_fiveseven",
    "weapon_ump45",
    "weapon_sg550",
    "weapon_galil",
    "weapon_famas",
    "weapon_usp",
    "weapon_glock18",
    "weapon_awp",
    "weapon_mp5navy",
    "weapon_m249",
    "weapon_m3",
    "weapon_m4a1",
    "weapon_tmp",
    "weapon_g3sg1",
    "weapon_deagle",
    "weapon_sg552",
    "weapon_ak47",
    "weapon_knife",
    "weapon_p90"
};

new const g_szWeaponScope[ ][ ] =
{
    "weapon_aug",
    "weapon_awp",
    "weapon_g3sg1",
    "weapon_scout",
    "weapon_sg550",
    "weapon_sg552"
};

// ========================================================================
//  ENUMS
// ========================================================================
enum SilencerState
{
    SIL_NONE = 0,
    SIL_ON,
    SIL_OFF
};

// ========================================================================
//  GLOBALS - Model Cache System
// ========================================================================
new Trie:g_tInspectSilenced;
new Trie:g_tInspectUnsilenced;
new Trie:g_tInspectGeneric;

new Trie:g_tIdleSilenced;
new Trie:g_tIdleUnsilenced;
new Trie:g_tIdleGeneric;

new Trie:g_tModelValidated;
new Trie:g_tModelAnalyzed;
new Trie:g_tModelSupportsInspect;
new Trie:g_tModelNumSeq;            // cache: model -> numseq

// ========================================================================
//  GLOBALS - Per-Model Rules (INI)
// ========================================================================
new Trie:g_tRuleAutoInspect;        // cell 0/1
new Trie:g_tRuleManualInspect;      // cell 0/1
new Trie:g_tRuleIdleLoopTime;       // cell floatbits
new Trie:g_tRuleIdleSeqForce;       // cell int

// ========================================================================
//  GLOBALS - Player State
// ========================================================================
new bool:g_bInspecting[ MAX_PLAYERS + 1 ];
new g_iInspectSeq[ MAX_PLAYERS + 1 ];
new Float:g_fInspectEnd[ MAX_PLAYERS + 1 ];

new Float:g_fCooldownUntil[ MAX_PLAYERS + 1 ];
new Float:g_fBusyUntil[ MAX_PLAYERS + 1 ];
new Float:g_fBlockedUntil[ MAX_PLAYERS + 1 ];

// Idle-loop throttle and explicit ownership of the weapon timer it changed.
new Float:g_fNextIdleLoop[ MAX_PLAYERS + 1 ];
new g_iIdleLoopWeapon[ MAX_PLAYERS + 1 ];

// Track last viewmodel per player to detect weapon switches
new g_szLastViewModel[ MAX_PLAYERS + 1 ][ MODEL_PATH_LEN ];

// ========================================================================
//  GLOBALS - Rate Limiting
// ========================================================================
new g_iInspectCount[ MAX_PLAYERS + 1 ];
new Float:g_fLastInspectReset[ MAX_PLAYERS + 1 ];

// ========================================================================
//  GLOBALS - Keywords
// ========================================================================
new Array:g_aInspectKeywords;
new g_iInspectKeywordCount;

// ========================================================================
//  GLOBALS - CVars
// ========================================================================
new g_pCvarEnabled;
new g_pCvarDeployCooldown;
new g_pCvarReloadCooldown;

new g_pCvarDurMin;
new g_pCvarDurMax;

new g_pCvarMaxInspectPerSec;

new g_pCvarImpulseMode;     // 0/1/2
new g_pCvarLogModels;       // 0/1
new g_pCvarAnnounce;        // 0/1 (optional message on first join)

// ========================================================================
//  GLOBALS - Announce
// ========================================================================
new bool:g_bAnnounced[ MAX_PLAYERS + 1 ];

// ========================================================================
//  FORWARDS
// ========================================================================
new g_fwdInspectStartPre;
new g_fwdInspectStart;
new g_fwdInspectEnd;

// ========================================================================
//  NATIVES
// ========================================================================
public plugin_natives( )
{
    register_library( "weapon_inspector" );

    register_native( "wi_is_inspecting",         "Native_IsInspecting" );
    register_native( "wi_force_inspect",         "Native_ForceInspect" );
    register_native( "wi_block_inspect",         "Native_BlockInspect" );
    register_native( "wi_get_inspect_timeleft",  "Native_GetInspectTimeLeft" );
}

// ========================================================================
//  PLUGIN INIT / CFG / END
// ========================================================================
public plugin_init( )
{
    register_plugin( PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR );

    // Tries
    g_tInspectSilenced      = TrieCreate( );
    g_tInspectUnsilenced    = TrieCreate( );
    g_tInspectGeneric       = TrieCreate( );

    g_tIdleSilenced         = TrieCreate( );
    g_tIdleUnsilenced       = TrieCreate( );
    g_tIdleGeneric          = TrieCreate( );

    g_tModelValidated       = TrieCreate( );
    g_tModelAnalyzed        = TrieCreate( );
    g_tModelSupportsInspect = TrieCreate( );
    g_tModelNumSeq          = TrieCreate( );

    // Rules
    g_tRuleAutoInspect      = TrieCreate( );
    g_tRuleManualInspect    = TrieCreate( );
    g_tRuleIdleLoopTime     = TrieCreate( );
    g_tRuleIdleSeqForce     = TrieCreate( );

    // Keywords
    g_aInspectKeywords = ArrayCreate( KEYWORD_MAX_LEN, 0 );
    LoadInspectKeywords( );

    // Per-model rules
    LoadModelRules( );

    // Forwards
    g_fwdInspectStartPre = CreateMultiForward( "wi_inspect_start_pre", ET_STOP,   FP_CELL, FP_CELL, FP_CELL );
    g_fwdInspectStart    = CreateMultiForward( "wi_inspect_start",     ET_IGNORE, FP_CELL, FP_CELL, FP_CELL );
    g_fwdInspectEnd      = CreateMultiForward( "wi_inspect_end",       ET_IGNORE, FP_CELL );

    // CVars
    g_pCvarEnabled          = register_cvar( "wi_enabled",          "1" );
    g_pCvarDeployCooldown   = register_cvar( "wi_deploy_cooldown",  "1.0" );
    g_pCvarReloadCooldown   = register_cvar( "wi_reload_cooldown",  "0.0" );
    g_pCvarDurMin           = register_cvar( "wi_dur_min",          "0.1" );
    g_pCvarDurMax           = register_cvar( "wi_dur_max",          "16.0" );
    g_pCvarMaxInspectPerSec = register_cvar( "wi_max_per_sec",      "3" );

    // Activation
    // 0 = disabled, 1 = impulse 100, 2 = impulse 201
    g_pCvarImpulseMode      = register_cvar( "wi_impulse_mode",     "1" );

    // Debug / support
    g_pCvarLogModels        = register_cvar( "wi_log_models",       "0" );

    // Optional announce
    g_pCvarAnnounce         = register_cvar( "wi_announce",         "0" );

    // Ham hooks
    for ( new i = 0; i < sizeof( g_szWeaponClasses ); i++ )
    {
        RegisterHam( Ham_Weapon_PrimaryAttack, g_szWeaponClasses[ i ], "HamHook_PrimaryAttack_Post", true );
        RegisterHam( Ham_Weapon_Reload,        g_szWeaponClasses[ i ], "HamHook_Reload_Post",        true );
        RegisterHam( Ham_Item_Deploy,          g_szWeaponClasses[ i ], "HamHook_Deploy_Post",        true );
    }

    for ( new i = 0; i < sizeof( g_szWeaponScope ); i++ )
    {
        RegisterHam( Ham_Weapon_SecondaryAttack, g_szWeaponScope[ i ], "HamHook_SecondaryAttack_Post", true );
    }

    // Commands
    register_concmd( "inspect", "Cmd_Inspect" );

    // PreThink monitors inspect end / interruption + idle-loop (rules)
    register_forward( FM_PlayerPreThink, "FMHook_PreThink" );

    // Admin
    register_concmd( "wi_status",        "Cmd_Status",        ADMIN_RCON, "- Show plugin status" );
    register_concmd( "wi_reload_config", "Cmd_ReloadConfig",  ADMIN_RCON, "- Reload keywords/rules and clear model cache" );
    register_concmd( "wi_debug",         "Cmd_Debug",         ADMIN_RCON, "<player> - Debug info for a player" );

    // Events
    register_event( "HLTV", "Event_RoundStart", "a", "1=0", "2=0" );
    register_event( "DeathMsg", "Event_DeathMsg", "a" );
}

public plugin_cfg( )
{
    // Auto exec weapon_inspector.cfg if present
    new szCfgDir[ 128 ];
    get_configsdir( szCfgDir, charsmax( szCfgDir ) );

    new szCfg[ 192 ];
    formatex( szCfg, charsmax( szCfg ), "%s/weapon_inspector.cfg", szCfgDir );

    if ( file_exists( szCfg ) )
    {
        server_cmd( "exec ^"%s^"", szCfg );
        server_exec( );
    }
}

public plugin_end( )
{
    CleanupTrieCache( g_tInspectSilenced );
    CleanupTrieCache( g_tInspectUnsilenced );
    CleanupTrieCache( g_tInspectGeneric );
    CleanupTrieCache( g_tIdleSilenced );
    CleanupTrieCache( g_tIdleUnsilenced );
    CleanupTrieCache( g_tIdleGeneric );

    if ( g_tInspectSilenced      != Invalid_Trie ) TrieDestroy( g_tInspectSilenced );
    if ( g_tInspectUnsilenced    != Invalid_Trie ) TrieDestroy( g_tInspectUnsilenced );
    if ( g_tInspectGeneric       != Invalid_Trie ) TrieDestroy( g_tInspectGeneric );

    if ( g_tIdleSilenced         != Invalid_Trie ) TrieDestroy( g_tIdleSilenced );
    if ( g_tIdleUnsilenced       != Invalid_Trie ) TrieDestroy( g_tIdleUnsilenced );
    if ( g_tIdleGeneric          != Invalid_Trie ) TrieDestroy( g_tIdleGeneric );

    if ( g_tModelValidated       != Invalid_Trie ) TrieDestroy( g_tModelValidated );
    if ( g_tModelAnalyzed        != Invalid_Trie ) TrieDestroy( g_tModelAnalyzed );
    if ( g_tModelSupportsInspect != Invalid_Trie ) TrieDestroy( g_tModelSupportsInspect );
    if ( g_tModelNumSeq          != Invalid_Trie ) TrieDestroy( g_tModelNumSeq );

    if ( g_tRuleAutoInspect      != Invalid_Trie ) TrieDestroy( g_tRuleAutoInspect );
    if ( g_tRuleManualInspect    != Invalid_Trie ) TrieDestroy( g_tRuleManualInspect );
    if ( g_tRuleIdleLoopTime     != Invalid_Trie ) TrieDestroy( g_tRuleIdleLoopTime );
    if ( g_tRuleIdleSeqForce     != Invalid_Trie ) TrieDestroy( g_tRuleIdleSeqForce );

    if ( g_aInspectKeywords      != Invalid_Array ) ArrayDestroy( g_aInspectKeywords );
}

// ========================================================================
//  CLIENT EVENTS
// ========================================================================
public client_putinserver( id )
{
    ResetPlayerState( id );
    g_bAnnounced[ id ] = false;
}

public client_disconnected( id )
{
    ResetPlayerState( id );
    g_bAnnounced[ id ] = false;
}

public Event_RoundStart( )
{
    for ( new i = 1; i <= MAX_PLAYERS; i++ )
    {
        if ( is_user_connected( i ) )
        {
            ResetPlayerState( i );
        }
    }
}

public Event_DeathMsg( )
{
    new id = read_data( 2 );

    if ( 1 <= id <= MAX_PLAYERS )
    {
        ResetPlayerState( id );
    }
}

// ========================================================================
//  NATIVES
// ========================================================================
public bool:Native_IsInspecting( iPlugin, iParams )
{
    new id = get_param( 1 );

    if ( !( 1 <= id <= MAX_PLAYERS ) )
    {
        return false;
    }

    return g_bInspecting[ id ];
}

public bool:Native_ForceInspect( iPlugin, iParams )
{
    new id = get_param( 1 );

    if ( !( 1 <= id <= MAX_PLAYERS ) )
    {
        return false;
    }

    return WI_TryInspect( id, true );
}

public Native_BlockInspect( iPlugin, iParams )
{
    new id = get_param( 1 );
    new Float:fDur = get_param_f( 2 );

    if ( !( 1 <= id <= MAX_PLAYERS ) )
    {
        return 0;
    }

    if ( fDur < 0.0 )
    {
        fDur = 0.0;
    }

    new Float:fUntil = get_gametime( ) + fDur;

    if ( fUntil > g_fBlockedUntil[ id ] )
    {
        g_fBlockedUntil[ id ] = fUntil;
    }

    // If currently inspecting and someone blocks, cancel softly to restore
    if ( g_bInspecting[ id ] )
    {
        CancelInspect( id, true );
    }

    return 1;
}

public Float:Native_GetInspectTimeLeft( iPlugin, iParams )
{
    new id = get_param( 1 );

    if ( !( 1 <= id <= MAX_PLAYERS ) )
    {
        return 0.0;
    }

    if ( !g_bInspecting[ id ] )
    {
        return 0.0;
    }

    new Float:fLeft = g_fInspectEnd[ id ] - get_gametime( );

    if ( fLeft < 0.0 )
    {
        fLeft = 0.0;
    }

    return fLeft;
}

// ========================================================================
//  ADMIN COMMANDS
// ========================================================================
public Cmd_Status( id, level, cid )
{
    if ( !cmd_access( id, level, cid, 1 ) )
    {
        return PLUGIN_HANDLED;
    }

    console_print( id, "========== Weapon Inspector Status ==========" );
    console_print( id, "Version: %s", PLUGIN_VERSION );
    console_print( id, "Enabled: %d", get_pcvar_num( g_pCvarEnabled ) );
    console_print( id, "Impulse mode: %d (0=off, 1=100, 2=201)", get_pcvar_num( g_pCvarImpulseMode ) );
    console_print( id, "Keywords loaded: %d", g_iInspectKeywordCount );
    console_print( id, "Log models: %d", get_pcvar_num( g_pCvarLogModels ) );
    console_print( id, "Model rules loaded: %d", TrieCountCells( g_tRuleAutoInspect ) );
    console_print( id, "=============================================" );

    return PLUGIN_HANDLED;
}

public Cmd_ReloadConfig( id, level, cid )
{
    if ( !cmd_access( id, level, cid, 1 ) )
    {
        return PLUGIN_HANDLED;
    }

    ArrayClear( g_aInspectKeywords );
    g_iInspectKeywordCount = 0;

    TrieClear( g_tModelValidated );
    TrieClear( g_tModelAnalyzed );
    TrieClear( g_tModelSupportsInspect );
    TrieClear( g_tModelNumSeq );

    CleanupTrieCache( g_tInspectSilenced );
    CleanupTrieCache( g_tInspectUnsilenced );
    CleanupTrieCache( g_tInspectGeneric );
    CleanupTrieCache( g_tIdleSilenced );
    CleanupTrieCache( g_tIdleUnsilenced );
    CleanupTrieCache( g_tIdleGeneric );

    TrieClear( g_tInspectSilenced );
    TrieClear( g_tInspectUnsilenced );
    TrieClear( g_tInspectGeneric );
    TrieClear( g_tIdleSilenced );
    TrieClear( g_tIdleUnsilenced );
    TrieClear( g_tIdleGeneric );

    TrieClear( g_tRuleAutoInspect );
    TrieClear( g_tRuleManualInspect );
    TrieClear( g_tRuleIdleLoopTime );
    TrieClear( g_tRuleIdleSeqForce );

    LoadInspectKeywords( );
    LoadModelRules( );

    console_print( id, "[WI] Config reloaded. %d keyword(s). Model rules: %d",
        g_iInspectKeywordCount,
        TrieCountCells( g_tRuleAutoInspect ) );

    return PLUGIN_HANDLED;
}

public Cmd_Debug( id, level, cid )
{
    if ( !cmd_access( id, level, cid, 2 ) )
    {
        return PLUGIN_HANDLED;
    }

    new szArg[ 64 ];
    read_argv( 1, szArg, charsmax( szArg ) );

    new iTarget = cmd_target( id, szArg, CMDTARGET_ALLOW_SELF | CMDTARGET_NO_BOTS );

    if ( !iTarget )
    {
        console_print( id, "[WI] Invalid target." );
        return PLUGIN_HANDLED;
    }

    new szModel[ MODEL_PATH_LEN ];
    GetPlayerViewModel( iTarget, szModel, charsmax( szModel ) );

    new weapon = get_pdata_cbase( iTarget, m_pActiveItem, XO_PLAYER );

    console_print( id, "========== WI DEBUG (%n) ==========", iTarget );
    console_print( id, "Alive: %d | Connected: %d", is_user_alive( iTarget ), is_user_connected( iTarget ) );
    console_print( id, "Weapon ent: %d | Weapon id: %d", weapon, get_user_weapon( iTarget ) );
    console_print( id, "Viewmodel: %s", szModel[ 0 ] ? szModel : "<none>" );
    console_print( id, "Inspecting: %d | Seq: %d | TimeLeft: %.3f",
        g_bInspecting[ iTarget ],
        g_iInspectSeq[ iTarget ],
        floatmax( 0.0, g_fInspectEnd[ iTarget ] - get_gametime( ) ) );

    console_print( id, "CooldownUntil: %.3f (in %.3f)",
        g_fCooldownUntil[ iTarget ],
        floatmax( 0.0, g_fCooldownUntil[ iTarget ] - get_gametime( ) ) );

    console_print( id, "BusyUntil: %.3f (in %.3f)",
        g_fBusyUntil[ iTarget ],
        floatmax( 0.0, g_fBusyUntil[ iTarget ] - get_gametime( ) ) );

    console_print( id, "BlockedUntil: %.3f (in %.3f)",
        g_fBlockedUntil[ iTarget ],
        floatmax( 0.0, g_fBlockedUntil[ iTarget ] - get_gametime( ) ) );

    console_print( id, "Zoom: %d", cs_get_user_zoom( iTarget ) );

    if ( szModel[ 0 ] )
    {
        new iSupport = 0;
        TrieGetCell( g_tModelSupportsInspect, szModel, iSupport );

        new iAuto = GetRuleAutoInspect( szModel );
        new iManual = GetRuleManualInspect( szModel );
        new Float:fLoop = GetRuleIdleLoopTime( szModel );
        new iForce = GetRuleIdleSeqForce( szModel );

        console_print( id, "Rules: AUTO=%d MANUAL=%d LOOP=%.2f IDLE_FORCE=%d", iAuto, iManual, fLoop, iForce );
        console_print( id, "ModelSupportsInspect cached: %d", iSupport );

        if ( EnsureModelAnalyzed( szModel ) )
        {
            new Array:a1 = GetCachedArray( g_tInspectGeneric, szModel );
            new Array:a2 = GetCachedArray( g_tInspectSilenced, szModel );
            new Array:a3 = GetCachedArray( g_tInspectUnsilenced, szModel );

            new Array:a4 = GetCachedArray( g_tIdleGeneric, szModel );
            new Array:a5 = GetCachedArray( g_tIdleSilenced, szModel );
            new Array:a6 = GetCachedArray( g_tIdleUnsilenced, szModel );

            console_print( id, "Inspect pools: gen=%d sil=%d unsil=%d",
                ( a1 != Invalid_Array ) ? ArraySize( a1 ) : 0,
                ( a2 != Invalid_Array ) ? ArraySize( a2 ) : 0,
                ( a3 != Invalid_Array ) ? ArraySize( a3 ) : 0 );

            console_print( id, "Idle pools:    gen=%d sil=%d unsil=%d",
                ( a4 != Invalid_Array ) ? ArraySize( a4 ) : 0,
                ( a5 != Invalid_Array ) ? ArraySize( a5 ) : 0,
                ( a6 != Invalid_Array ) ? ArraySize( a6 ) : 0 );
        }
        else
        {
            console_print( id, "EnsureModelAnalyzed: FAILED" );
        }
    }

    console_print( id, "==================================" );
    return PLUGIN_HANDLED;
}

// ========================================================================
//  ACTIVATION - COMMAND / IMPULSE
// ========================================================================
public Cmd_Inspect( id )
{
    if ( !get_pcvar_num( g_pCvarEnabled ) )
    {
        return PLUGIN_HANDLED;
    }

    WI_TryInspect( id, false );
    return PLUGIN_HANDLED;
}

public client_impulse( id, impulse )
{
    if ( !get_pcvar_num( g_pCvarEnabled ) )
    {
        return PLUGIN_CONTINUE;
    }

    if ( !is_user_alive( id ) )
    {
        return PLUGIN_CONTINUE;
    }

    new iMode = get_pcvar_num( g_pCvarImpulseMode );

    if ( iMode != 1 && iMode != 2 )
    {
        return PLUGIN_CONTINUE;
    }

    if ( ( iMode == 1 && impulse != 100 ) || ( iMode == 2 && impulse != 201 ) )
    {
        return PLUGIN_CONTINUE;
    }

    // Only block default impulse if we actually start inspect
    if ( WI_TryInspect( id, false ) )
    {
        return PLUGIN_HANDLED;
    }

    return PLUGIN_CONTINUE;
}

// ========================================================================
//  CORE - TRY INSPECT (MANUAL)
// ========================================================================
stock bool:WI_TryInspect( const id, const bool:bForced )
{
    if ( !get_pcvar_num( g_pCvarEnabled ) )
    {
        return false;
    }

    if ( !is_user_alive( id ) || !is_user_connected( id ) )
    {
        return false;
    }

    // Optional announce (first time)
    if ( get_pcvar_num( g_pCvarAnnounce ) && !g_bAnnounced[ id ] )
    {
        g_bAnnounced[ id ] = true;
        client_print( id, print_chat, "[WI] Usa ^"inspect^" (bind) o impulse segun configuracion del servidor." );
    }

    // Block if scoped
    if ( cs_get_user_zoom( id ) > CS_SET_NO_ZOOM )
    {
        return false;
    }

    new wpn_id = get_user_weapon( id );

    if ( WPNS_NO_INSPECT & ( 1 << wpn_id ) )
    {
        return false;
    }

    // Active weapon entity
    new weapon = get_pdata_cbase( id, m_pActiveItem, XO_PLAYER );

    if ( !pev_valid( weapon ) )
    {
        return false;
    }

    if ( g_bInspecting[ id ] )
    {
        return false;
    }

    // Hard block by other plugins/events
    if ( get_gametime( ) < g_fBlockedUntil[ id ] )
    {
        return false;
    }

    // Block if player is pressing attack
    new buttons = pev( id, pev_button );

    if ( buttons & ( IN_ATTACK | IN_ATTACK2 ) )
    {
        return false;
    }

    // Block during special reload state (shotguns)
    if ( get_pdata_int( weapon, m_fInSpecialReload, XO_WEAPON ) )
    {
        return false;
    }

    // Safe timing checks (do not break weapon logic)
    new Float:flNextAttack    = get_pdata_float( id,     m_flNextAttack,           XO_PLAYER );
    new Float:flNextPrimary   = get_pdata_float( weapon, m_flNextPrimaryAttack,    XO_WEAPON );
    new Float:flNextSecondary = get_pdata_float( weapon, m_flNextSecondaryAttack,  XO_WEAPON );

    if ( flNextAttack > 0.0 || flNextPrimary > 0.0 || flNextSecondary > 0.0 )
    {
        return false;
    }

    // Model path
    new szModel[ MODEL_PATH_LEN ];

    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) )
    {
        return false;
    }

    // Manual inspect rule (unless forced)
    if ( !bForced && !GetRuleManualInspect( szModel ) )
    {
        return false;
    }

    // Forced calls may bypass cooldown/rate limiting, but not an active
    // gameplay safety window created by firing, deploying or reloading.
    if ( get_gametime( ) < g_fBusyUntil[ id ] )
    {
        return false;
    }

    // Non-forced restrictions
    if ( !bForced )
    {
        if ( get_gametime( ) < g_fCooldownUntil[ id ] )
        {
            return false;
        }

        if ( !CheckRateLimit( id ) )
        {
            return false;
        }
    }

    // Model support check (parses model only once per unique path)
    if ( !ModelSupportsInspect( szModel ) )
    {
        return false;
    }

    // Select inspect sequence + duration
    new iSeq;
    new Float:fDuration;

    if ( !GetInspectSequenceAndDuration( id, weapon, iSeq, fDuration ) )
    {
        return false;
    }

    // Pre forward (can block)
    new iRet = 0;
    ExecuteForward( g_fwdInspectStartPre, iRet, id, weapon, iSeq );

    if ( iRet >= PLUGIN_HANDLED )
    {
        return false;
    }

    // Clamp duration
    new Float:fMin = get_pcvar_float( g_pCvarDurMin );
    new Float:fMax = get_pcvar_float( g_pCvarDurMax );

    if ( fDuration < fMin ) fDuration = fMin;
    if ( fDuration > fMax ) fDuration = fMax;

    // Start inspect
    g_bInspecting[ id ] = true;
    g_iInspectSeq[ id ] = iSeq;
    g_fInspectEnd[ id ] = get_gametime( ) + fDuration;

    // IMPORTANT: ensure idle-loop never runs during inspect
    ClearIdleLoopState( id );

    // Play inspect
    PlayWeaponAnim( id, weapon, iSeq );

    // Natural idle: push weapon idle into the future.
    BlockWeaponIdle( id, weapon, g_fInspectEnd[ id ] + IDLE_BLOCK_PAD );

    ExecuteForward( g_fwdInspectStart, _, id, weapon, iSeq );

    return true;
}

// ========================================================================
//  HAM HOOKS
// ========================================================================
public HamHook_PrimaryAttack_Post( weapon )
{
    new id = get_pdata_cbase( weapon, m_pPlayer, XO_WEAPON );

    if ( id < 1 || id > MAX_PLAYERS )
    {
        return;
    }

    // GameDLL may have replaced the timer written by the automatic idle loop.
    ClearIdleLoopState( id );

    if ( !get_pcvar_num( g_pCvarEnabled ) || !is_user_alive( id ) )
    {
        return;
    }

    new wpn_id = get_user_weapon( id );

    // Shotgun special reload: NEVER interfere (critical)
    if ( ( wpn_id == CSW_M3 || wpn_id == CSW_XM1014 )
        && get_pdata_int( weapon, m_fInSpecialReload, XO_WEAPON ) != 0 )
    {
        return;
    }

    new szModel[ MODEL_PATH_LEN ];
    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) || !ModelSupportsInspect( szModel ) )
    {
        return;
    }

    if ( g_bInspecting[ id ] )
    {
        CancelInspect( id, false );
        SetCooldown( id, get_gametime( ) + 0.30 );
    }

    new Float:fBusy;

    switch ( wpn_id )
    {
        case CSW_AWP, CSW_SCOUT, CSW_M3, CSW_XM1014:
        {
            fBusy = 1.50;
        }
        case CSW_KNIFE:
        {
            fBusy = 1.00;
        }
        case CSW_DEAGLE:
        {
            fBusy = 0.70;
        }
        default:
        {
            fBusy = 0.30;
        }
    }

    g_fBusyUntil[ id ] = floatmax( g_fBusyUntil[ id ], get_gametime( ) + fBusy );

    BlockWeaponIdle( id, weapon, g_fBusyUntil[ id ] + IDLE_BLOCK_PAD );
}

public HamHook_SecondaryAttack_Post( weapon )
{
    new id = get_pdata_cbase( weapon, m_pPlayer, XO_WEAPON );

    if ( id < 1 || id > MAX_PLAYERS )
    {
        return;
    }

    ClearIdleLoopState( id );

    if ( !get_pcvar_num( g_pCvarEnabled ) || !is_user_alive( id ) )
    {
        return;
    }

    new szModel[ MODEL_PATH_LEN ];
    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) || !ModelSupportsInspect( szModel ) )
    {
        return;
    }

    if ( g_bInspecting[ id ] )
    {
        CancelInspect( id, true );
    }

    new Float:fSecondaryDelay = get_pdata_float( weapon, m_flNextSecondaryAttack, XO_WEAPON );
    if ( fSecondaryDelay < 0.0 )
    {
        fSecondaryDelay = 0.0;
    }

    new Float:fUntil = get_gametime( ) + floatmax( fSecondaryDelay, 0.50 );
    g_fBusyUntil[ id ] = floatmax( g_fBusyUntil[ id ], fUntil );
    SetCooldown( id, fUntil );
}

public HamHook_Deploy_Post( weapon )
{
    new id = get_pdata_cbase( weapon, m_pPlayer, XO_WEAPON );

    if ( id < 1 || id > MAX_PLAYERS )
    {
        return;
    }

    ClearIdleLoopState( id );

    if ( !get_pcvar_num( g_pCvarEnabled ) || !is_user_alive( id ) )
    {
        return;
    }

    if ( g_bInspecting[ id ] )
    {
        CancelInspect( id, false );
    }

    new szModel[ MODEL_PATH_LEN ];
    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) || !ModelSupportsInspect( szModel ) )
    {
        return;
    }

    new Float:fCd = get_pcvar_float( g_pCvarDeployCooldown );

    SetCooldown( id, get_gametime( ) + fCd );
    g_fBusyUntil[ id ] = floatmax( g_fBusyUntil[ id ], get_gametime( ) + fCd );
}

public HamHook_Reload_Post( weapon )
{
    new id = get_pdata_cbase( weapon, m_pPlayer, XO_WEAPON );

    if ( id < 1 || id > MAX_PLAYERS )
    {
        return;
    }

    ClearIdleLoopState( id );

    if ( !get_pcvar_num( g_pCvarEnabled ) || !is_user_alive( id ) )
    {
        return;
    }

    if ( g_bInspecting[ id ] )
    {
        CancelInspect( id, false );
    }

    new szModel[ MODEL_PATH_LEN ];
    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) || !ModelSupportsInspect( szModel ) )
    {
        return;
    }

    // Shotgun special reload: NEVER interfere (fix)
    if ( get_pdata_int( weapon, m_fInSpecialReload, XO_WEAPON ) != 0 )
    {
        return;
    }

    new Float:flNextAttack = get_pdata_float( id, m_flNextAttack, XO_PLAYER );

    if ( flNextAttack > 0.0 )
    {
        new Float:fReloadEnd = get_gametime( ) + flNextAttack;

        g_fBusyUntil[ id ] = floatmax( g_fBusyUntil[ id ], fReloadEnd );

        SetCooldown( id, fReloadEnd + get_pcvar_float( g_pCvarReloadCooldown ) );
        BlockWeaponIdle( id, weapon, fReloadEnd + IDLE_BLOCK_PAD );
    }
}

// ========================================================================
//  PRETHINK - Monitor inspect end / interruption + MODEL AUTO idle-loop
// ========================================================================
public FMHook_PreThink( id )
{
    if ( !is_user_alive( id ) )
    {
        return FMRES_IGNORED;
    }

    if ( !get_pcvar_num( g_pCvarEnabled ) )
    {
        new Float:fNow = get_gametime( );
        new weapon = get_pdata_cbase( id, m_pActiveItem, XO_PLAYER );
        new bool:bWasInspecting = g_bInspecting[ id ];
        new bool:bOwnsIdleLoop = pev_valid( weapon )
            && g_iIdleLoopWeapon[ id ] == weapon
            && g_fNextIdleLoop[ id ] > fNow;

        if ( bWasInspecting )
        {
            // Restore a known idle when possible, then immediately release
            // the predicted weapon timer so disabled hooks leave no lock.
            CancelInspect( id, true );
        }

        if ( pev_valid( weapon ) && ( bWasInspecting || bOwnsIdleLoop ) )
        {
            BlockWeaponIdle( id, weapon, fNow );
        }

        ClearIdleLoopState( id );
        return FMRES_IGNORED;
    }

    // ------------------------------------------------------------
    // While inspecting: NEVER run idle-loop.
    // ------------------------------------------------------------
    if ( g_bInspecting[ id ] )
    {
        // Cancel if player attacks
        new buttons = pev( id, pev_button );

        if ( buttons & ( IN_ATTACK | IN_ATTACK2 ) )
        {
            CancelInspect( id, true );
            SetCooldown( id, get_gametime( ) + 0.30 );
            return FMRES_IGNORED;
        }

        // Cancel if weapon changed (viewmodel changed)
        new szModel[ MODEL_PATH_LEN ];

        if ( GetPlayerViewModel( id, szModel, charsmax( szModel ) ) )
        {
            if ( !equal( szModel, g_szLastViewModel[ id ] ) )
            {
                CancelInspect( id, false );
                return FMRES_IGNORED;
            }
        }

        // Cancel if weapon entered reload (shotguns)
        new weapon = get_pdata_cbase( id, m_pActiveItem, XO_PLAYER );

        if ( pev_valid( weapon ) )
        {
            if ( get_pdata_int( weapon, m_fInSpecialReload, XO_WEAPON ) )
            {
                CancelInspect( id, false );
                return FMRES_IGNORED;
            }

            // Keep idle blocked while inspecting
            if ( get_gametime( ) < g_fInspectEnd[ id ] )
            {
                BlockWeaponIdle( id, weapon, g_fInspectEnd[ id ] + IDLE_BLOCK_PAD );
            }
            else
            {
                CancelInspect( id, true );
            }
        }
        else
        {
            CancelInspect( id, false );
        }

        return FMRES_IGNORED;
    }

    // ------------------------------------------------------------
    // Not inspecting: apply per-model AUTO idle-loop if configured.
    // ------------------------------------------------------------
    new szModel[ MODEL_PATH_LEN ];
    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) )
    {
        return FMRES_IGNORED;
    }

    // Only meaningful for models that have inspect support (cached logic)
    if ( !ModelSupportsInspect( szModel ) )
    {
        return FMRES_IGNORED;
    }

    // AUTO_INSPECT = 1 => do nothing (allow model's normal idle)
    if ( GetRuleAutoInspect( szModel ) != 0 )
    {
        return FMRES_IGNORED;
    }

    new Float:fLoopTime = GetRuleIdleLoopTime( szModel );

    // If loop time is not configured, we do not attempt hacks.
    if ( fLoopTime <= 0.0 )
    {
        return FMRES_IGNORED;
    }

    // Do not interfere while busy / blocked / scoped / attacking / reloading
    if ( get_gametime( ) < g_fBusyUntil[ id ] )
    {
        return FMRES_IGNORED;
    }

    if ( get_gametime( ) < g_fBlockedUntil[ id ] )
    {
        return FMRES_IGNORED;
    }

    if ( cs_get_user_zoom( id ) > CS_SET_NO_ZOOM )
    {
        return FMRES_IGNORED;
    }

    new buttons = pev( id, pev_button );
    if ( buttons & ( IN_ATTACK | IN_ATTACK2 ) )
    {
        // Secondary actions are not hooked for every weapon class. Invalidate
        // ownership before GameDLL can replace the timer we previously wrote.
        ClearIdleLoopState( id );
        return FMRES_IGNORED;
    }

    new weapon = get_pdata_cbase( id, m_pActiveItem, XO_PLAYER );
    if ( !pev_valid( weapon ) )
    {
        ClearIdleLoopState( id );
        return FMRES_IGNORED;
    }

    if ( g_iIdleLoopWeapon[ id ] != 0 && g_iIdleLoopWeapon[ id ] != weapon )
    {
        ClearIdleLoopState( id );
    }

    // Shotgun special reload: NEVER interfere (fix)
    if ( get_pdata_int( weapon, m_fInSpecialReload, XO_WEAPON ) )
    {
        return FMRES_IGNORED;
    }

    if ( get_pdata_float( id, m_flNextAttack, XO_PLAYER ) > 0.0 )
    {
        return FMRES_IGNORED;
    }

    new Float:gt = get_gametime( );

    if ( gt < g_fNextIdleLoop[ id ] )
    {
        return FMRES_IGNORED;
    }

    new iIdleSeq = -1;
    new Float:fIdleDur = 0.0;

    // Optional forced idle sequence per model
    new iForced = GetRuleIdleSeqForce( szModel );

    if ( iForced >= 0 )
    {
        // Validate against model seq count (cached)
        new iNumSeq = GetModelNumSeqCached( szModel );

        if ( iNumSeq > 0 && iForced < iNumSeq && iForced <= MAX_WEAPON_ANIM_SEQ )
        {
            iIdleSeq = iForced;
        }
        else
        {
            // bad force value -> ignore hack for safety
            return FMRES_IGNORED;
        }
    }
    else
    {
        if ( !GetIdleSequenceAndDuration( id, weapon, iIdleSeq, fIdleDur ) )
        {
            return FMRES_IGNORED;
        }
    }

    if ( iIdleSeq < 0 )
    {
        return FMRES_IGNORED;
    }

    if ( fLoopTime < 0.05 )
    {
        fLoopTime = 0.05;
    }

    // Restart through the weapon animation message. pev_viewmodel is a string
    // handle in GoldSrc, not an entity that can safely receive set_pev calls.
    PlayWeaponAnim( id, weapon, iIdleSeq );

    BlockWeaponIdle( id, weapon, gt + fLoopTime );
    g_fNextIdleLoop[ id ] = gt + fLoopTime;
    g_iIdleLoopWeapon[ id ] = weapon;

    return FMRES_IGNORED;
}

// ========================================================================
//  HELPERS - State Management
// ========================================================================
stock ClearIdleLoopState( const id )
{
    g_fNextIdleLoop[ id ] = 0.0;
    g_iIdleLoopWeapon[ id ] = 0;
}

stock ResetPlayerState( const id )
{
    if ( g_bInspecting[ id ] )
    {
        CancelInspect( id, false );
    }

    g_fCooldownUntil[ id ]     = 0.0;
    g_fBusyUntil[ id ]         = 0.0;
    g_fBlockedUntil[ id ]      = 0.0;

    g_iInspectCount[ id ]      = 0;
    g_fLastInspectReset[ id ]  = 0.0;

    ClearIdleLoopState( id );

    g_szLastViewModel[ id ][ 0 ] = EOS;
    g_iInspectSeq[ id ]          = -1;
    g_fInspectEnd[ id ]          = 0.0;
}

stock CancelInspect( const id, bool:bPlayIdle = true )
{
    new bool:bWasInspecting = g_bInspecting[ id ];

    g_bInspecting[ id ] = false;
    g_iInspectSeq[ id ] = -1;
    g_fInspectEnd[ id ] = 0.0;

    // ensure idle-loop won't collide right after inspect ends
    ClearIdleLoopState( id );

    if ( bPlayIdle && bWasInspecting && is_user_alive( id ) )
    {
        new weapon = get_pdata_cbase( id, m_pActiveItem, XO_PLAYER );

        if ( pev_valid( weapon ) )
        {
            new iIdleSeq = -1;
            new Float:fIdleDur = 0.0;

            // If model has forced idle seq, prefer it here too (optional)
            new szModel[ MODEL_PATH_LEN ];
            if ( GetPlayerViewModel( id, szModel, charsmax( szModel ) ) )
            {
                new iForced = GetRuleIdleSeqForce( szModel );

                if ( iForced >= 0 )
                {
                    new iNumSeq = GetModelNumSeqCached( szModel );

                    if ( iNumSeq > 0 && iForced < iNumSeq && iForced <= MAX_WEAPON_ANIM_SEQ )
                    {
                        iIdleSeq = iForced;
                        fIdleDur = 3.0;
                    }
                }
            }

            if ( iIdleSeq < 0 )
            {
                if ( !GetIdleSequenceAndDuration( id, weapon, iIdleSeq, fIdleDur ) )
                {
                    // No known idle sequence: let the GameDLL choose its
                    // normal idle instead of assuming sequence 0 is safe.
                    BlockWeaponIdle( id, weapon, get_gametime( ) );
                    iIdleSeq = -1;
                }
            }

            if ( iIdleSeq >= 0 )
            {
                PlayWeaponAnim( id, weapon, iIdleSeq );

                if ( fIdleDur < 0.10 )
                {
                    fIdleDur = 3.0;
                }

                BlockWeaponIdle( id, weapon, get_gametime( ) + fIdleDur );
            }
        }
    }

    if ( bWasInspecting )
    {
        ExecuteForward( g_fwdInspectEnd, _, id );
    }
}

stock SetCooldown( const id, const Float:fUntil )
{
    if ( fUntil > g_fCooldownUntil[ id ] )
    {
        g_fCooldownUntil[ id ] = fUntil;
    }
}

stock bool:CheckRateLimit( const id )
{
    new iMax = get_pcvar_num( g_pCvarMaxInspectPerSec );

    if ( iMax <= 0 )
    {
        return true;
    }

    if ( get_gametime( ) - g_fLastInspectReset[ id ] >= 1.0 )
    {
        g_iInspectCount[ id ] = 0;
        g_fLastInspectReset[ id ] = get_gametime( );
    }

    if ( g_iInspectCount[ id ] >= iMax )
    {
        return false;
    }

    g_iInspectCount[ id ]++;
    return true;
}

// ========================================================================
//  HELPERS - Animation & Idle
// ========================================================================
stock PlayWeaponAnim( const id, const weapon, const iAnim )
{
    if ( !is_user_alive( id )
        || !pev_valid( weapon )
        || iAnim < 0
        || iAnim > MAX_WEAPON_ANIM_SEQ )
    {
        return;
    }

    new iBody = clamp( pev( weapon, pev_body ), 0, 255 );

    set_pev( id, pev_weaponanim, iAnim );

    message_begin( MSG_ONE_UNRELIABLE, SVC_WEAPONANIM, { 0, 0, 0 }, id );
    write_byte( iAnim );
    write_byte( iBody );
    message_end( );
}

stock BlockWeaponIdle( const id, const weapon, const Float:fAbsoluteUntil )
{
    if ( !is_user_alive( id ) || !pev_valid( weapon ) )
    {
        return;
    }

    new Float:fDelay = fAbsoluteUntil - get_gametime( );

    if ( fDelay < 0.0 )
    {
        fDelay = 0.0;
    }

    // CS 1.6 predicted weapon timers are stored as relative durations.
    set_pdata_float( weapon, m_flTimeWeaponIdle, fDelay, XO_WEAPON );
}

stock bool:GetPlayerViewModel( const id, szModel[ ], const iLen )
{
    szModel[ 0 ] = EOS;
    pev( id, pev_viewmodel2, szModel, iLen );

    return ( szModel[ 0 ] != EOS );
}

// ========================================================================
//  RULES - GETTERS (defaults if no entry)
// ========================================================================
stock GetRuleAutoInspect( const szModel[ ] )
{
    new v;
    if ( TrieGetCell( g_tRuleAutoInspect, szModel, v ) )
    {
        return v;
    }
    return RULE_DEFAULT_AUTO;
}

stock GetRuleManualInspect( const szModel[ ] )
{
    new v;
    if ( TrieGetCell( g_tRuleManualInspect, szModel, v ) )
    {
        return v;
    }
    return RULE_DEFAULT_MANUAL;
}

stock Float:GetRuleIdleLoopTime( const szModel[ ] )
{
    new bits;
    if ( TrieGetCell( g_tRuleIdleLoopTime, szModel, bits ) )
    {
        return Float:bits;
    }
    return RULE_DEFAULT_LOOP;
}

stock GetRuleIdleSeqForce( const szModel[ ] )
{
    new v;
    if ( TrieGetCell( g_tRuleIdleSeqForce, szModel, v ) )
    {
        return v;
    }
    return RULE_DEFAULT_IDLE_SEQ_FORCE;
}

// ========================================================================
//  MODEL SUPPORT CHECK
// ========================================================================
stock bool:ModelSupportsInspect( const szModel[ ] )
{
    new iSupport;

    if ( TrieGetCell( g_tModelSupportsInspect, szModel, iSupport ) )
    {
        return ( iSupport != 0 );
    }

    if ( !ValidateModelFile( szModel ) )
    {
        TrieSetCell( g_tModelSupportsInspect, szModel, 0 );
        return false;
    }

    if ( !EnsureModelAnalyzed( szModel ) )
    {
        TrieSetCell( g_tModelSupportsInspect, szModel, 0 );
        return false;
    }

    if ( TrieGetCell( g_tModelSupportsInspect, szModel, iSupport ) )
    {
        return ( iSupport != 0 );
    }

    TrieSetCell( g_tModelSupportsInspect, szModel, 0 );
    return false;
}

// ========================================================================
//  MODEL VALIDATION
// ========================================================================
stock bool:ReadStudioSequenceTable( const szModel[ ], &iSeqCount, &iSeqIndex )
{
    iSeqCount = 0;
    iSeqIndex = 0;

    new iFileSize = file_size( szModel, 0 );

    if ( iFileSize < MIN_MODEL_SIZE || iFileSize > MAX_MODEL_SIZE )
    {
        return false;
    }

    new f = fopen( szModel, "rb" );

    if ( !f )
    {
        return false;
    }

    new iMagic;
    new iVersion;
    new iDeclaredLength;
    new bool:bReadOk = true;

    if ( fseek( f, 0, SEEK_SET ) != 0
        || fread( f, iMagic, BLOCK_INT ) != 1
        || fread( f, iVersion, BLOCK_INT ) != 1 )
    {
        bReadOk = false;
    }

    if ( bReadOk
        && ( fseek( f, STUDIO_LENGTH_OFFSET, SEEK_SET ) != 0
            || fread( f, iDeclaredLength, BLOCK_INT ) != 1 ) )
    {
        bReadOk = false;
    }

    if ( bReadOk
        && ( fseek( f, STUDIO_NUMSEQ_OFFSET, SEEK_SET ) != 0
            || fread( f, iSeqCount, BLOCK_INT ) != 1
            || fread( f, iSeqIndex, BLOCK_INT ) != 1 ) )
    {
        bReadOk = false;
    }

    fclose( f );

    if ( !bReadOk
        || iMagic != STUDIO_MAGIC
        || iVersion != STUDIO_VERSION
        || iDeclaredLength < STUDIO_HEADER_SIZE
        || iDeclaredLength > iFileSize
        || iSeqCount < 1
        || iSeqCount > MAX_STUDIO_SEQUENCES
        || iSeqIndex < STUDIO_HEADER_SIZE
        || iSeqIndex > iDeclaredLength )
    {
        return false;
    }

    // Division avoids overflow in iSeqCount * STUDIO_SEQDESC_SIZE.
    if ( iSeqCount > ( iDeclaredLength - iSeqIndex ) / STUDIO_SEQDESC_SIZE )
    {
        return false;
    }

    return true;
}

stock bool:ValidateModelFile( const szModel[ ] )
{
    new iValid;

    if ( TrieGetCell( g_tModelValidated, szModel, iValid ) )
    {
        return ( iValid != 0 );
    }

    new iSeqCount;
    new iSeqIndex;
    new bool:bValid = ReadStudioSequenceTable( szModel, iSeqCount, iSeqIndex );

    TrieSetCell( g_tModelValidated, szModel, bValid ? 1 : 0 );
    return bValid;
}

// ========================================================================
//  MODEL ANALYSIS - Sequence Classification
// ========================================================================
stock bool:EnsureModelAnalyzed( const szModel[ ] )
{
    if ( !ValidateModelFile( szModel ) )
    {
        return false;
    }

    new iAnalyzed;

    if ( TrieGetCell( g_tModelAnalyzed, szModel, iAnalyzed ) )
    {
        return true;
    }

    if ( !AnalyzeModelSequences( szModel ) )
    {
        return false;
    }

    TrieSetCell( g_tModelAnalyzed, szModel, 1 );
    return true;
}

stock bool:AnalyzeModelSequences( const szModel[ ] )
{
    new Array:aSeqNames = Invalid_Array;
    new iSeqCount = 0;

    if ( !GetAllSequenceNames( szModel, aSeqNames, iSeqCount ) )
    {
        return false;
    }

    new Array:aInspectSil   = ArrayCreate( 1, 0 );
    new Array:aInspectUnsil = ArrayCreate( 1, 0 );
    new Array:aInspectGen   = ArrayCreate( 1, 0 );

    new Array:aIdleSil      = ArrayCreate( 1, 0 );
    new Array:aIdleUnsil    = ArrayCreate( 1, 0 );
    new Array:aIdleGen      = ArrayCreate( 1, 0 );

    new szSeqName[ SEQ_NAME_LEN ];
    new szNormalized[ SEQ_NAME_LEN ];

    for ( new i = 0; i < iSeqCount; i++ )
    {
        ArrayGetString( aSeqNames, i, szSeqName, charsmax( szSeqName ) );

        // SVC_WEAPONANIM carries the sequence index in one byte.
        if ( i > MAX_WEAPON_ANIM_SEQ )
        {
            continue;
        }

        if ( IsSilencerActionSequence( szSeqName ) )
        {
            continue;
        }

        NormalizeSequenceName( szSeqName, szNormalized, charsmax( szNormalized ) );

        new SilencerState:silState = DetectSilencerSuffix( szSeqName );

        if ( IsInspectKeyword( szNormalized ) )
        {
            switch ( silState )
            {
                case SIL_ON:   ArrayPushCell( aInspectSil, i );
                case SIL_OFF:  ArrayPushCell( aInspectUnsil, i );
                case SIL_NONE: ArrayPushCell( aInspectGen, i );
            }

            continue;
        }

        if ( IsIdleKeyword( szNormalized ) )
        {
            switch ( silState )
            {
                case SIL_ON:   ArrayPushCell( aIdleSil, i );
                case SIL_OFF:  ArrayPushCell( aIdleUnsil, i );
                case SIL_NONE: ArrayPushCell( aIdleGen, i );
            }
        }
    }

    ArrayDestroy( aSeqNames );

    TrieSetCell( g_tInspectSilenced,      szModel, aInspectSil );
    TrieSetCell( g_tInspectUnsilenced,    szModel, aInspectUnsil );
    TrieSetCell( g_tInspectGeneric,       szModel, aInspectGen );

    TrieSetCell( g_tIdleSilenced,         szModel, aIdleSil );
    TrieSetCell( g_tIdleUnsilenced,       szModel, aIdleUnsil );
    TrieSetCell( g_tIdleGeneric,          szModel, aIdleGen );

    new bool:bHasInspect = ( ArraySize( aInspectSil ) > 0 || ArraySize( aInspectUnsil ) > 0 || ArraySize( aInspectGen ) > 0 );

    TrieSetCell( g_tModelSupportsInspect, szModel, bHasInspect ? 1 : 0 );

    if ( get_pcvar_num( g_pCvarLogModels ) )
    {
        server_print( "[WI] Model analyzed: %s", szModel );
        server_print( "[WI]   Inspect: gen=%d sil=%d unsil=%d | Idle: gen=%d sil=%d unsil=%d | Support=%d",
            ArraySize( aInspectGen ),
            ArraySize( aInspectSil ),
            ArraySize( aInspectUnsil ),
            ArraySize( aIdleGen ),
            ArraySize( aIdleSil ),
            ArraySize( aIdleUnsil ),
            bHasInspect ? 1 : 0 );
    }

    return true;
}

// ========================================================================
//  SEQUENCE SELECTION
// ========================================================================
stock bool:GetInspectSequenceAndDuration( const id, const weapon, &iSeq, &Float:fDuration )
{
    iSeq = -1;
    fDuration = 0.0;

    new szModel[ MODEL_PATH_LEN ];

    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) )
    {
        return false;
    }

    if ( !ValidateModelFile( szModel ) )
    {
        return false;
    }

    if ( !EnsureModelAnalyzed( szModel ) )
    {
        return false;
    }

    if ( !ModelSupportsInspect( szModel ) )
    {
        return false;
    }

    copy( g_szLastViewModel[ id ], charsmax( g_szLastViewModel[ ] ), szModel );

    new Array:aTarget   = Invalid_Array;
    new Array:aFallback = Invalid_Array;
    new Array:aOpposite = Invalid_Array;

    if ( IsSilenceAwareWeapon( weapon ) )
    {
        if ( IsWeaponSilenced( weapon ) )
        {
            aTarget   = GetCachedArray( g_tInspectSilenced,   szModel );
            aFallback = GetCachedArray( g_tInspectGeneric,    szModel );
            aOpposite = GetCachedArray( g_tInspectUnsilenced, szModel );
        }
        else
        {
            aTarget   = GetCachedArray( g_tInspectUnsilenced, szModel );
            aFallback = GetCachedArray( g_tInspectGeneric,    szModel );
            aOpposite = GetCachedArray( g_tInspectSilenced,   szModel );
        }
    }
    else
    {
        aTarget = GetCachedArray( g_tInspectGeneric, szModel );
    }

    if ( aTarget != Invalid_Array && ArraySize( aTarget ) > 0 )
    {
        iSeq = ArrayGetCell( aTarget, random_num( 0, ArraySize( aTarget ) - 1 ) );
    }
    else if ( aFallback != Invalid_Array && ArraySize( aFallback ) > 0 )
    {
        iSeq = ArrayGetCell( aFallback, random_num( 0, ArraySize( aFallback ) - 1 ) );
    }
    else if ( aOpposite != Invalid_Array && ArraySize( aOpposite ) > 0 )
    {
        iSeq = ArrayGetCell( aOpposite, random_num( 0, ArraySize( aOpposite ) - 1 ) );
    }

    if ( iSeq == -1 )
    {
        return false;
    }

    return GetSequenceDurationByIndex( szModel, iSeq, fDuration );
}

stock bool:GetIdleSequenceAndDuration( const id, const weapon, &iSeq, &Float:fDuration )
{
    iSeq = -1;
    fDuration = 0.0;

    new szModel[ MODEL_PATH_LEN ];

    if ( !GetPlayerViewModel( id, szModel, charsmax( szModel ) ) )
    {
        return false;
    }

    if ( !ValidateModelFile( szModel ) )
    {
        return false;
    }

    if ( !EnsureModelAnalyzed( szModel ) )
    {
        return false;
    }

    new Array:aTarget   = Invalid_Array;
    new Array:aFallback = Invalid_Array;
    new Array:aOpposite = Invalid_Array;

    if ( IsSilenceAwareWeapon( weapon ) )
    {
        if ( IsWeaponSilenced( weapon ) )
        {
            aTarget   = GetCachedArray( g_tIdleSilenced,   szModel );
            aFallback = GetCachedArray( g_tIdleGeneric,    szModel );
            aOpposite = GetCachedArray( g_tIdleUnsilenced, szModel );
        }
        else
        {
            aTarget   = GetCachedArray( g_tIdleUnsilenced, szModel );
            aFallback = GetCachedArray( g_tIdleGeneric,    szModel );
            aOpposite = GetCachedArray( g_tIdleSilenced,   szModel );
        }
    }
    else
    {
        aTarget = GetCachedArray( g_tIdleGeneric, szModel );
    }

    if ( aTarget != Invalid_Array && ArraySize( aTarget ) > 0 )
    {
        iSeq = ArrayGetCell( aTarget, random_num( 0, ArraySize( aTarget ) - 1 ) );
    }
    else if ( aFallback != Invalid_Array && ArraySize( aFallback ) > 0 )
    {
        iSeq = ArrayGetCell( aFallback, random_num( 0, ArraySize( aFallback ) - 1 ) );
    }
    else if ( aOpposite != Invalid_Array && ArraySize( aOpposite ) > 0 )
    {
        iSeq = ArrayGetCell( aOpposite, random_num( 0, ArraySize( aOpposite ) - 1 ) );
    }

    if ( iSeq == -1 )
    {
        return false;
    }

    return GetSequenceDurationByIndex( szModel, iSeq, fDuration );
}

stock Array:GetCachedArray( Trie:hTrie, const szModel[ ] )
{
    new Array:aData = Invalid_Array;

    if ( !TrieGetCell( hTrie, szModel, aData ) )
    {
        return Invalid_Array;
    }

    return aData;
}

// ========================================================================
//  SILENCER HELPERS
// ========================================================================
stock bool:IsSilenceAwareWeapon( const weapon )
{
    if ( !pev_valid( weapon ) )
    {
        return false;
    }

    new wpn_id = cs_get_weapon_id( weapon );

    return ( wpn_id == CSW_M4A1 || wpn_id == CSW_USP );
}

stock bool:IsWeaponSilenced( const weapon )
{
    if ( !pev_valid( weapon ) )
    {
        return false;
    }

    new wpn_id = cs_get_weapon_id( weapon );

    if ( wpn_id == CSW_M4A1 || wpn_id == CSW_USP )
    {
        return ( cs_get_weapon_silen( weapon ) == 1 );
    }

    return false;
}

// ========================================================================
//  SEQUENCE NAME ANALYSIS
// ========================================================================
stock bool:IsSilencerActionSequence( const szName[ ] )
{
    for ( new i = 0; i < sizeof( g_szSilencerActions ); i++ )
    {
        if ( containi( szName, g_szSilencerActions[ i ] ) != -1 )
        {
            return true;
        }
    }

    return false;
}

stock bool:IsInspectKeyword( const szName[ ] )
{
    if ( g_iInspectKeywordCount == 0 )
    {
        return false;
    }

    new szKw[ KEYWORD_MAX_LEN ];

    for ( new i = 0; i < g_iInspectKeywordCount; i++ )
    {
        ArrayGetString( g_aInspectKeywords, i, szKw, charsmax( szKw ) );

        if ( containi( szName, szKw ) != -1 )
        {
            return true;
        }
    }

    return false;
}

stock bool:IsIdleKeyword( const szName[ ] )
{
    return ( containi( szName, "idle" ) != -1 );
}

stock SilencerState:DetectSilencerSuffix( const szName[ ] )
{
    if ( containi( szName, "_unsil" ) != -1 )
    {
        return SIL_OFF;
    }

    if ( containi( szName, "_sil" ) != -1 )
    {
        return SIL_ON;
    }

    return SIL_NONE;
}

stock NormalizeSequenceName( const szInput[ ], szOutput[ ], const iLen )
{
    new szTemp[ SEQ_NAME_LEN ];
    new szTemp2[ SEQ_NAME_LEN ];

    RemoveWeaponPrefix( szInput, szTemp, charsmax( szTemp ) );
    RemoveSilencerSuffix( szTemp, szTemp2, charsmax( szTemp2 ) );
    RemoveNumericSuffix( szTemp2, szOutput, iLen );
}

stock RemoveWeaponPrefix( const szInput[ ], szOutput[ ], const iLen )
{
    new iPos = strfind( szInput, "_" );

    if ( iPos == -1 || iPos >= 16 )
    {
        copy( szOutput, iLen, szInput );
        return;
    }

    if ( IsInspectKeyword( szInput[ iPos + 1 ] ) || IsIdleKeyword( szInput[ iPos + 1 ] ) )
    {
        copy( szOutput, iLen, szInput[ iPos + 1 ] );
        return;
    }

    copy( szOutput, iLen, szInput );
}

stock RemoveSilencerSuffix( const szInput[ ], szOutput[ ], const iLen )
{
    copy( szOutput, iLen, szInput );

    new iPos = containi( szOutput, "_unsil" );

    if ( iPos != -1 )
    {
        szOutput[ iPos ] = EOS;
        return;
    }

    iPos = containi( szOutput, "_sil" );

    if ( iPos != -1 )
    {
        szOutput[ iPos ] = EOS;
        return;
    }
}

stock RemoveNumericSuffix( const szInput[ ], szOutput[ ], const iLen )
{
    copy( szOutput, iLen, szInput );

    new iStrLen = strlen( szOutput );

    for ( new i = iStrLen - 1; i >= 0; i-- )
    {
        if ( !( '0' <= szOutput[ i ] <= '9' ) )
        {
            break;
        }

        szOutput[ i ] = EOS;
    }
}

// ========================================================================
//  MODEL PARSING (LOW LEVEL)
// ========================================================================
stock bool:GetAllSequenceNames( const szModel[ ], &Array:aSeqNames, &iCount )
{
    iCount = 0;
    aSeqNames = Invalid_Array;

    new iSeqCount;
    new iSeqIndex;

    if ( !ReadStudioSequenceTable( szModel, iSeqCount, iSeqIndex ) )
    {
        return false;
    }

    new f = fopen( szModel, "rb" );

    if ( !f || fseek( f, iSeqIndex, SEEK_SET ) != 0 )
    {
        if ( f )
        {
            fclose( f );
        }

        return false;
    }

    aSeqNames = ArrayCreate( SEQ_NAME_LEN, iSeqCount );

    if ( aSeqNames == Invalid_Array )
    {
        fclose( f );
        return false;
    }

    new szName[ SEQ_NAME_LEN ];

    for ( new i = 0; i < iSeqCount; i++ )
    {
        if ( fread_blocks( f, szName, SEQ_LABEL_BYTES, BLOCK_CHAR ) != SEQ_LABEL_BYTES )
        {
            fclose( f );
            ArrayDestroy( aSeqNames );
            aSeqNames = Invalid_Array;
            return false;
        }

        szName[ SEQ_LABEL_BYTES ] = EOS;
        ArrayPushString( aSeqNames, szName );

        if ( fseek( f, STUDIO_SEQDESC_SIZE - SEQ_LABEL_BYTES, SEEK_CUR ) != 0 )
        {
            fclose( f );
            ArrayDestroy( aSeqNames );
            aSeqNames = Invalid_Array;
            return false;
        }
    }

    fclose( f );

    iCount = ArraySize( aSeqNames );

    if ( iCount <= 0 )
    {
        ArrayDestroy( aSeqNames );
        aSeqNames = Invalid_Array;
        return false;
    }

    return true;
}

stock bool:GetSequenceDurationByIndex( const szModel[ ], const iSeq, &Float:fDuration )
{
    fDuration = 0.0;

    new iSeqCount;
    new iSeqIndex;

    if ( !ReadStudioSequenceTable( szModel, iSeqCount, iSeqIndex )
        || iSeq < 0
        || iSeq >= iSeqCount )
    {
        return false;
    }

    new f = fopen( szModel, "rb" );

    if ( !f )
    {
        return false;
    }

    new iDescriptor = iSeqIndex + ( iSeq * STUDIO_SEQDESC_SIZE );
    new iFpsRaw;
    new iFrames;

    if ( fseek( f, iDescriptor + STUDIO_SEQDESC_FPS, SEEK_SET ) != 0
        || fread( f, iFpsRaw, BLOCK_INT ) != 1
        || fseek( f, iDescriptor + STUDIO_SEQDESC_FRAMES, SEEK_SET ) != 0
        || fread( f, iFrames, BLOCK_INT ) != 1 )
    {
        fclose( f );
        return false;
    }

    fclose( f );

    if ( iFrames < 1 || iFrames > 10000 )
    {
        return false;
    }

    new Float:fFps = Float:iFpsRaw;

    if ( !( fFps >= 1.0 && fFps <= 200.0 ) )
    {
        fFps = 30.0;
    }

    fDuration = float( iFrames ) / fFps;

    return true;
}

stock GetModelNumSeqCached( const szModel[ ] )
{
    new v;

    if ( TrieGetCell( g_tModelNumSeq, szModel, v ) )
    {
        return v;
    }

    new iNum = 0;

    if ( GetModelNumSeq( szModel, iNum ) )
    {
        TrieSetCell( g_tModelNumSeq, szModel, iNum );
        return iNum;
    }

    TrieSetCell( g_tModelNumSeq, szModel, 0 );
    return 0;
}

stock bool:GetModelNumSeq( const szModel[ ], &iNumSeq )
{
    iNumSeq = 0;

    new iSeqIndex;

    if ( !ReadStudioSequenceTable( szModel, iNumSeq, iSeqIndex ) )
    {
        iNumSeq = 0;
        return false;
    }

    return true;
}

// ========================================================================
//  TRIE CACHE CLEANUP
// ========================================================================
stock CleanupTrieCache( Trie:hTrie )
{
    if ( hTrie == Invalid_Trie )
    {
        return;
    }

    new Snapshot:hSnap = TrieSnapshotCreate( hTrie );
    new iLen = TrieSnapshotLength( hSnap );

    new szKey[ MODEL_PATH_LEN ];
    new Array:aData;

    for ( new i = 0; i < iLen; i++ )
    {
        TrieSnapshotGetKey( hSnap, i, szKey, charsmax( szKey ) );

        if ( TrieGetCell( hTrie, szKey, aData ) )
        {
            if ( aData != Invalid_Array )
            {
                ArrayDestroy( aData );
            }
        }
    }

    TrieSnapshotDestroy( hSnap );
}

// ========================================================================
//  KEYWORD LOADING
// ========================================================================
stock bool:ReadCompleteConfigLine( const f, szLine[ ], const iLen )
{
    // AMXX reads each physical line into an internal 4096-byte C buffer
    // before copying it to Pawn. Match that size here so a long line cannot
    // make us consume the following valid line while discarding truncation.
    static szRawLine[ 4096 ];

    if ( !fgets( f, szRawLine, charsmax( szRawLine ) ) )
    {
        return false;
    }

    if ( contain( szRawLine, "^n" ) == -1 && !feof( f ) )
    {
        while ( fgets( f, szRawLine, charsmax( szRawLine ) ) )
        {
            if ( contain( szRawLine, "^n" ) != -1 || feof( f ) )
            {
                break;
            }
        }

        // Reject a truncated logical line instead of parsing its fragments.
        szLine[ 0 ] = EOS;
        return true;
    }

    new iRawLen = strlen( szRawLine );

    while ( iRawLen > 0 && ( szRawLine[ iRawLen - 1 ] == '^n' || szRawLine[ iRawLen - 1 ] == '^r' ) )
    {
        szRawLine[ --iRawLen ] = EOS;
    }

    if ( iRawLen > iLen )
    {
        // Reject the complete overlong line rather than parsing a prefix.
        szLine[ 0 ] = EOS;
        return true;
    }

    copy( szLine, iLen, szRawLine );

    return true;
}

stock LoadInspectKeywords( )
{
    new szConfigDir[ 128 ];
    get_configsdir( szConfigDir, charsmax( szConfigDir ) );

    new szFilePath[ 256 ];
    formatex( szFilePath, charsmax( szFilePath ), "%s/inspect_list.ini", szConfigDir );

    if ( !file_exists( szFilePath ) )
    {
        LoadDefaultKeywords( );
        CreateDefaultConfigFile( szFilePath );
        return;
    }

    new f = fopen( szFilePath, "rt" );

    if ( !f )
    {
        LoadDefaultKeywords( );
        return;
    }

    new szLine[ 256 ];
    new szKeyword[ KEYWORD_MAX_LEN ];

    while ( ReadCompleteConfigLine( f, szLine, charsmax( szLine ) ) )
    {
        trim( szLine );

        if ( szLine[ 0 ] == EOS || szLine[ 0 ] == ';' || ( szLine[ 0 ] == '/' && szLine[ 1 ] == '/' ) )
        {
            continue;
        }

        new iKeywordLen = strlen( szLine );
        if ( iKeywordLen > 0 && iKeywordLen < KEYWORD_MAX_LEN )
        {
            copy( szKeyword, charsmax( szKeyword ), szLine );
            ArrayPushString( g_aInspectKeywords, szKeyword );
            g_iInspectKeywordCount++;

            if ( g_iInspectKeywordCount >= MAX_INSPECT_KEYWORDS )
            {
                break;
            }
        }
    }

    fclose( f );

    if ( g_iInspectKeywordCount == 0 )
    {
        LoadDefaultKeywords( );
        return;
    }
}

stock LoadDefaultKeywords( )
{
    ArrayPushString( g_aInspectKeywords, "inspect" );
    ArrayPushString( g_aInspectKeywords, "lookat" );
    ArrayPushString( g_aInspectKeywords, "examine" );
    ArrayPushString( g_aInspectKeywords, "check" );

    g_iInspectKeywordCount = 4;
}

stock CreateDefaultConfigFile( const szPath[ ] )
{
    new f = fopen( szPath, "wt" );

    if ( !f )
    {
        return;
    }

    fprintf( f, "; ============================================================^n" );
    fprintf( f, "; Weapon Inspector - Inspect Keyword Configuration^n" );
    fprintf( f, "; ============================================================^n" );
    fprintf( f, "; Keywords are case-insensitive. One per line.^n" );
    fprintf( f, "; Any sequence containing a keyword = inspect animation.^n" );
    fprintf( f, "; Lines starting with ';' or '//' are comments.^n" );
    fprintf( f, "; ============================================================^n^n" );

    fprintf( f, "inspect^n" );
    fprintf( f, "lookat^n" );
    fprintf( f, "examine^n" );
    fprintf( f, "check^n^n" );

    fprintf( f, "; Add custom keywords below:^n" );
    fprintf( f, "; view^n" );
    fprintf( f, "; admire^n^n" );

    fclose( f );
}

// ========================================================================
//  MODEL RULES (INI) - weapon_inspector_models.ini
// ========================================================================
stock LoadModelRules( )
{
    new szConfigDir[ 128 ];
    get_configsdir( szConfigDir, charsmax( szConfigDir ) );

    new szPath[ 256 ];
    formatex( szPath, charsmax( szPath ), "%s/weapon_inspector_models.ini", szConfigDir );

    if ( !file_exists( szPath ) )
    {
        CreateDefaultModelRulesFile( szPath );
        return;
    }

    new f = fopen( szPath, "rt" );

    if ( !f )
    {
        return;
    }

    new szLine[ 256 ];
    new szSection[ MODEL_PATH_LEN ];
    szSection[ 0 ] = EOS;

    while ( ReadCompleteConfigLine( f, szLine, charsmax( szLine ) ) )
    {
        trim( szLine );

        if ( szLine[ 0 ] == EOS || szLine[ 0 ] == ';' || ( szLine[ 0 ] == '/' && szLine[ 1 ] == '/' ) )
        {
            continue;
        }

        // [ model/path.mdl ]
        if ( szLine[ 0 ] == '[' )
        {
            ParseIniSection( szLine, szSection, charsmax( szSection ) );
            continue;
        }

        if ( szSection[ 0 ] == EOS )
        {
            continue;
        }

        // KEY = VALUE
        new szKey[ 64 ], szVal[ 64 ];
        if ( !ParseIniKeyValue( szLine, szKey, charsmax( szKey ), szVal, charsmax( szVal ) ) )
        {
            continue;
        }

        if ( equali( szKey, "AUTO_INSPECT" ) )
        {
            TrieSetCell( g_tRuleAutoInspect, szSection, clamp( str_to_num( szVal ), 0, 1 ) );
        }
        else if ( equali( szKey, "MANUAL_INSPECT" ) )
        {
            TrieSetCell( g_tRuleManualInspect, szSection, clamp( str_to_num( szVal ), 0, 1 ) );
        }
        else if ( equali( szKey, "IDLE_LOOP_TIME" ) )
        {
            new Float:fVal = str_to_float( szVal );
            if ( fVal < 0.0 ) fVal = 0.0;

            TrieSetCell( g_tRuleIdleLoopTime, szSection, _:fVal );
        }
        else if ( equali( szKey, "IDLE_SEQ_FORCE" ) )
        {
            TrieSetCell( g_tRuleIdleSeqForce, szSection, str_to_num( szVal ) );
        }
    }

    fclose( f );
}

stock CreateDefaultModelRulesFile( const szPath[ ] )
{
    new f = fopen( szPath, "wt" );

    if ( !f )
    {
        return;
    }

    fprintf( f, "; ------------------------------------------------------------^n" );
    fprintf( f, "; Weapon Inspector - Per-Model Rules^n" );
    fprintf( f, "; ------------------------------------------------------------^n" );
    fprintf( f, "; AUTO_INSPECT    = 0/1  (0 blocks baked auto-inspect via controlled idle loop)^n" );
    fprintf( f, "; MANUAL_INSPECT  = 0/1  (0 blocks manual inspect: command/impulse)^n" );
    fprintf( f, "; IDLE_LOOP_TIME  = float seconds (enable only if AUTO_INSPECT = 0)^n" );
    fprintf( f, "; IDLE_SEQ_FORCE  = -1 auto / >=0 force sequence index for idle-loop^n" );
    fprintf( f, ";^n" );
    fprintf( f, "; NOTE: If a model has only 1 idle and it's mixed with inspect, you MUST set^n" );
    fprintf( f, ";       IDLE_LOOP_TIME to a small value to keep idles looping before the inspect part.^n" );
    fprintf( f, "; ------------------------------------------------------------^n^n" );

    fprintf( f, ";EXAMPLE:^n" );
    fprintf( f, ";[ models/custom/v_ak47.mdl ]^n" );
    fprintf( f, ";AUTO_INSPECT    = 0^n" );
    fprintf( f, ";MANUAL_INSPECT  = 1^n" );
    fprintf( f, ";IDLE_SEQ_FORCE  = -1^n" );
    fprintf( f, ";IDLE_LOOP_TIME  = 0.80^n^n" );

    fclose( f );
}

stock ParseIniSection( const szLine[ ], szOut[ ], const iLen )
{
    szOut[ 0 ] = EOS;

    new iStart = contain( szLine, "[" );
    new iEnd   = contain( szLine, "]" );

    if ( iStart != 0 || iEnd <= iStart + 1 )
    {
        return;
    }

    new iSectionLen = iEnd - iStart - 1;

    if ( iSectionLen > iLen )
    {
        return;
    }

    copy( szOut, iSectionLen, szLine[ iStart + 1 ] );
    trim( szOut );
}

stock bool:ParseIniKeyValue( const szLine[ ], szKey[ ], const iKeyLen, szVal[ ], const iValLen )
{
    szKey[ 0 ] = EOS;
    szVal[ 0 ] = EOS;

    new iEq = contain( szLine, "=" );
    if ( iEq <= 0 || iEq > iKeyLen )
    {
        return false;
    }

    copy( szKey, iEq, szLine );
    trim( szKey );

    copy( szVal, iValLen, szLine[ iEq + 1 ] );
    trim( szVal );

    // strip inline comments ';' or '//' (simple)
    new iCom = contain( szVal, ";" );
    if ( iCom != -1 )
    {
        szVal[ iCom ] = EOS;
        trim( szVal );
    }

    iCom = contain( szVal, "//" );
    if ( iCom != -1 )
    {
        szVal[ iCom ] = EOS;
        trim( szVal );
    }

    return ( szKey[ 0 ] != EOS && szVal[ 0 ] != EOS );
}

// Small utility: count keys in a Trie (for status printing)
stock TrieCountCells( Trie:hTrie )
{
    if ( hTrie == Invalid_Trie )
    {
        return 0;
    }

    new Snapshot:hSnap = TrieSnapshotCreate( hTrie );
    new iLen = TrieSnapshotLength( hSnap );
    TrieSnapshotDestroy( hSnap );

    return iLen;
}
