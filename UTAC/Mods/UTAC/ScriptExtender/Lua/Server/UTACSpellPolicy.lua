-- UTACSpellPolicy.lua
-- UTAC-scoped optional spell blocking and normal spell-slot limiter.

local SpellPolicy = {}

local SPELL_POLICY_STATUS = "UTAC_SPELL_POLICY_BLOCKED"
local SPELL_POLICY_REQUIREMENT_GATE = "not HasStatus('UTAC_SPELL_POLICY_BLOCKED')"
local SPELL_POLICY_TARGET_GATE = "not HasStatus('UTAC_SPELL_POLICY_BLOCKED', context.Source)"
local PATCH_FIELD_GATES = {
    RequirementConditions = SPELL_POLICY_REQUIREMENT_GATE,
}
local CLEANUP_FIELDS = { "RequirementConditions", "TargetConditions" }
local KNOWN_POLICY_GATES = {
    SPELL_POLICY_REQUIREMENT_GATE,
    SPELL_POLICY_TARGET_GATE,
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
    patchedSpells = {},
    strippedByKey = {},
    slotStatusByKey = {},
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
        return
    end
    if type(deps.ApplyStatusIfMissing) == "function" then
        pcall(deps.ApplyStatusIfMissing, character, status, -1)
    elseif Osi and type(Osi.ApplyStatus) == "function" and not HasStatus(character, status) then
        pcall(Osi.ApplyStatus, character, status, -1, 1)
    end
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

local function GetNumber(settingId, fallback)
    if type(deps.GetMCM_Number) == "function" then
        local value = deps.GetMCM_Number(settingId, fallback)
        return tonumber(value) or fallback
    end
    return fallback
end

local function GetBlockedSpellList()
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
            return list
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

local function SyncStat(stat)
    if stat and type(stat.Sync) == "function" then
        pcall(function() stat:Sync() end)
    end
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
            "Spell policy patched %s with UTAC caster gate; RequirementConditions=%s; TargetConditions=%s",
            tostring(spell),
            tostring(stat.RequirementConditions or ""),
            tostring(stat.TargetConditions or "")
        ))
    end
    return true
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
        if changed then
            Log("Spell policy unpatched " .. tostring(spell))
        end
    end
    state.patchedSpells[spell] = nil
end

local function RebuildBlockedSpellSet()
    state.blockedSpells = {}
    state.blockedSet = {}
    for _, spell in ipairs(GetBlockedSpellList()) do
        if type(spell) == "string" and spell ~= "" and state.blockedSet[spell] ~= true then
            state.blockedSet[spell] = true
            table.insert(state.blockedSpells, spell)
        end
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
        if state.patchedSpells[spell] ~= true then
            PatchSpell(spell)
        end
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
    local ok = pcall(Osi.RemoveSpell, character, spell, 1)
    return ok == true
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
    for _, target in ipairs(GetStatusTargets(character)) do
        ApplyStatus(target, SPELL_POLICY_STATUS)
    end

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
    SpellPolicy.RefreshSettings("initialize")
end

function SpellPolicy.RefreshSettings(reason)
    state.spellPolicyEnabled = GetBool("MCM_EnableUTACSpellPolicy", false)
    state.slotLimiterEnabled = GetBool("MCM_EnableSpellSlotLimiter", false)
    state.slotMinLevel = GetNumber("MCM_SpellSlotLimiter_MinLevel", 3)
    state.slotAllowEnemies = GetNumber("MCM_SpellSlotLimiter_AllowEnemiesAtLeast", 3)

    RebuildBlockedSpellSet()
    PatchCurrentSpellList()
    RestoreUnblockedSpells()

    if state.spellPolicyEnabled ~= true then
        ClearSpellPolicyState("spell policy disabled: " .. tostring(reason or "settings"))
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
    SpellPolicy.RestoreStrippedSpells(character, reason)
    for _, target in ipairs(GetStatusTargets(character)) do
        RemoveStatus(target, SPELL_POLICY_STATUS)
    end
    ClearSlotLimitStatuses(character, reason)
end

function SpellPolicy.ClearAll(reason)
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

function SpellPolicy.OnUsingSpell(caster, spellId)
    if state.spellPolicyEnabled ~= true or not spellId or state.blockedSet[spellId] ~= true then
        return false
    end
    if not IsModEnabled() or not IsUTACControlled(caster) then
        return false
    end

    local liveTarget = GetLiveTarget(caster)
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
    Log(string.format("Spell policy late guard blocked spell %s from %s", tostring(spellId), tostring(caster)))
    return true
end

return SpellPolicy
