-- UTACSpellPolicy.lua
-- UTAC-scoped optional spell blocking and normal spell-slot limiter.

local SpellPolicy = {}

local SPELL_POLICY_STATUS = "UTAC_SPELL_POLICY_BLOCKED"
local SPELL_POLICY_OLD_REQUIREMENT_GATE = "not HasStatus('UTAC_SPELL_POLICY_BLOCKED')"
local SPELL_POLICY_OLD_TARGET_GATE = "not HasStatus('UTAC_SPELL_POLICY_BLOCKED', context.Source)"
local SPELL_POLICY_CASTER_GATE = "not HasStatus('UTAC_SPELL_POLICY_BLOCKED', context:Self)"
local SPELL_POLICY_UTAC_ALLY_GATE = "not HasStatus('UTAC_ALLY')"
local SPELL_POLICY_UTAC_ALLY_SOURCE_GATE = "not HasStatus('UTAC_ALLY', context.Source)"
local SPELL_POLICY_OLD_COMBAT_GATE = "not HasStatus('UTAC_ALLY') or not Combat()"
local SPELL_POLICY_OLD_COMBINED_GATE = "(not HasStatus('UTAC_SPELL_POLICY_BLOCKED')) and (not HasStatus('UTAC_ALLY') or not Combat())"
local SPELL_POLICY_SOURCE_MARKER_GATE = "not HasStatus('UTAC_SPELL_POLICY_BLOCKED', context.Source)"
local SPELL_POLICY_SOURCE_COMBAT_GATE = "not HasStatus('UTAC_ALLY', context.Source) or not Combat(context.Source)"
local SPELL_POLICY_MARKER_GATE = "(" .. SPELL_POLICY_SOURCE_MARKER_GATE .. ") and (" .. SPELL_POLICY_SOURCE_COMBAT_GATE .. ")"
local SPELL_POLICY_TAC_GATE = SPELL_POLICY_UTAC_ALLY_GATE
local PATCH_FIELD_GATES = {
    RequirementConditions = SPELL_POLICY_TAC_GATE,
}
local CLEANUP_FIELDS = { "RequirementConditions", "TargetConditions" }
local KNOWN_POLICY_GATES = {
    SPELL_POLICY_OLD_REQUIREMENT_GATE,
    SPELL_POLICY_OLD_TARGET_GATE,
    SPELL_POLICY_CASTER_GATE,
    SPELL_POLICY_UTAC_ALLY_GATE,
    SPELL_POLICY_UTAC_ALLY_SOURCE_GATE,
    SPELL_POLICY_OLD_COMBAT_GATE,
    SPELL_POLICY_OLD_COMBINED_GATE,
    SPELL_POLICY_SOURCE_MARKER_GATE,
    SPELL_POLICY_SOURCE_COMBAT_GATE,
    SPELL_POLICY_MARKER_GATE,
    SPELL_POLICY_TAC_GATE,
}

local SLOT_LIMIT_STATUSES = {
    [2] = "UTAC_SLOT_LIMIT_L2_PLUS",
    [3] = "UTAC_SLOT_LIMIT_L3_PLUS",
    [4] = "UTAC_SLOT_LIMIT_L4_PLUS",
    [5] = "UTAC_SLOT_LIMIT_L5_PLUS",
    [6] = "UTAC_SLOT_LIMIT_L6_PLUS",
}

local DEFAULT_BLOCKED_SPELLS = {
    "Shout_FeatherFall",
    "Target_FogCloud",
    "Target_BlessingOfTheTrickster",
}

local TURN_SCOPED_THROW_BLOCK_SPELLS = {
    "Throw_Throw",
    "Throw_ImprovisedWeapon",
    "Throw_FrenziedThrow",
}

local SPELL_POLICY_PREFIXES = {
    "Projectile",
    "Target",
    "Shout",
    "Zone",
    "Rush",
    "Teleportation",
    "ProjectileStrike",
}

local SPELL_POLICY_UPCAST_SUFFIXES = { "_2", "_3", "_4", "_5", "_6" }

local SPELL_POLICY_ALIASES = {
    magicmissile = {
        "Projectile_MagicMissile",
        "Projectile_MagicMissile_2",
        "Projectile_MagicMissile_3",
        "Projectile_MagicMissile_4",
        "Projectile_MagicMissile_5",
        "Projectile_MagicMissile_6",
        "Projectile_UND_MagicMissile_SocietyOfBrilliance_Amulet",
        "Projectile_MAG_MagicMissile_Shot",
        "Projectile_LOW_Rolan_MagicMissile",
    },
    projectile_magicmissile = {
        "Projectile_MagicMissile",
        "Projectile_MagicMissile_2",
        "Projectile_MagicMissile_3",
        "Projectile_MagicMissile_4",
        "Projectile_MagicMissile_5",
        "Projectile_MagicMissile_6",
        "Projectile_UND_MagicMissile_SocietyOfBrilliance_Amulet",
        "Projectile_MAG_MagicMissile_Shot",
        "Projectile_LOW_Rolan_MagicMissile",
    },
    target_magicmissile = {
        "Projectile_MagicMissile",
        "Projectile_MagicMissile_2",
        "Projectile_MagicMissile_3",
        "Projectile_MagicMissile_4",
        "Projectile_MagicMissile_5",
        "Projectile_MagicMissile_6",
        "Projectile_UND_MagicMissile_SocietyOfBrilliance_Amulet",
        "Projectile_MAG_MagicMissile_Shot",
        "Projectile_LOW_Rolan_MagicMissile",
    },
}

local CASTER_ARCHETYPES = {
    Spellcaster = true,
    AoE_Specialist = true,
    Support_Healer = true,
    General_AI = true,
}

local deps = {}
local state = {
    initialized = false,
    spellPolicyEnabled = false,
    slotLimiterEnabled = false,
    slotMinLevel = 3,
    slotAllowEnemies = 3,
    blockedSpells = {},
    blockedSet = {},
    blockedSourceBySpell = {},
    blockedTailByPrefix = {},
    unresolvedBlockedSpells = {},
    patchedSpells = {},
    originalAIFlagsBySpell = {},
    strippedByKey = {},
    slotStatusByKey = {},
    blockedAttempts = {},
    turnAIFlagOwnerKey = nil,
    turnAIFlagOwnerCharacter = nil,
    turnAIFlagOwnerLabel = nil,
    turnAIFlagActive = false,
    consoleRegistered = false,
}

local function Log(...)
    if type(deps.InfoPrint) == "function" then
        deps.InfoPrint(...)
    end
end

local function IsModEnabled()
    if type(deps.IsModEnabled) == "function" then
        return deps.IsModEnabled() == true
    end
    return true
end

local function Normalize(character)
    if type(deps.CC_Normalize) == "function" then
        local ok, key = pcall(deps.CC_Normalize, character)
        if ok then return key end
    end
    return character and tostring(character) or nil
end

local function Exists(character)
    if not character or character == "" or not Osi or type(Osi.Exists) ~= "function" then
        return false
    end
    local ok, exists = pcall(Osi.Exists, character)
    return ok and exists == 1
end

local function IsInCombat(character)
    if not character or character == "" or not Osi or type(Osi.IsInCombat) ~= "function" then
        return false
    end
    local ok, inCombat = pcall(Osi.IsInCombat, character)
    return ok and inCombat == 1
end

