-- UTAC Config.lua — Constants and data tables (no Osi/MCM at load time)
local Config = {}

-- === Triage / healer ===
Config.TRIAGE_RADIUS_M = 20  -- allies within this distance count for urgent triage

-- === Combat status maps ===
Config.CombatStatusMap = {
    ["UTAC_BRUISER"]        = "UTAC_BRUISER_COMBAT",
    ["UTAC_MARKSMAN"]       = "UTAC_MARKSMAN_COMBAT",
    ["UTAC_PROTECTOR"]      = "UTAC_PROTECTOR_COMBAT",
    ["UTAC_HEALER"]         = "UTAC_HEALER_COMBAT",
    ["UTAC_SKIRMISHER"]     = "UTAC_SKIRMISHER_COMBAT",
    ["UTAC_ASSASSIN"]       = "UTAC_ASSASSIN_COMBAT",
    ["UTAC_GENERAL"]        = "UTAC_GENERAL_COMBAT",
    ["UTAC_SUMMON"]         = "UTAC_SUMMON_COMBAT",
    ["UTAC_AOE_SPECIALIST"] = "UTAC_AOE_SPECIALIST_COMBAT",
    ["UTAC_SPELLCASTER"]    = "UTAC_SPELLCASTER_COMBAT",
}

-- NPC-mode combat status variants (no LoseControl, used with MakeNPC)
Config.CombatStatusNPCMap = {
    ["UTAC_BRUISER"]        = "UTAC_BRUISER_COMBAT_NPC",
    ["UTAC_MARKSMAN"]       = "UTAC_MARKSMAN_COMBAT_NPC",
    ["UTAC_PROTECTOR"]      = "UTAC_PROTECTOR_COMBAT_NPC",
    ["UTAC_HEALER"]         = "UTAC_HEALER_COMBAT_NPC",
    ["UTAC_SKIRMISHER"]     = "UTAC_SKIRMISHER_COMBAT_NPC",
    ["UTAC_ASSASSIN"]       = "UTAC_ASSASSIN_COMBAT_NPC",
    ["UTAC_GENERAL"]        = "UTAC_GENERAL_COMBAT_NPC",
    ["UTAC_SUMMON"]         = "UTAC_SUMMON_COMBAT_NPC",
    ["UTAC_AOE_SPECIALIST"] = "UTAC_AOE_SPECIALIST_COMBAT_NPC",
    ["UTAC_SPELLCASTER"]    = "UTAC_SPELLCASTER_COMBAT_NPC",
}

Config.NPCStatusSet = {}
for _, npcStatus in pairs(Config.CombatStatusNPCMap) do
    Config.NPCStatusSet[npcStatus] = true
end

function Config.IsNPCCombatStatus(status)
    return Config.NPCStatusSet[status] == true
end

Config.SculptSpellsHelperStatus = "UTAC_SCULPT_SPELLS_HELPER"

-- === Status → archetype and helpers ===
Config.StatusToArchetype = {
    UTAC_BRUISER        = { Arch = "Melee_Bruiser",    Helpers = { "AI_BRUISER_BLOODLUST" } },
    UTAC_SKIRMISHER     = { Arch = "Melee_Skirmisher",  Helpers = { "AI_SKIRMISHER_MOMENTUM" } },
    UTAC_ASSASSIN       = { Arch = "Hybrid_Assassin",   Helpers = { "AI_ASSASSIN_HUNTER", "AI_ASSASSIN_ISOLATION_BONUS" } },
    UTAC_MARKSMAN       = { Arch = "Ranged_Marksman",   Helpers = { "AI_MARKSMAN_DEADEYE", "AI_MARKSMAN_KITING" } },
    UTAC_HEALER         = { Arch = "Support_Healer",    Helpers = { "AI_HEALER_SANCTUARY" } },
    UTAC_PROTECTOR      = { Arch = "Protector",         Helpers = { "AI_PROTECTOR_GUARDIAN" } },
    UTAC_AOE_SPECIALIST = { Arch = "AoE_Specialist",    Helpers = { "AI_AOE_DEVASTATOR" } },
    UTAC_SPELLCASTER    = { Arch = "Spellcaster",       Helpers = { "AI_SPELLCASTER_FOCUS" } },
    UTAC_GENERAL        = { Arch = "General_AI",        Helpers = { "AI_GENERAL_ADAPTIVE" } },
    UTAC_SUMMON         = { Arch = "Summon_AI" },
}

-- Master list of temporary helper statuses the AI brain can apply
Config.TemporaryHelpers = {
    "AI_HELPER_MINDSANCTUARY", "AI_HELPER_BUFF_MASSIVE", "AI_HELPER_BUFF_LARGE", "AI_HELPER_BUFF_SMALL",
    "AI_HELPER_LONGJUMP", "AI_HELPER_TRUESTRIKE",
    "UTAC_ENCOURAGE_ABILITIES", "UTAC_ENCOURAGE_CONSUMABLES", "UTAC_ENCOURAGE_SPELLS",
}

Config.AllPermanentHelpers = {
    "AI_BRUISER_BLOODLUST", "AI_SKIRMISHER_MOMENTUM", "AI_ASSASSIN_HUNTER", "AI_ASSASSIN_ISOLATION_BONUS",
    "AI_MARKSMAN_DEADEYE", "AI_MARKSMAN_KITING", "AI_HEALER_SANCTUARY", "AI_PROTECTOR_GUARDIAN",
    "AI_AOE_DEVASTATOR", "AI_SPELLCASTER_FOCUS", "AI_GENERAL_ADAPTIVE",
    "AI_BRUISER_BLOODLUST_ENHANCED", "AI_SPELLCASTER_FOCUS_ENHANCED",
}

-- === AI-only spell variants ===
Config.UTAC_SpellMappings = {
    Shout_Dash             = "Shout_UTAC_Dash_AI",
    Shout_Dash_BonusAction = "Shout_UTAC_Dash_BonusAction_AI",
}

-- === Healer presets (values only; UTACSettings.lua is the runtime owner) ===
Config.PRESETS = {
    [0] = { name = "Default", values = nil },
    [1] = { name = "Defensive Healer", values = {
        Healer_TriageThreshold = 70,
        ConserveHighSlots = true,
        ConserveHighSlots_MinLevel = 3,
        ConserveHighSlots_AllowEnemiesAtLeast = 2,
    }},
    [2] = { name = "Proactive Healer", values = {
        Healer_TriageThreshold = 55,
        ConserveHighSlots = false,
        ConserveHighSlots_MinLevel = 3,
        ConserveHighSlots_AllowEnemiesAtLeast = 1,
    }},
    [3] = { name = "Battle Cleric", values = {
        Healer_TriageThreshold = 45,
        ConserveHighSlots = false,
        ConserveHighSlots_MinLevel = 2,
        ConserveHighSlots_AllowEnemiesAtLeast = 0,
    }},
}

-- Pure helper: number or zero/fallback
function Config.NZ(n, f)
    return (type(n) == "number") and n or (f or 0)
end

return Config