local function HasStatus(character, status)
    if not character or character == "" or not status then
        return false
    end
    if type(deps.HasStatusSafe) == "function" then
        local ok, hasStatus = pcall(deps.HasStatusSafe, character, status)
        if ok then return hasStatus == true end
    end
    if Osi and type(Osi.HasActiveStatus) == "function" then
        local ok, hasStatus = pcall(Osi.HasActiveStatus, character, status)
        return ok and hasStatus == 1
    end
    return false
end

local function ApplyStatus(character, status)
    if not character or character == "" or not status then
        return false
    end
    if HasStatus(character, status) then
        return true
    end

    -- Some Osiris status applications return successfully even when the status
    -- does not land, so confirm before treating limiter statuses as applied.
    local attempts = {
        function()
            if Osi and type(Osi.ApplyStatus) == "function" then
                return pcall(Osi.ApplyStatus, character, status, -1, 1)
            end
            return false
        end,
        function()
            if Osi and type(Osi.ApplyStatus) == "function" then
                return pcall(Osi.ApplyStatus, character, status, -1)
            end
            return false
        end,
        function()
            if type(_G.ApplyStatus) == "function" then
                return pcall(_G.ApplyStatus, character, status, -1, 1)
            end
            return false
        end,
        function()
            if type(_G.ApplyStatus) == "function" then
                return pcall(_G.ApplyStatus, character, status, -1)
            end
            return false
        end,
        function()
            if type(deps.ApplyStatusIfMissing) == "function" then
                return pcall(deps.ApplyStatusIfMissing, character, status, -1)
            end
            return false
        end,
    }

    for _, attempt in ipairs(attempts) do
        attempt()
        if HasStatus(character, status) then
            return true
        end
    end

    return false
end

local function RemoveStatus(character, status)
    if not character or character == "" or not status then
        return false
    end
    local hadStatus = HasStatus(character, status)
    if type(deps.RemoveStatusIfPresent) == "function" then
        pcall(deps.RemoveStatusIfPresent, character, status)
    elseif Osi and type(Osi.RemoveStatus) == "function" and hadStatus then
        pcall(Osi.RemoveStatus, character, status)
    end
    return hadStatus
end

local function GetStatusTargets(character)
    local key = Normalize(character)
    if type(deps.ResolveCharacterHandle) == "function" and type(deps.GetStatusTargetVariants) == "function" then
        local ok, liveCharacter = pcall(deps.ResolveCharacterHandle, character)
        if ok then
            local okTargets, targets = pcall(deps.GetStatusTargetVariants, character, liveCharacter, key)
            if okTargets and type(targets) == "table" then
                return targets, key
            end
        end
    end
    return { character, key }, key
end

local function GetLiveTarget(character)
    local targets = GetStatusTargets(character)
    for _, target in ipairs(targets or {}) do
        if target and target ~= "" and Exists(target) then
            return target
        end
    end
    return character
end

local function IsUTACControlled(character)
    if type(deps.IsUTACControlled) == "function" then
        local ok, controlled = pcall(deps.IsUTACControlled, character)
        if ok and controlled == true then
            return true
        end
    end
    local key = Normalize(character)
    if key and _G.UTAC_Companions and _G.UTAC_Companions[key] == true then
        return true
    end
    if HasStatus(character, "UTAC_IS_CONTROLLED") or (key and key ~= character and HasStatus(key, "UTAC_IS_CONTROLLED")) then
        return true
    end
    return false
end

local function GetBool(settingId, fallback)
    if type(deps.GetMCM_Bool) == "function" then
        return deps.GetMCM_Bool(settingId, fallback) == true
    end
    return fallback == true
end

local function DebugLoggingEnabled()
    return GetBool("MCM_DebugLogging", false) == true
end

local function GetNumber(settingId, fallback)
    if type(deps.GetMCM_Number) == "function" then
        local value = deps.GetMCM_Number(settingId, fallback)
        return tonumber(value) or fallback
    end
    return fallback
end

local function NormalizeListEntries(value)
    local out = {}
    if type(value) ~= "table" then
        return out
    end

    if type(value.settings) == "table" and value.settings.MCM_UTACBlockedSpellList ~= nil then
        value = value.settings.MCM_UTACBlockedSpellList
    end
    if type(value.Default) == "table" then
        value = value.Default
    end
    if type(value) ~= "table" then
        return out
    end

    local elements = value.elements or value.list or value.values or value.value or value
    if type(elements) ~= "table" then
        return out
    end

    local globallyEnabled = value.enabled ~= false
    local function addEntry(entry, key)
        local name = nil
        local enabled = globallyEnabled
        if type(entry) == "string" then
            name = entry
        elseif type(entry) == "boolean" and entry == true and type(key) == "string" then
            name = key
        elseif type(entry) == "table" then
            name = entry.name or entry.value or entry.id or entry.Name or entry.Id
            enabled = globallyEnabled and entry.enabled ~= false
        end

        if enabled and type(name) == "string" then
            local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed ~= "" then
                table.insert(out, trimmed)
            end
        end
    end

    for key, entry in ipairs(elements) do
        addEntry(entry, key)
    end
    if #out == 0 then
        for key, entry in pairs(elements) do
            addEntry(entry, key)
        end
    end

    return out
end

local function HasBlockedListPayload(value)
    if type(value) ~= "table" then
        return false
    end
    if value[1] ~= nil then
        return true
    end
    if value.elements ~= nil or value.list ~= nil or value.values ~= nil or value.value ~= nil then
        return true
    end
    if type(value.Default) == "table" then
        return HasBlockedListPayload(value.Default)
    end
    if type(value.settings) == "table" and value.settings.MCM_UTACBlockedSpellList ~= nil then
        return HasBlockedListPayload(value.settings.MCM_UTACBlockedSpellList)
    end
    return false
end

local function GetMCMAPI()
    if not Mods then
        return nil
    end
    if Mods.BG3MCM and Mods.BG3MCM.MCMAPI and type(Mods.BG3MCM.MCMAPI.GetSettingValue) == "function" then
        return Mods.BG3MCM.MCMAPI
    end
    if Mods.UTAC and Mods.UTAC.MCMAPI and type(Mods.UTAC.MCMAPI.GetSettingValue) == "function" then
        return Mods.UTAC.MCMAPI
    end
    return nil
end

local function ReadLiveMCMBlockedSpellList()
    local mcmApi = GetMCMAPI()
    if mcmApi then
        local ok, list = pcall(function()
            return mcmApi:GetSettingValue("MCM_UTACBlockedSpellList", deps.ModuleUUID)
        end)
        if ok and type(list) == "table" and HasBlockedListPayload(list) then
            return NormalizeListEntries(list), true
        end
    end

    if MCM and MCM.List and type(MCM.List.GetEnabled) == "function" then
        local ok, list = pcall(MCM.List.GetEnabled, "MCM_UTACBlockedSpellList")
        if ok and type(list) == "table" and HasBlockedListPayload(list) then
            return NormalizeListEntries(list), true
        end
    end

    return nil, false
end

local function GetBlockedSpellList()
    local liveList, liveOk = ReadLiveMCMBlockedSpellList()
    if liveOk then
        return liveList
    end

    if deps.Settings and type(deps.Settings.GetList) == "function" then
        local ok, list = pcall(deps.Settings.GetList, "MCM_UTACBlockedSpellList", {
            enabled = true,
            elements = {
                { name = DEFAULT_BLOCKED_SPELLS[1], enabled = true },
                { name = DEFAULT_BLOCKED_SPELLS[2], enabled = true },
                { name = DEFAULT_BLOCKED_SPELLS[3], enabled = true },
            },
        })
        if ok and type(list) == "table" then
            return NormalizeListEntries(list)
        end
    end
    return DEFAULT_BLOCKED_SPELLS
end

local function EscapePattern(text)
    return tostring(text):gsub("([^%w])", "%%%1")
end

local function GetStat(spell)
    if not Ext or not Ext.Stats or type(Ext.Stats.Get) ~= "function" then
        return nil
    end
    local ok, stat = pcall(Ext.Stats.Get, spell)
    if ok then
        return stat
    end
    return nil
end

local function CanResolveStats()
    return Ext and Ext.Stats and type(Ext.Stats.Get) == "function"
end

local function AddUnique(list, seen, value)
    if type(value) ~= "string" or value == "" or seen[value] == true then
        return
    end
    seen[value] = true
    table.insert(list, value)
end

local function NormalizeSpellAliasKey(spell)
    if type(spell) ~= "string" then
        return ""
    end
    return spell:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", ""):lower()
end

local function HasKnownSpellPrefix(spell)
    if type(spell) ~= "string" then
        return false
    end
    for _, prefix in ipairs(SPELL_POLICY_PREFIXES) do
        if spell:find("^" .. prefix .. "_") then
            return true
        end
    end
    return false
end

local function StripSpellVariantSuffix(spell)
    if type(spell) ~= "string" then
        return ""
    end
    local out = spell
    local changed = true
    while changed do
        changed = false
        local nextValue = out:gsub("_AI$", "")
        if nextValue ~= out then
            out = nextValue
            changed = true
        end
        nextValue = out:gsub("_%d$", "")
        if nextValue ~= out then
            out = nextValue
            changed = true
        end
    end
    return out
end

local function GetSpellPrefixAndTail(spell)
    if type(spell) ~= "string" then
        return nil, ""
    end
    local stripped = StripSpellVariantSuffix(spell:gsub("^%s+", ""):gsub("%s+$", ""))
    for _, prefix in ipairs(SPELL_POLICY_PREFIXES) do
        local marker = prefix .. "_"
        if stripped:sub(1, #marker) == marker then
            return prefix, stripped:sub(#marker + 1)
        end
    end
    return nil, stripped
end

local function TailMatches(candidateTail, blockedTail)
    if type(candidateTail) ~= "string" or type(blockedTail) ~= "string" or blockedTail == "" then
        return false
    end
    return candidateTail == blockedTail or candidateTail:sub(-(#blockedTail + 1)) == "_" .. blockedTail
end

local function AddUpcastCandidates(candidates, seen, spell)
    if type(spell) ~= "string" or spell == "" or spell:find("_%d$") then
        return
    end
    for _, suffix in ipairs(SPELL_POLICY_UPCAST_SUFFIXES) do
        AddUnique(candidates, seen, spell .. suffix)
    end
end

local function AddAICandidates(candidates, seen, spell)
    if type(spell) ~= "string" or spell == "" or spell:find("_AI$") then
        return
    end
    AddUnique(candidates, seen, spell .. "_AI")
    if not spell:find("_%d$") then
        for _, suffix in ipairs(SPELL_POLICY_UPCAST_SUFFIXES) do
            AddUnique(candidates, seen, spell .. suffix .. "_AI")
        end
    end
end

local function AddLoadedSpellDataTailCandidates(candidates, seen, spell)
    if not (Ext and Ext.Stats and type(Ext.Stats.GetStats) == "function") then
        return
    end

    local blockedPrefix, blockedTail = GetSpellPrefixAndTail(spell)
    if not blockedPrefix or blockedTail == "" then
        return
    end

    local ok, spellNames = pcall(Ext.Stats.GetStats, "SpellData")
    if not ok or type(spellNames) ~= "table" then
        return
    end

    for _, candidate in ipairs(spellNames) do
        local candidatePrefix, candidateTail = GetSpellPrefixAndTail(candidate)
        if candidatePrefix == blockedPrefix and TailMatches(candidateTail, blockedTail) then
            AddUnique(candidates, seen, candidate)
        end
    end
end

local function AddCombatAIOverrideCandidates(candidates, seen)
    local index = 1
    while index <= #candidates do
        local stat = GetStat(candidates[index])
        local override = stat and stat.CombatAIOverrideSpell or nil
        if type(override) == "string" and override ~= "" then
            AddUnique(candidates, seen, override)
            AddAICandidates(candidates, seen, override)
        end
        index = index + 1
    end
end

local function GetSpellPolicyCandidates(spell)
    local candidates = {}
    local seen = {}
    if type(spell) ~= "string" then
        return candidates
    end

    local trimmed = spell:gsub("^%s+", ""):gsub("%s+$", "")
    local compact = trimmed:gsub("%s+", "")
    local aliasKey = NormalizeSpellAliasKey(trimmed)

    AddUnique(candidates, seen, trimmed)
    if compact ~= trimmed then
        AddUnique(candidates, seen, compact)
    end

    local aliases = SPELL_POLICY_ALIASES[aliasKey]
    if aliases then
        for _, alias in ipairs(aliases) do
            AddUnique(candidates, seen, alias)
        end
    end

    if HasKnownSpellPrefix(compact) then
        AddUpcastCandidates(candidates, seen, compact)
    elseif compact ~= "" then
        for _, prefix in ipairs(SPELL_POLICY_PREFIXES) do
            local prefixed = prefix .. "_" .. compact
            AddUnique(candidates, seen, prefixed)
            AddUpcastCandidates(candidates, seen, prefixed)
        end
    end

    local tailScanCount = #candidates
    for index = 1, tailScanCount do
        AddLoadedSpellDataTailCandidates(candidates, seen, candidates[index])
    end

    local initialCount = #candidates
    for index = 1, initialCount do
        AddAICandidates(candidates, seen, candidates[index])
    end
    AddCombatAIOverrideCandidates(candidates, seen)

    return candidates
end

local function AddBlockedSpell(resolvedSpell, sourceSpell)
    if type(resolvedSpell) ~= "string" or resolvedSpell == "" or state.blockedSet[resolvedSpell] == true then
        return false
    end
    state.blockedSet[resolvedSpell] = true
    state.blockedSourceBySpell[resolvedSpell] = sourceSpell or resolvedSpell
    table.insert(state.blockedSpells, resolvedSpell)
    return true
end

local function TrackBlockedTail(sourceSpell)
    local prefix, tail = GetSpellPrefixAndTail(sourceSpell)
    if not prefix or tail == "" then
        return
    end
    state.blockedTailByPrefix[prefix] = state.blockedTailByPrefix[prefix] or {}
    state.blockedTailByPrefix[prefix][tail] = sourceSpell
end

local function GetBlockedSourceForRuntimeSpell(spell)
    if state.blockedSet[spell] == true then
        return state.blockedSourceBySpell[spell] or spell
    end

    local prefix, tail = GetSpellPrefixAndTail(spell)
    local tails = prefix and state.blockedTailByPrefix[prefix] or nil
    if tails then
        for blockedTail, sourceSpell in pairs(tails) do
            if TailMatches(tail, blockedTail) then
                return sourceSpell
            end
        end
    end

    for _, sourceSpell in pairs(state.blockedSourceBySpell or {}) do
        local sourcePrefix, sourceTail = GetSpellPrefixAndTail(sourceSpell)
        if sourcePrefix == prefix and TailMatches(tail, sourceTail) then
            return sourceSpell
        end
    end

    for _, sourceSpell in ipairs(GetBlockedSpellList()) do
        local sourcePrefix, sourceTail = GetSpellPrefixAndTail(sourceSpell)
        if sourcePrefix == prefix and TailMatches(tail, sourceTail) then
            return sourceSpell
        end
    end

    return nil
end

local function SyncStat(stat)
    if stat and type(stat.Sync) == "function" then
        pcall(function() stat:Sync() end)
    end
end

local function SplitAIFlags(flags)
    local out = {}
    if type(flags) ~= "string" or flags == "" then
        return out
    end
    for token in flags:gmatch("[^;]+") do
        local trimmed = token:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            table.insert(out, trimmed)
        end
    end
    return out
end

local function AIFlagsContain(flags, wanted)
    for _, flag in ipairs(SplitAIFlags(flags)) do
        if flag == wanted then
            return true
        end
    end
    return false
end

local function SetAIFlags(stat, flags)
    stat.AIFlags = table.concat(flags, ";")
    SyncStat(stat)
end

local function EnsureCanNotUseAIFlag(spell, stat)
    if not stat then
        return false, false
    end
    if state.originalAIFlagsBySpell[spell] == nil then
        local original = stat.AIFlags or ""
        state.originalAIFlagsBySpell[spell] = {
            flags = original,
            originalHadCanNotUse = AIFlagsContain(original, "CanNotUse") == true,
        }
    end
    if AIFlagsContain(stat.AIFlags, "CanNotUse") then
        return false, true
    end
    local flags = SplitAIFlags(stat.AIFlags)
    table.insert(flags, "CanNotUse")
    SetAIFlags(stat, flags)
    return true, true
end

local function RestoreCanNotUseAIFlag(spell, stat)
    local record = state.originalAIFlagsBySpell[spell]
    if record == nil then
        return false
    end
    state.originalAIFlagsBySpell[spell] = nil
    if not stat then
        return false
    end

    local originalFlags = type(record) == "table" and tostring(record.flags or "") or tostring(record or "")
    local originalHadCanNotUse = type(record) == "table"
        and record.originalHadCanNotUse == true
        or AIFlagsContain(originalFlags, "CanNotUse")
    if originalHadCanNotUse then
        return false
    end

    if (stat.AIFlags or "") == originalFlags then
        return false
    end

    SetAIFlags(stat, SplitAIFlags(originalFlags))
    return true
end

local function EnsureGateInField(stat, field, gate)
    if not gate or gate == "" then
        return false
    end
    local cond = stat[field] or ""
    if cond == gate or cond:find(gate, 1, true) then
        return false
    end
    if cond == "" then
        stat[field] = gate
    else
        stat[field] = "(" .. cond .. ") and " .. gate
    end
    SyncStat(stat)
    return true
end

local function RemoveGateFromField(stat, field, gate)
    local before = stat[field] or ""
    if before == "" or not gate or not before:find(gate, 1, true) then
        return false
    end

    local escapedGate = EscapePattern(gate)
    local after = before
        :gsub("%s+and%s+" .. escapedGate, "")
        :gsub(escapedGate .. "%s+and%s+", "")
        :gsub("^%s*" .. escapedGate .. "%s*$", "")
        :gsub("^%((.*)%)$", "%1")

    stat[field] = after
    SyncStat(stat)
    return true
end

local function PatchSpell(spell)
    local stat = GetStat(spell)
    if not stat then
        Log("Spell policy skipped missing spell stat: " .. tostring(spell))
        return false
    end
    local changed = false
    for _, field in ipairs(CLEANUP_FIELDS) do
        for _, gate in ipairs(KNOWN_POLICY_GATES) do
            if PATCH_FIELD_GATES[field] ~= gate then
                changed = RemoveGateFromField(stat, field, gate) or changed
            end
        end
    end
    for field, gate in pairs(PATCH_FIELD_GATES) do
        changed = EnsureGateInField(stat, field, gate) or changed
    end
    state.patchedSpells[spell] = true
    if changed then
        Log(string.format(
            "Spell policy patched %s with TAC-style UTAC_ALLY requirement gate; RequirementConditions=%s; TargetConditions=%s; AIFlags=%s",
            tostring(spell),
            tostring(stat.RequirementConditions or ""),
            tostring(stat.TargetConditions or ""),
            tostring(stat.AIFlags or "")
        ))
    end
    return true
end

local function RegisterObservedBlockedVariant(spell, sourceSpell)
    if type(spell) ~= "string" or spell == "" or type(sourceSpell) ~= "string" or sourceSpell == "" then
        return false
    end
    if state.blockedSet[spell] == true then
        return false
    end

    AddBlockedSpell(spell, sourceSpell)
    TrackBlockedTail(sourceSpell)
    PatchSpell(spell)

    local stat = GetStat(spell)
    if state.turnAIFlagActive == true and stat then
        EnsureCanNotUseAIFlag(spell, stat)
    end

    Log(string.format(
        "Spell policy learned runtime blocked variant %s from MCM entry %s",
        tostring(spell),
        tostring(sourceSpell)
    ))
    return true
end

local function PrintLine(message)
    if Ext and Ext.Utils and type(Ext.Utils.Print) == "function" then
        Ext.Utils.Print("[UTAC] " .. tostring(message))
    else
        print("[UTAC] " .. tostring(message))
    end
end

local function RegisterConsoleCommands()
    if state.consoleRegistered == true or not Ext or type(Ext.RegisterConsoleCommand) ~= "function" then
        return
    end

    Ext.RegisterConsoleCommand("utac_spell_policy_dump", function()
        PrintLine(string.format(
            "Spell policy enabled=%s blockedCount=%d",
            tostring(state.spellPolicyEnabled == true),
            #state.blockedSpells
        ))
        for _, spell in ipairs(state.blockedSpells) do
            local source = state.blockedSourceBySpell[spell]
            if source and source ~= spell then
                PrintLine("  - " .. tostring(spell) .. " (from " .. tostring(source) .. ")")
            else
                PrintLine("  - " .. tostring(spell))
            end
        end
    end)

    Ext.RegisterConsoleCommand("utac_spell_policy_fields", function(_, spellId)
        if not spellId or spellId == "" then
            PrintLine("Usage: utac_spell_policy_fields <SpellId>")
            return
        end

        local stat = GetStat(spellId)
        if not stat then
            PrintLine("No spell stat found for " .. tostring(spellId))
            return
        end

        PrintLine(string.format("%s.RequirementConditions = %s", tostring(spellId), tostring(stat.RequirementConditions or "")))
        PrintLine(string.format("%s.TargetConditions = %s", tostring(spellId), tostring(stat.TargetConditions or "")))
        PrintLine(string.format("%s.AIFlags = %s", tostring(spellId), tostring(stat.AIFlags or "")))
    end)

    Ext.RegisterConsoleCommand("utac_spell_policy_ai_flags", function(_, spellId)
        if not spellId or spellId == "" then
            PrintLine("Usage: utac_spell_policy_ai_flags <SpellId>")
            return
        end

        local stat = GetStat(spellId)
        if not stat then
            PrintLine("No spell stat found for " .. tostring(spellId))
            return
        end

        local record = state.originalAIFlagsBySpell[spellId]
        local originalHadCanNotUse = false
        local originalFlags = ""
        if type(record) == "table" then
            originalHadCanNotUse = record.originalHadCanNotUse == true
            originalFlags = tostring(record.flags or "")
        elseif type(record) == "string" then
            originalFlags = record
            originalHadCanNotUse = AIFlagsContain(record, "CanNotUse")
        end

        PrintLine(string.format("%s.AIFlags = %s", tostring(spellId), tostring(stat.AIFlags or "")))
        PrintLine(string.format("%s.hasCanNotUse = %s", tostring(spellId), tostring(AIFlagsContain(stat.AIFlags, "CanNotUse") == true)))
        PrintLine(string.format("%s.tracked = %s", tostring(spellId), tostring(record ~= nil)))
        PrintLine(string.format("%s.originalHadCanNotUse = %s", tostring(spellId), tostring(originalHadCanNotUse == true)))
        PrintLine(string.format("%s.originalAIFlags = %s", tostring(spellId), tostring(originalFlags)))
        PrintLine(string.format("activeOwnerKey = %s", tostring(state.turnAIFlagOwnerKey or "none")))
        PrintLine(string.format("activeOwnerLabel = %s", tostring(state.turnAIFlagOwnerLabel or "none")))
    end)

    state.consoleRegistered = true
end

local function UnpatchSpell(spell)
    local stat = GetStat(spell)
    if stat then
        local changed = false
        for _, field in ipairs(CLEANUP_FIELDS) do
            for _, gate in ipairs(KNOWN_POLICY_GATES) do
                changed = RemoveGateFromField(stat, field, gate) or changed
            end
        end
        changed = RestoreCanNotUseAIFlag(spell, stat) or changed
        if changed then
            Log("Spell policy unpatched " .. tostring(spell))
        end
    else
        state.originalAIFlagsBySpell[spell] = nil
    end
    state.patchedSpells[spell] = nil
end

local function RebuildBlockedSpellSet()
    state.blockedSpells = {}
    state.blockedSet = {}
    state.blockedSourceBySpell = {}
    state.blockedTailByPrefix = {}
    state.unresolvedBlockedSpells = {}

    local canResolve = CanResolveStats()
    local entryCount = 0
    local unresolvedCount = 0
    for _, spell in ipairs(GetBlockedSpellList()) do
        if type(spell) == "string" and spell ~= "" then
            entryCount = entryCount + 1
            TrackBlockedTail(spell)
            local matched = 0
            for _, candidate in ipairs(GetSpellPolicyCandidates(spell)) do
                if not canResolve or GetStat(candidate) then
                    matched = matched + 1
                    AddBlockedSpell(candidate, spell)
                end
            end

            if matched == 0 then
                state.unresolvedBlockedSpells[spell] = true
                AddBlockedSpell(spell, spell)
                unresolvedCount = unresolvedCount + 1
            end
        end
    end

    return {
        entries = entryCount,
        resolved = #state.blockedSpells,
        unresolved = unresolvedCount,
    }
end

local function MarkBlockedAttempt(caster, spellId)
    local key = Normalize(caster)
    if not key then return end
    state.blockedAttempts[key] = spellId or true

    if Ext and Ext.Timer and type(Ext.Timer.WaitFor) == "function" then
        Ext.Timer.WaitFor(1500, function()
            if state.blockedAttempts[key] == spellId or state.blockedAttempts[key] == true then
                state.blockedAttempts[key] = nil
            end
        end)
    end
end

local function WasRecentlyBlocked(source)
    local key = Normalize(source)
    return key ~= nil and state.blockedAttempts[key] ~= nil
end

local function ClearBlockedAttempt(source)
    local key = Normalize(source)
    if key then
        state.blockedAttempts[key] = nil
    end
end

local function PatchCurrentSpellList()
    if state.spellPolicyEnabled ~= true then
        for spell, _ in pairs(state.patchedSpells) do
            UnpatchSpell(spell)
        end
        return
    end

    for spell, _ in pairs(state.patchedSpells) do
        if state.blockedSet[spell] ~= true then
            UnpatchSpell(spell)
        end
    end
    for spell, _ in pairs(state.blockedSet) do
        -- Stats can be reloaded after we already marked a spell as patched.
        -- Re-run idempotently so persisted MCM lists stay blocked after reload.
        PatchSpell(spell)
    end
end

local function HasSpell(character, spell)
    if not character or character == "" or not spell or not Osi or type(Osi.HasSpell) ~= "function" then
        return false
    end
    local ok, hasSpell = pcall(Osi.HasSpell, character, spell)
    return ok and hasSpell == 1
end

local function RemoveSpell(character, spell)
    if not character or character == "" or not spell or not Osi or type(Osi.RemoveSpell) ~= "function" then
        return false
    end
    if HasSpell(character, spell) ~= true then
        return false
    end

    local attempts = {
        function() return pcall(Osi.RemoveSpell, character, spell, 1) end,
        function() return pcall(Osi.RemoveSpell, character, spell, 0) end,
        function() return pcall(Osi.RemoveSpell, character, spell) end,
    }

    for _, attempt in ipairs(attempts) do
        attempt()
        if HasSpell(character, spell) ~= true then
            return true
        end
    end

    Log(string.format("Spell policy failed to remove %s from %s; HasSpell stayed true", tostring(spell), tostring(character)))
    return false
end

local function AddSpell(character, spell)
    if not character or character == "" or not spell or not Osi or type(Osi.AddSpell) ~= "function" then
        return false
    end
    local ok = pcall(Osi.AddSpell, character, spell, 0, 1)
    return ok == true
end

local function CollectTableKeys(t)
    local keys = {}
    for key, _ in pairs(t or {}) do
        table.insert(keys, key)
    end
    return keys
end

local function RestoreSpellForKey(key, spell, preferredCharacter)
    if not key or not spell then
        return false
    end
    local record = state.strippedByKey[key]
    if type(record) ~= "table" or record[spell] ~= true then
        return false
    end

    local target = GetLiveTarget(preferredCharacter or key)
    if target and target ~= "" and GetStat(spell) then
        AddSpell(target, spell)
    end
    record[spell] = nil
    if next(record) == nil then
        state.strippedByKey[key] = nil
    end
    return true
end

local function RestoreUnblockedSpells()
    for key, record in pairs(state.strippedByKey) do
        for _, spell in ipairs(CollectTableKeys(record)) do
            if state.blockedSet[spell] ~= true then
                RestoreSpellForKey(key, spell, key)
            end
        end
    end
end

local function RestoreTurnScopedCanNotUse(reason)
    local restored = 0
    local tracked = 0
    for _, spell in ipairs(CollectTableKeys(state.originalAIFlagsBySpell)) do
        tracked = tracked + 1
        if RestoreCanNotUseAIFlag(spell, GetStat(spell)) then
            restored = restored + 1
        end
    end

    if state.turnAIFlagActive == true or tracked > 0 then
        Log(string.format(
            "Spell policy restored temporary CanNotUse flags: restored=%d tracked=%d owner=%s reason=%s",
            restored,
            tracked,
            tostring(state.turnAIFlagOwnerLabel or state.turnAIFlagOwnerKey or "none"),
            tostring(reason or "restore")
        ))
    end

    state.turnAIFlagOwnerKey = nil
    state.turnAIFlagOwnerCharacter = nil
    state.turnAIFlagOwnerLabel = nil
    state.turnAIFlagActive = false
    return restored
end

local function CollectTurnScopedCanNotUseSpells()
    local out = {}
    local seen = {}

    if state.spellPolicyEnabled == true then
        for _, spell in ipairs(state.blockedSpells) do
            AddUnique(out, seen, spell)
        end
    end

    if GetBool("MCM_DisableUTACThrow", false) == true then
        for _, spell in ipairs(TURN_SCOPED_THROW_BLOCK_SPELLS) do
            AddUnique(out, seen, spell)
        end
    end

    return out
end

local function ApplyTurnScopedCanNotUse(character, reason, forceCombat)
    if not IsModEnabled() or not IsUTACControlled(character) then
        return false
    end
    if forceCombat ~= true and not IsInCombat(character) then
        return false
    end

    local turnSpells = CollectTurnScopedCanNotUseSpells()
    if #turnSpells == 0 then
        return false
    end

    local key = Normalize(character)
    if not key then
        return false
    end

    if state.turnAIFlagOwnerKey and state.turnAIFlagOwnerKey ~= key then
        RestoreTurnScopedCanNotUse("owner changed to " .. tostring(key) .. "; " .. tostring(reason or "turn sync"))
    end

    state.turnAIFlagOwnerKey = key
    state.turnAIFlagOwnerCharacter = character
    state.turnAIFlagOwnerLabel = tostring(character)
    state.turnAIFlagActive = true

    local applied = 0
    local tracked = 0
    local missing = 0
    for _, spell in ipairs(turnSpells) do
        local stat = GetStat(spell)
        if stat then
            local changed, isTracked = EnsureCanNotUseAIFlag(spell, stat)
            if isTracked then
                tracked = tracked + 1
            end
            if changed then
                applied = applied + 1
            end
        else
            missing = missing + 1
        end
    end

    Log(string.format(
        "Spell policy temporarily set CanNotUse on %d blocked spell(s) for %s; tracked=%d missing=%d reason=%s",
        applied,
        tostring(state.turnAIFlagOwnerLabel),
        tracked,
        missing,
        tostring(reason or "turn sync")
    ))
    return true
end

local function RestoreTurnScopedCanNotUseIfOwner(character, reason)
    local key = Normalize(character)
    if key and state.turnAIFlagOwnerKey and key == state.turnAIFlagOwnerKey then
        RestoreTurnScopedCanNotUse(reason or "owner restore")
        return true
    end

    if DebugLoggingEnabled() and state.turnAIFlagOwnerKey then
        Log(string.format(
            "Spell policy ignored stale TurnEnded for %s; active owner=%s reason=%s",
            tostring(character),
            tostring(state.turnAIFlagOwnerLabel or state.turnAIFlagOwnerKey),
            tostring(reason or "owner mismatch")
        ))
    end
    return false
end

local function RestoreTurnScopedCanNotUseForDifferentOwner(character, reason)
    local key = Normalize(character)
    if key and state.turnAIFlagOwnerKey and key ~= state.turnAIFlagOwnerKey then
        RestoreTurnScopedCanNotUse(string.format(
            "%s; new turn owner=%s",
            tostring(reason or "turn owner changed"),
            tostring(character)
        ))
        return true
    end
    return false
end

local function ApplySpellPolicyForCharacter(character, reason, combatState)
    local key = Normalize(character)
    if not key then
        return
    end

    if state.spellPolicyEnabled ~= true
        or not IsModEnabled()
        or not IsUTACControlled(character)
        or (not combatState and not IsInCombat(character)) then
        SpellPolicy.RestoreStrippedSpells(character, reason or "spell policy inactive")
        for _, target in ipairs(GetStatusTargets(character)) do
            RemoveStatus(target, SPELL_POLICY_STATUS)
        end
        return
    end

    local removed = 0
    local liveTarget = GetLiveTarget(character)

    for _, spell in ipairs(state.blockedSpells) do
        if HasSpell(liveTarget, spell) then
            if RemoveSpell(liveTarget, spell) then
                state.strippedByKey[key] = state.strippedByKey[key] or {}
                state.strippedByKey[key][spell] = true
                removed = removed + 1
            end
        end
    end

    if removed > 0 then
        Log(string.format("Spell policy removed %d blocked spell(s) from %s (%s)", removed, tostring(liveTarget), tostring(reason or "sync")))
    end
end

local function ClearSlotLimitStatuses(character, reason)
    local key = Normalize(character)
    local changed = false
    for _, target in ipairs(GetStatusTargets(character)) do
        for _, status in pairs(SLOT_LIMIT_STATUSES) do
            changed = RemoveStatus(target, status) or changed
        end
    end
    if key and state.slotStatusByKey[key] then
        changed = true
        state.slotStatusByKey[key] = nil
    end
    if changed and reason then
        Log(string.format("Spell slot limiter cleanup for %s (%s)", tostring(character), tostring(reason)))
    end
    return changed
end

local function HasNormalSpellSlot(character, casterResource)
    if casterResource and casterResource.name == "SpellSlot" then
        return true
    end
    if not character or character == "" or not Osi or type(Osi.GetActionResourceValuePersonal) ~= "function" then
        return false
    end
    for level = 1, 6 do
        local ok, amount = pcall(Osi.GetActionResourceValuePersonal, character, "SpellSlot", level)
        if ok and tonumber(amount) and tonumber(amount) > 0 then
            return true
        end
    end
    return false
end

local function GetHP(character)
    if Osi and type(Osi.GetHitpointsPercentage) == "function" then
        local ok, hp = pcall(Osi.GetHitpointsPercentage, character)
        if ok and tonumber(hp) then
            return tonumber(hp)
        end
    end
    return 100
end

local function GetHPForLimiter(character, combatState)
    if combatState and tonumber(combatState.selfHP) then
        return tonumber(combatState.selfHP)
    end
    return GetHP(character)
end

local function ShouldClearLimiter(character, archetype, combatState, casterResource)
    if state.slotLimiterEnabled ~= true then return true, "disabled" end
    if not IsModEnabled() then return true, "mod disabled" end
    if not IsUTACControlled(character) then return true, "not UTAC-controlled" end
    if not combatState and not IsInCombat(character) then return true, "not in combat" end
    if not CASTER_ARCHETYPES[archetype] then return true, "non-caster archetype" end
    if not HasNormalSpellSlot(character, casterResource) then return true, "no normal SpellSlot" end
    if state.slotAllowEnemies <= 0 then return true, "pressure override disabled" end

    local nearbyEnemies = tonumber(combatState and combatState.enemiesNearby) or 0
    if nearbyEnemies >= state.slotAllowEnemies then
        return true, "enemy pressure"
    end

    local hp = GetHPForLimiter(character, combatState)
    if hp <= 50 then
        return true, "low HP"
    end

    if archetype == "Support_Healer" then
        local triage = tonumber(combatState and combatState.triageThreshold) or 60
        local selfHP = tonumber(combatState and combatState.selfHP) or hp
        if (tonumber(combatState and combatState.downedAlliesNearby) or 0) > 0 then
            return true, "downed ally"
        end
        if (tonumber(combatState and combatState.urgentHealCandidates) or 0) > 0 then
            return true, "urgent heal candidate"
        end
        if (tonumber(combatState and combatState.alliesLowHP) or 0) > 0 then
            return true, "low HP ally"
        end
        if combatState and combatState.selfLowHP == true then
            return true, "healer self low"
        end
        if selfHP <= triage then
            return true, "healer self triage"
        end
    end

    return false, nil
end

local function LogSlotLimiterDiagnostic(character, archetype, combatState, casterResource, shouldClear, clearReason, status, reason)
    if state.slotLimiterEnabled ~= true then
        return
    end
    if not CASTER_ARCHETYPES[archetype] and not status then
        return
    end

    local nearbyEnemies = tonumber(combatState and combatState.enemiesNearby) or 0
    local hp = GetHPForLimiter(character, combatState)
    local hasSpellSlot = HasNormalSpellSlot(character, casterResource)
    local result = shouldClear and "clear" or "apply"
    local detail = clearReason or status or "none"
    local resourceLabel = casterResource and casterResource.name or "none"
    if casterResource and casterResource.level then
        resourceLabel = string.format("%s:L%d", tostring(casterResource.name), tonumber(casterResource.level) or 0)
    end

    Log(string.format(
        "Spell slot limiter sync: target=%s archetype=%s result=%s detail=%s minLevel=%s allowEnemiesNearby=%s nearbyEnemies=%d hp=%d hasNormalSpellSlot=%s resource=%s reason=%s",
        tostring(character),
        tostring(archetype or "none"),
        tostring(result),
        tostring(detail),
        tostring(state.slotMinLevel),
        tostring(state.slotAllowEnemies),
        nearbyEnemies,
        math.floor(hp),
        tostring(hasSpellSlot == true),
        tostring(resourceLabel),
        tostring(reason or "sync")
    ))
end

local function SyncSlotLimiter(character, archetype, combatState, casterResource, reason)
    if not archetype then
        if state.slotLimiterEnabled ~= true then
            ClearSlotLimitStatuses(character)
        end
        return
    end

    local key = Normalize(character)
    local shouldClear, clearReason = ShouldClearLimiter(character, archetype, combatState, casterResource)
    if shouldClear then
        LogSlotLimiterDiagnostic(character, archetype, combatState, casterResource, true, clearReason, nil, reason)
        if ClearSlotLimitStatuses(character) then
            Log(string.format("Spell slot limiter cleared for %s (%s; %s)", tostring(character), tostring(clearReason), tostring(reason or "sync")))
        end
        return
    end

    local minLevel = math.floor(tonumber(state.slotMinLevel) or 3)
    if minLevel < 2 then minLevel = 2 end
    if minLevel > 6 then minLevel = 6 end
    local status = SLOT_LIMIT_STATUSES[minLevel]
    if not status then
        ClearSlotLimitStatuses(character)
        return
    end

    LogSlotLimiterDiagnostic(character, archetype, combatState, casterResource, false, nil, status, reason)
    if key and state.slotStatusByKey[key] == status and HasStatus(character, status) then
        return
    end
    ClearSlotLimitStatuses(character)
    ApplyStatus(character, status)
    if key and state.slotStatusByKey[key] ~= status then
        state.slotStatusByKey[key] = status
        Log(string.format("Spell slot limiter applied %s to %s (%s)", tostring(status), tostring(character), tostring(reason or "sync")))
    end
end

local function ClearSpellPolicyState(reason)
    RestoreTurnScopedCanNotUse(reason or "spell policy clear")
    for _, key in ipairs(CollectTableKeys(state.strippedByKey)) do
        SpellPolicy.RestoreStrippedSpells(key, reason)
    end
    if type(deps.CollectKnownUTACCharacters) == "function" then
        local ok, characters = pcall(deps.CollectKnownUTACCharacters, true)
        if ok and type(characters) == "table" then
            for _, character in ipairs(characters) do
                for _, target in ipairs(GetStatusTargets(character)) do
                    RemoveStatus(target, SPELL_POLICY_STATUS)
                end
            end
        end
    end
end

local function ClearSlotLimiterState(reason)
    for _, key in ipairs(CollectTableKeys(state.slotStatusByKey)) do
        ClearSlotLimitStatuses(key, reason)
    end
    if type(deps.CollectKnownUTACCharacters) == "function" then
        local ok, characters = pcall(deps.CollectKnownUTACCharacters, true)
        if ok and type(characters) == "table" then
            for _, character in ipairs(characters) do
                ClearSlotLimitStatuses(character, reason)
            end
        end
    end
end

function SpellPolicy.Initialize(newDeps)
    deps = newDeps or {}
    state.initialized = true
    RegisterConsoleCommands()
end

function SpellPolicy.RefreshSettings(reason)
    local previousTurnOwner = state.turnAIFlagOwnerCharacter or state.turnAIFlagOwnerKey
    local hadTurnOwner = state.turnAIFlagActive == true
    RestoreTurnScopedCanNotUse("settings refresh: " .. tostring(reason or "settings"))

    state.spellPolicyEnabled = GetBool("MCM_EnableUTACSpellPolicy", false)
    state.slotLimiterEnabled = GetBool("MCM_EnableSpellSlotLimiter", false)
    state.slotMinLevel = GetNumber("MCM_SpellSlotLimiter_MinLevel", 3)
    state.slotAllowEnemies = GetNumber("MCM_SpellSlotLimiter_AllowEnemiesAtLeast", 3)

    local summary = RebuildBlockedSpellSet()
    PatchCurrentSpellList()
    RestoreUnblockedSpells()

    if state.spellPolicyEnabled == true or (summary and summary.unresolved or 0) > 0 then
        Log(string.format(
            "Spell policy refreshed: entries=%d resolved=%d unresolved=%d reason=%s",
            summary and summary.entries or 0,
            summary and summary.resolved or 0,
            summary and summary.unresolved or 0,
            tostring(reason or "settings")
        ))
    end

    if state.spellPolicyEnabled ~= true then
        ClearSpellPolicyState("spell policy disabled: " .. tostring(reason or "settings"))
    elseif hadTurnOwner and previousTurnOwner then
        ApplyTurnScopedCanNotUse(previousTurnOwner, "settings refresh reapply: " .. tostring(reason or "settings"), true)
    end
    if state.slotLimiterEnabled ~= true then
        ClearSlotLimiterState("slot limiter disabled: " .. tostring(reason or "settings"))
    end
end

function SpellPolicy.SyncForCharacter(character, archetype, combatState, casterResource, reason)
    if not state.initialized then return end
    ApplySpellPolicyForCharacter(character, reason, combatState)
    SyncSlotLimiter(character, archetype, combatState, casterResource, reason)
end

function SpellPolicy.ApplyTurnScopedCanNotUse(character, reason)
    if not state.initialized then return false end
    return ApplyTurnScopedCanNotUse(character, reason, true)
end

function SpellPolicy.RestoreTurnScopedCanNotUse(reason)
    return RestoreTurnScopedCanNotUse(reason)
end

function SpellPolicy.RestoreTurnScopedCanNotUseIfOwner(character, reason)
    return RestoreTurnScopedCanNotUseIfOwner(character, reason)
end

function SpellPolicy.RestoreTurnScopedCanNotUseForDifferentOwner(character, reason)
    return RestoreTurnScopedCanNotUseForDifferentOwner(character, reason)
end

function SpellPolicy.RestoreStrippedSpells(character, reason)
    local key = Normalize(character)
    if not key then return end
    local record = state.strippedByKey[key]
    if type(record) ~= "table" then return end

    local restored = 0
    for _, spell in ipairs(CollectTableKeys(record)) do
        if RestoreSpellForKey(key, spell, character) then
            restored = restored + 1
        end
    end
    if restored > 0 then
        Log(string.format("Spell policy restored %d spell(s) to %s (%s)", restored, tostring(character), tostring(reason or "restore")))
    end
end

function SpellPolicy.ClearForCharacter(character, reason)
    if not character or character == "" then return end
    local key = Normalize(character)
    if key then
        state.blockedAttempts[key] = nil
    end
    RestoreTurnScopedCanNotUseIfOwner(character, reason or "clear character")
    SpellPolicy.RestoreStrippedSpells(character, reason)
    for _, target in ipairs(GetStatusTargets(character)) do
        RemoveStatus(target, SPELL_POLICY_STATUS)
    end
    ClearSlotLimitStatuses(character, reason)
end

function SpellPolicy.HasStateForCharacter(character)
    local key = Normalize(character)
    if not key then return false end
    return state.strippedByKey[key] ~= nil
        or state.slotStatusByKey[key] ~= nil
        or state.turnAIFlagOwnerKey == key
end

function SpellPolicy.ClearAll(reason)
    state.blockedAttempts = {}
    RestoreTurnScopedCanNotUse(reason or "clear all")
    for _, spell in ipairs(CollectTableKeys(state.patchedSpells)) do
        UnpatchSpell(spell)
    end
    for _, key in ipairs(CollectTableKeys(state.strippedByKey)) do
        SpellPolicy.RestoreStrippedSpells(key, reason)
    end
    for _, key in ipairs(CollectTableKeys(state.slotStatusByKey)) do
        SpellPolicy.ClearForCharacter(key, reason)
    end
    if type(deps.CollectKnownUTACCharacters) == "function" then
        local ok, characters = pcall(deps.CollectKnownUTACCharacters, true)
        if ok and type(characters) == "table" then
            for _, character in ipairs(characters) do
                SpellPolicy.ClearForCharacter(character, reason)
            end
        end
    end
end

function SpellPolicy.ClearNonCombat(reason)
    if state.turnAIFlagOwnerKey and not IsInCombat(state.turnAIFlagOwnerCharacter or state.turnAIFlagOwnerKey) then
        RestoreTurnScopedCanNotUse(reason or "noncombat cleanup")
    end
    for _, key in ipairs(CollectTableKeys(state.strippedByKey)) do
        if not IsInCombat(key) then
            SpellPolicy.ClearForCharacter(key, reason)
        end
    end
    for _, key in ipairs(CollectTableKeys(state.slotStatusByKey)) do
        if not IsInCombat(key) then
            SpellPolicy.ClearForCharacter(key, reason)
        end
    end
end

function SpellPolicy.ResyncTracked(reason)
    SpellPolicy.RefreshSettings(reason)
    if type(deps.CollectKnownUTACCharacters) ~= "function" then return end
    local ok, characters = pcall(deps.CollectKnownUTACCharacters, true)
    if not ok or type(characters) ~= "table" then return end
    for _, character in ipairs(characters) do
        SpellPolicy.SyncForCharacter(character, nil, nil, nil, reason)
    end
end

function SpellPolicy.ObserveSpell(caster, spellId, eventName, detail)
    if DebugLoggingEnabled() ~= true or not spellId or spellId == "" then
        return false
    end
    if not IsModEnabled() or not IsUTACControlled(caster) then
        return false
    end

    local stat = GetStat(spellId)
    local liveTarget = GetLiveTarget(caster)
    local matchedSource = GetBlockedSourceForRuntimeSpell(spellId)
    if matchedSource and state.blockedSet[spellId] ~= true then
        RegisterObservedBlockedVariant(spellId, matchedSource)
    end
    local sourceEntry = matchedSource or spellId
    Log(string.format(
        "Spell policy observe: event=%s spell=%s sourceEntry=%s caster=%s liveTarget=%s controlled=%s inCombat=%s blockedExact=%s hasUTACAlly=%s hasPolicyStatus=%s hasSpell=%s RequirementConditions=%s TargetConditions=%s AIFlags=%s%s",
        tostring(eventName or "unknown"),
        tostring(spellId),
        tostring(sourceEntry),
        tostring(caster),
        tostring(liveTarget),
        tostring(IsUTACControlled(caster) == true),
        tostring(IsInCombat(caster) == true),
        tostring(matchedSource ~= nil),
        tostring(HasStatus(liveTarget, "UTAC_ALLY") == true),
        tostring(HasStatus(liveTarget, SPELL_POLICY_STATUS) == true),
        tostring(HasSpell(liveTarget, spellId) == true),
        tostring(stat and stat.RequirementConditions or ""),
        tostring(stat and stat.TargetConditions or ""),
        tostring(stat and stat.AIFlags or ""),
        detail and (" detail=" .. tostring(detail)) or ""
    ))
    return true
end

function SpellPolicy.OnUsingSpell(caster, spellId)
    local sourceSpell = spellId and GetBlockedSourceForRuntimeSpell(spellId) or nil
    if state.spellPolicyEnabled ~= true or not spellId or not sourceSpell then
        return false
    end
    if not IsModEnabled() or not IsUTACControlled(caster) then
        return false
    end

    if state.blockedSet[spellId] ~= true then
        RegisterObservedBlockedVariant(spellId, sourceSpell)
    end

    local liveTarget = GetLiveTarget(caster)
    MarkBlockedAttempt(caster, spellId)
    if HasSpell(liveTarget, spellId) then
        RemoveSpell(liveTarget, spellId)
        local key = Normalize(caster)
        if key then
            state.strippedByKey[key] = state.strippedByKey[key] or {}
            state.strippedByKey[key][spellId] = true
        end
    end
    if Osi and type(Osi.PurgeOsirisQueue) == "function" then
        pcall(Osi.PurgeOsirisQueue, caster, 1)
    end
    if sourceSpell and sourceSpell ~= spellId then
        Log(string.format("Spell policy late guard blocked spell %s from %s (matched MCM entry %s)", tostring(spellId), tostring(caster), tostring(sourceSpell)))
    else
        Log(string.format("Spell policy late guard blocked spell %s from %s", tostring(spellId), tostring(caster)))
    end
    return true
end

function SpellPolicy.OnUsingSpellAfter(caster, spellId)
    local sourceSpell = spellId and GetBlockedSourceForRuntimeSpell(spellId) or nil
    if state.spellPolicyEnabled ~= true or not spellId or not sourceSpell then
        return false
    end
    if not IsModEnabled() or not IsUTACControlled(caster) then
        return false
    end

    local stat = GetStat(spellId)
    local liveTarget = GetLiveTarget(caster)
    Log(string.format(
        "Spell policy observed blocked spell attempt after guard: spell=%s sourceEntry=%s caster=%s liveTarget=%s hasUTACAlly=%s RequirementConditions=%s TargetConditions=%s AIFlags=%s",
        tostring(spellId),
        tostring(sourceSpell),
        tostring(caster),
        tostring(liveTarget),
        tostring(HasStatus(liveTarget, "UTAC_ALLY") == true),
        tostring(stat and stat.RequirementConditions or ""),
        tostring(stat and stat.TargetConditions or ""),
        tostring(stat and stat.AIFlags or "")
    ))
    return true
end

function SpellPolicy.OnStatusApplied(target, status, source)
    if state.spellPolicyEnabled ~= true or not WasRecentlyBlocked(source) then
        return false
    end
    if not IsModEnabled() or not IsUTACControlled(source) then
        ClearBlockedAttempt(source)
        return false
    end
    if type(status) == "string" and status:find("^UTAC_") then
        return false
    end

    if Osi and type(Osi.RemoveStatus) == "function" then
        local ok = pcall(Osi.RemoveStatus, target, status, source)
        if not ok then
            pcall(Osi.RemoveStatus, target, status)
        end
    end
    if Osi and type(Osi.PurgeOsirisQueue) == "function" then
        pcall(Osi.PurgeOsirisQueue, source, 1)
    end
    ClearBlockedAttempt(source)
    Log(string.format(
        "Spell policy post-leak cleanup removed status %s from %s after blocked spell source=%s",
        tostring(status),
        tostring(target),
        tostring(source)
    ))
    return true
end

return SpellPolicy
