-- ||                      ULTIMATE TACTICAL AI COMPANIONS (UTAC)                 ||
-- =================================================================================
-- Requires: Norbyte BG3 Script Extender (see ScriptExtender/Config.json RequiredVersion; min 9).
-- Mod version: 1.0.9 (see meta.lsx Version64).
-- =================================================================================

local ModuleUUID = "300fb883-8af8-4be9-a101-171b56698dc5"
local BUILD_TAG = "2026-05-04-movement-safety-spell-policy"
local NULL_UUID = "NULL_00000000-0000-0000-0000-000000000000"
local UTACSettings = Ext.Require("Server/UTACSettings.lua")

_G.UTAC_Companions = _G.UTAC_Companions or {}
_G.UTAC_TransformedForDialog = {}
_G.UTAC_BaseStatusByCharacter = _G.UTAC_BaseStatusByCharacter or {}

local Config = Ext.Require("Server/Config.lua")
local UTACSpellPolicy = Ext.Require("Server/UTACSpellPolicy.lua")

-- =================================================================================
-- ||                        HELPERS & MCM                                        ||
-- =================================================================================

local function IsModEnabled()
    return UTACSettings.GetBool("MCM_EnableMod", true)
end

local function InfoPrint(...)
    if UTACSettings.GetBool("MCM_DebugLogging", false) then
        if Ext and Ext.Utils and Ext.Utils.Print then
            Ext.Utils.Print("[UTAC]", ...)
        else
            print("[UTAC]", ...)
        end
    end
end

_G.UTAC_InfoPrint = InfoPrint

local function GetHealerTriageThreshold()
    return UTACSettings.GetNumber("Healer_TriageThreshold", 60)
end

local function GetMCM_Bool(id, default)
    return UTACSettings.GetBool(id, default)
end

local function GetMCM_Number(id, default)
    return UTACSettings.GetNumber(id, default)
end

-- === UTAC: AI-only spell variants ===
local function UTAC_ModifySpells(character, enable)
    if not character or character == "" then return end
    if type(Osi.HasSpell) ~= "function" or type(Osi.AddSpell) ~= "function" or type(Osi.RemoveSpell) ~= "function" then
        return
    end
    if enable then
        for baseId, aiId in pairs(Config.UTAC_SpellMappings) do
            if Osi.HasSpell(character, baseId) == 1 and Osi.HasSpell(character, aiId) == 0 then
                Osi.AddSpell(character, aiId, 0, 1)
            end
        end
    else
        for _, aiId in pairs(Config.UTAC_SpellMappings) do
            if Osi.HasSpell(character, aiId) == 1 then
                Osi.RemoveSpell(character, aiId)
            end
        end
    end
end

-- === Post-heal window ===
local RuntimeJustHealed = {}

local function PostHealActive(uuid)
    return RuntimeJustHealed[tostring(uuid)] == true
end

local function GetUTACModVars()
    if not (Ext and Ext.Vars and type(Ext.Vars.GetModVariables) == "function") then
        return nil
    end

    local ok, vars = pcall(function()
        return Ext.Vars.GetModVariables(ModuleUUID)
    end)
    if ok and vars then
        return vars
    end
    return nil
end

local function SetModVar(name, value)
    local vars = GetUTACModVars()
    if vars then
        vars[name] = value
        return true
    end
    return false
end

-- === Spell resource tracking ===
local LevelAwareSpellResources = {}
local FlatSpellResources = {}

local function BuildTrackedSpellResources()
    LevelAwareSpellResources = {
        SpellSlot = {1, 2, 3, 4, 5, 6, 7, 8, 9},
        WarlockSpellSlot = {1, 2, 3, 4, 5}
    }
    FlatSpellResources = {
        PsiPointsResource = true, PsiLimitResource = true, PsionicMasteryResource = true, PsionicMasteryCooldown = true,
        MindSurge = true, AnomalySuppressionCharge = true, SpectralVanishCharge = true, DimensionalAmbushCharge = true,
        AetherCharge = true,
        Interrupt_PsionicStrike = true, Interrupt_PsionicSurge = true, Interrupt_SurgeOfHealth = true,
        Interrupt_MemoryOfOneThousandSteps = true, Interrupt_MindstrikeRiposteCharge = true,
        Interrupt_KineticDeflectionCharge = true, Interrupt_ForceboundRetributionCharge = true,
        FrostIncarnateCharge = true, ForceEruptionCharge = true, SoulEssence = true
    }
    local customList = UTACSettings.Get("MCM_CustomSpellResources")
    if type(customList) == "string" then
        for entry in customList:gmatch("[^,;]+") do
            local trimmed = entry:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed ~= "" then FlatSpellResources[trimmed] = true end
        end
    end
    local tracked = {}
    for name in pairs(LevelAwareSpellResources) do table.insert(tracked, name) end
    for name in pairs(FlatSpellResources) do
        if not LevelAwareSpellResources[name] then table.insert(tracked, name) end
    end
    table.sort(tracked)
    InfoPrint("Tracking spell resources: " .. table.concat(tracked, ", "))
end

local function RefreshTrackedSpellResources()
    BuildTrackedSpellResources()
end

local function GetAvailableCasterResource(character)
    if not character or character == "" then return nil end
    for resource, levels in pairs(LevelAwareSpellResources) do
        for _, level in ipairs(levels) do
            local amount = Osi.GetActionResourceValuePersonal(character, resource, level) or 0
            if amount > 0 then
                return {
                    name = resource, level = level, type = "level",
                    isSpellSlot = resource == "SpellSlot" or resource == "WarlockSpellSlot"
                }
            end
        end
    end
    for resource, _ in pairs(FlatSpellResources) do
        local amount = Osi.GetActionResourceValuePersonal(character, resource, 0) or 0
        if amount > 0 then
            return {
                name = resource, type = "flat",
                isSpellSlot = resource == "SpellSlot" or resource == "WarlockSpellSlot"
            }
        end
    end
    return nil
end

local function EncourageSpellcasting(character, resourceInfo)
    if not character or character == "" then return end
    Osi.ApplyStatus(character, "UTAC_ENCOURAGE_SPELLS", 100, 1)
    if resourceInfo and not resourceInfo.isSpellSlot then
        Osi.ApplyStatus(character, "AI_HELPER_BUFF_SMALL", 100, 1)
    end
end

local GetHostCharacterSafe

local function CallGlobalHasActiveStatus(...)
    return HasActiveStatus(...)
end

local function CallOsiHasActiveStatus(...)
    return Osi.HasActiveStatus(...)
end

local function CallGlobalApplyStatus(...)
    return ApplyStatus(...)
end

local function CallOsiApplyStatus(...)
    return Osi.ApplyStatus(...)
end

local function CallGlobalRemoveStatus(...)
    return RemoveStatus(...)
end

local function CallOsiRemoveStatus(...)
    return Osi.RemoveStatus(...)
end

local function ApplyStatusRaw(character, status, duration, force, source)
    local lastError = nil
    local function callWith(applyStatus)
        if source ~= nil then
            return applyStatus(character, status, duration, force, source)
        elseif force ~= nil then
            return applyStatus(character, status, duration, force)
        else
            return applyStatus(character, status, duration)
        end
    end

    -- Osi.* is the stable path in BG3SE; the global is kept as a fallback for mods
    -- that expose the Osiris call aliases directly.
    local ok, err = pcall(function()
        return callWith(CallOsiApplyStatus)
    end)
    if ok then
        return true, nil
    end
    lastError = err

    ok, err = pcall(function()
        return callWith(CallGlobalApplyStatus)
    end)
    if ok then
        return true, nil
    end
    return false, tostring(lastError or err)
end

local function HasStatusSafe(character, status)
    if not character or character == "" or not status then
        return false
    end
    local candidates = {}
    local function add(fn)
        for _, existing in ipairs(candidates) do
            if existing == fn then return end
        end
        table.insert(candidates, fn)
    end
    add(CallGlobalHasActiveStatus)
    add(CallOsiHasActiveStatus)
    for _, hasActiveStatus in ipairs(candidates) do
        local ok, has = pcall(hasActiveStatus, character, status)
        if ok and has == 1 then
            return true
        end
    end
    return false
end

local function HasPassiveSafe(character, passive)
    if not character or character == "" or not passive then
        return false
    end
    local candidates = {}
    local function add(fn)
        for _, existing in ipairs(candidates) do
            if existing == fn then return end
        end
        table.insert(candidates, fn)
    end
    add(function(...) return HasPassive(...) end)
    add(function(...) return Osi.HasPassive(...) end)
    for _, hasPassive in ipairs(candidates) do
        local ok, has = pcall(hasPassive, character, passive)
        if ok and has == 1 then
            return true
        end
    end
    return false
end

local ManualTargetOrders = { focusTarget = nil, ignoreTargets = {} }
local RuntimeReleaseInProgress = {}
local RuntimeReleaseOwner = {}
local RuntimeCharacterByKey = {}
local RuntimeNPCModeOwner = {}
local RuntimeNPCModeTarget = {}
local RuntimeNPCRestorePending = {}
local RuntimeNPCModeCombatMonitor = {}
local RuntimeNPCModeCombatMonitorSeq = 0
local RuntimeNPCRestoreSeq = 0
local RuntimeAutoSummonCombat = {}
local RuntimeAutoSummonExcludedLog = {}
local RuntimeAutoSummonTemplateMissLog = {}
local RuntimeProcessedStatusApplied = {}
local SUMMON_TAG = "SUMMON_26c78224-a4c1-43e4-b943-75e7fa1bfa41"
local AUTO_SUMMON_RETRY_DELAYS_MS = { 100, 500, 1500 }
local AUTO_SUMMON_DEFAULT_STATUS = "UTAC_SUMMON"
local SHADOW_CURSE_IMMUNITY_STATUS = "UTAC_SHADOW_CURSE_IMMUNITY"
local SCULPT_SPELLS_HELPER_STATUS = Config.SculptSpellsHelperStatus
local AUTO_SUMMON_CONTROL_STATUSES = {
    UTAC_IS_CONTROLLED = true,
    UTAC_SUMMON = true,
    UTAC_SUMMON_COMBAT = true,
    UTAC_GENERAL = true,
    UTAC_GENERAL_COMBAT = true,
}

local GATED_THROW_SPELLS = {
    Throw_Throw = true,
    Throw_ImprovisedWeapon = true,
    Throw_FrenziedThrow = true,
}

local function HasAutoSummonControl(character)
    return HasStatusSafe(character, "UTAC_IS_CONTROLLED")
        or HasStatusSafe(character, AUTO_SUMMON_DEFAULT_STATUS)
        or HasStatusSafe(character, "UTAC_SUMMON_COMBAT")
        or HasStatusSafe(character, "UTAC_GENERAL")
        or HasStatusSafe(character, "UTAC_GENERAL_COMBAT")
end

local function HasManualFocusTarget(target)
    return HasStatusSafe(target, "UTAC_FOCUS_TARGET")
end

local function HasManualIgnoreTarget(target)
    return HasStatusSafe(target, "UTAC_IGNORE_TARGET")
end

local function RemoveStatusIfPresent(character, status, maxAttempts)
    if not character or character == "" or not status then
        return false
    end
    local removeFunctions = {}
    local function add(fn)
        if type(fn) ~= "function" then return end
        for _, existing in ipairs(removeFunctions) do
            if existing == fn then return end
        end
        table.insert(removeFunctions, fn)
    end
    add(CallGlobalRemoveStatus)
    add(CallOsiRemoveStatus)

    local removed = false
    local limit = maxAttempts or 8
    for _ = 1, limit do
        if not HasStatusSafe(character, status) then
            break
        end
        removed = true
        for _, removeStatus in ipairs(removeFunctions) do
            pcall(removeStatus, character, status)
            if not HasStatusSafe(character, status) then
                break
            end
        end
        if #removeFunctions == 0 then
            break
        end
    end
    return removed
end

local function MakePlayerSafe(character, ownerCharacter)
    if not character or character == "" or type(Osi.MakePlayer) ~= "function" then
        return false
    end

    local owner = (ownerCharacter and ownerCharacter ~= "") and ownerCharacter or NULL_UUID
    if owner == NULL_UUID then
        local legacyOk, legacyErr = pcall(Osi.MakePlayer, character)
        if legacyOk then
            InfoPrint(string.format("MakePlayer legacy call issued for %s", tostring(character)))
            return true
        end
        InfoPrint(string.format("Legacy MakePlayer(character) failed for %s: %s; trying MakePlayer(character, owner, 1)", tostring(character), tostring(legacyErr)))
    end

    local ok, err = pcall(Osi.MakePlayer, character, owner, 1)
    if ok then
        InfoPrint(string.format("MakePlayer owner call issued for %s owner=%s", tostring(character), tostring(owner)))
        return true
    end

    InfoPrint(string.format("MakePlayer(character, owner, 1) failed for %s: %s; trying legacy MakePlayer(character)", tostring(character), tostring(err)))
    local fallbackOk, fallbackErr = pcall(Osi.MakePlayer, character)
    if not fallbackOk then
        InfoPrint(string.format("Legacy MakePlayer(character) failed for %s: %s", tostring(character), tostring(fallbackErr)))
    end
    return fallbackOk == true
end

local function ApplyStatusIfMissing(character, status, duration)
    if not character or character == "" or not status then
        return
    end
    local source = GetHostCharacterSafe()
    local statusDuration = duration or -1

    if source and source ~= "" and source ~= character then
        if not HasStatusSafe(character, status) and ApplyStatusRaw(character, status, statusDuration, 1, source) then
            return
        end
        if not HasStatusSafe(character, status) and ApplyStatusRaw(character, status, statusDuration, 0, source) then
            return
        end
    end
    if not HasStatusSafe(character, status) and ApplyStatusRaw(character, status, statusDuration, 1) then
        return
    end
    if not HasStatusSafe(character, status) then
        ApplyStatusRaw(character, status, statusDuration)
    end
end

local function ClearPermanentHelpers(character)
    for _, status in ipairs(Config.AllPermanentHelpers) do
        RemoveStatusIfPresent(character, status)
    end
end

local function SyncShadowCurseProtectionForCharacter(character, enabled)
    if not character or character == "" then
        return
    end

    if enabled == true and IsModEnabled() then
        ApplyStatusIfMissing(character, SHADOW_CURSE_IMMUNITY_STATUS, -1)
    else
        RemoveStatusIfPresent(character, SHADOW_CURSE_IMMUNITY_STATUS)
    end
end

-- === Post-heal tracker (Osiris) ===
if Ext and Ext.Osiris and Ext.Osiris.RegisterListener then
    Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(target, status, causee, storyActionId)
        local stype = Osi.GetStatusType(status)
        if stype == "HEAL" and causee and Osi.Exists(causee) == 1 then
            RuntimeJustHealed[tostring(causee)] = true
        end
    end)
    Ext.Osiris.RegisterListener("TurnStarted", 1, "after", function(char)
        if char then RuntimeJustHealed[tostring(char)] = nil end
    end)
end

-- =================================================================================
-- ||                        COMBAT CACHE & TACTICS MODULES                       ||
-- =================================================================================

local CombatCache = Ext.Require("Server/CombatCache.lua")
local CC_Normalize = CombatCache.CC_Normalize
local GetCombatParticipants = CombatCache.GetCombatParticipants
local GetHealerCombatParticipants = CombatCache.GetHealerCombatParticipants or CombatCache.GetCombatParticipants

local function RememberCharacterHandle(character)
    local key = CC_Normalize(character)
    if key and character and character ~= "" then
        local existing = RuntimeCharacterByKey[key]
        if not (existing and existing ~= key and character == key) then
            RuntimeCharacterByKey[key] = character
        end
    end
    return key
end

local function IsUTACControlledForOptionalHelper(character, key)
    return (key and _G.UTAC_Companions and _G.UTAC_Companions[key] == true)
        or HasStatusSafe(character, "UTAC_IS_CONTROLLED")
        or (key and key ~= character and HasStatusSafe(key, "UTAC_IS_CONTROLLED"))
end

local function HasNPCModeCombatStatus(character, key)
    for _, npcStatus in pairs(Config.CombatStatusNPCMap) do
        if HasStatusSafe(character, npcStatus) or (key and key ~= character and HasStatusSafe(key, npcStatus)) then
            return true
        end
    end
    return false
end

local function LogThrowSpellDiagnostic(caster, spellId)
    if type(spellId) ~= "string" or spellId:sub(1, 6) ~= "Throw_" then
        return
    end

    local key = CC_Normalize(caster)
    if not IsUTACControlledForOptionalHelper(caster, key) then
        return
    end

    InfoPrint(string.format(
        "Throw diagnostic: caster=%s key=%s spell=%s npcMode=%s UTAC_ALLY=%s UTAC_THROWING_DISABLED=%s mcmThrowBlock=%s gatedSpell=%s",
        tostring(caster),
        tostring(key or "none"),
        tostring(spellId),
        tostring(HasNPCModeCombatStatus(caster, key)),
        tostring(HasStatusSafe(caster, "UTAC_ALLY") or (key and key ~= caster and HasStatusSafe(key, "UTAC_ALLY"))),
        tostring(HasStatusSafe(caster, "UTAC_THROWING_DISABLED") or (key and key ~= caster and HasStatusSafe(key, "UTAC_THROWING_DISABLED"))),
        tostring(GetMCM_Bool("MCM_DisableUTACThrow", false)),
        tostring(GATED_THROW_SPELLS[spellId] == true)
    ))
end

local function SyncSculptSpellsHelperForCharacter(character, enabled)
    if not character or character == "" then
        return
    end

    local key = CC_Normalize(character)
    local shouldHave = enabled == true
        and IsModEnabled()
        and IsUTACControlledForOptionalHelper(character, key)

    local seen = {}
    local function syncTarget(target)
        if not target or target == "" or seen[target] then return end
        seen[target] = true
        if shouldHave then
            ApplyStatusIfMissing(target, SCULPT_SPELLS_HELPER_STATUS, -1)
        else
            RemoveStatusIfPresent(target, SCULPT_SPELLS_HELPER_STATUS)
        end
    end

    syncTarget(character)
    if key and key ~= character then
        syncTarget(key)
    end
end

local function IsPlayerSafe(character)
    if not character or character == "" or type(Osi.IsPlayer) ~= "function" then
        return false
    end
    local ok, isPlayer = pcall(Osi.IsPlayer, character, 1)
    return ok and isPlayer == 1
end

local function IsPartyFollowerSafe(character)
    if not character or character == "" or type(Osi.IsPartyFollower) ~= "function" then
        return false
    end
    local ok, isFollower = pcall(Osi.IsPartyFollower, character, 1)
    return ok and isFollower == 1
end

GetHostCharacterSafe = function()
    if type(Osi.GetHostCharacter) == "function" then
        local ok, host = pcall(Osi.GetHostCharacter)
        if ok and host and host ~= "" then
            return host
        end
    end

    local dbs = {
        Osi.DB_Players,
        Osi.DB_Avatars,
        Osi.DB_PartyMembers,
    }
    for _, db in ipairs(dbs) do
        if db and type(db.Get) == "function" then
            local ok, rows = pcall(function()
                return db:Get(nil)
            end)
            if ok and rows then
                for _, row in ipairs(rows) do
                    local candidate = row[1]
                    if candidate and candidate ~= "" and type(Osi.Exists) == "function" then
                        local existsOk, exists = pcall(Osi.Exists, candidate)
                        if existsOk and exists == 1 then
                            return candidate
                        end
                    elseif candidate and candidate ~= "" then
                        return candidate
                    end
                end
            end
        end
    end
    return nil
end

local function IsExistingCharacter(character)
    if not character or character == "" or type(Osi.Exists) ~= "function" then
        return false
    end
    local ok, exists = pcall(Osi.Exists, character)
    return ok and exists == 1
end

local function IsInCombatSafe(character)
    if not character or character == "" or type(Osi.IsInCombat) ~= "function" then
        return false
    end
    local ok, inCombat = pcall(Osi.IsInCombat, character)
    return ok and inCombat == 1
end

local function FindEntityCharacterHandleByKey(key)
    if not key or key == "" or not Ext or not Ext.Entity or type(Ext.Entity.GetAllEntitiesWithComponent) ~= "function" then
        return nil
    end

    local componentNames = { "ServerCharacter", "BaseHp", "Uuid" }
    for _, componentName in ipairs(componentNames) do
        local ok, entities = pcall(Ext.Entity.GetAllEntitiesWithComponent, componentName)
        if ok and entities then
            for _, entity in ipairs(entities) do
                local entityUuid = entity and entity.Uuid and entity.Uuid.EntityUuid or nil
                if entityUuid and CC_Normalize(entityUuid) == key then
                    local handles = { entityUuid }
                    local templateName = entity.ServerCharacter and entity.ServerCharacter.Template and entity.ServerCharacter.Template.Name or nil
                    if templateName and templateName ~= "" and not string.find(entityUuid, "_", 1, true) then
                        table.insert(handles, 1, templateName .. "_" .. entityUuid)
                    end

                    for _, handle in ipairs(handles) do
                        if IsExistingCharacter(handle) then
                            RuntimeCharacterByKey[key] = handle
                            return handle
                        end
                    end

                    local fallback = handles[1]
                    RuntimeCharacterByKey[key] = fallback
                    return fallback
                end
            end
        end
    end

    return nil
end

local function ResolveCharacterHandle(character)
    local key = CC_Normalize(character)
    local candidates = {}
    local seen = {}

    local function add(candidate)
        if not candidate or candidate == "" or seen[candidate] then return end
        seen[candidate] = true
        table.insert(candidates, candidate)
    end

    add(character)
    if key then
        add(RuntimeCharacterByKey[key])
        add(key)
    end

    for _, candidate in ipairs(candidates) do
        if IsExistingCharacter(candidate) then
            if key and candidate ~= key then
                RuntimeCharacterByKey[key] = candidate
            end
            return candidate, key, true
        end
    end

    local entityHandle = FindEntityCharacterHandleByKey(key)
    if entityHandle then
        return entityHandle, key, true
    end

    -- DB_PlayerSummons/DB_PartyFollowers can yield bare UUIDs that Osi.Exists()
    -- rejects even though status and ownership calls still accept the ID.
    if key and character and character ~= "" then
        return RuntimeCharacterByKey[key] or character, key, true
    end

    return RuntimeCharacterByKey[key] or character, key, false
end

local function IsValidMakePlayerOwner(owner, targetKey)
    if not owner or owner == "" or owner == NULL_UUID then
        return false
    end
    local ownerKey = CC_Normalize(owner)
    if targetKey and ownerKey == targetKey then
        return false
    end
    return IsExistingCharacter(owner)
end

local function GetPartyMemberRowsSafe()
    if not (Osi.DB_PartyMembers and type(Osi.DB_PartyMembers.Get) == "function") then
        return nil
    end
    local ok, rows = pcall(function()
        return Osi.DB_PartyMembers:Get(nil)
    end)
    if ok and rows then
        return rows
    end
    return nil
end

local function GetPartyOwnerCandidate(targetKey, preferAvatar)
    local rows = GetPartyMemberRowsSafe()
    if not rows then
        return nil
    end

    local fallback = nil
    local playerFallback = nil
    for _, row in ipairs(rows) do
        local member = row[1]
        local memberKey = CC_Normalize(member)
        if member and member ~= "" and memberKey ~= targetKey and IsExistingCharacter(member) then
            if not fallback then
                fallback = member
            end
            if IsPlayerSafe(member) and not playerFallback then
                playerFallback = member
            end
            if preferAvatar and not IsPartyFollowerSafe(member) then
                return member
            end
        end
    end
    return playerFallback or fallback
end

local function GetPreferredMakePlayerOwner(character, key)
    key = key or CC_Normalize(character)
    local storedOwner = key and RuntimeNPCModeOwner[key] or nil
    if IsValidMakePlayerOwner(storedOwner, key) then
        return storedOwner
    end

    local releaseOwner = key and RuntimeReleaseOwner[key] or nil
    if IsValidMakePlayerOwner(releaseOwner, key) then
        return releaseOwner
    end

    local partyOwner = GetPartyOwnerCandidate(key, true)
    if IsValidMakePlayerOwner(partyOwner, key) then
        return partyOwner
    end

    local host = GetHostCharacterSafe()
    if IsValidMakePlayerOwner(host, key) then
        return host
    end

    return NULL_UUID
end

local function CaptureNPCModeOwner(character, key)
    key = key or CC_Normalize(character)
    if not key then return nil end

    local owner = GetPreferredMakePlayerOwner(character, key)
    RuntimeNPCModeOwner[key] = owner
    RuntimeNPCModeTarget[key] = character
    InfoPrint(string.format("NPC-mode restore state captured for %s target=%s owner=%s", tostring(key), tostring(character), tostring(owner)))
    return owner
end

local function IsPlayerControlledSafe(character)
    if not character or character == "" or type(Osi.IsPlayer) ~= "function" then
        return false
    end
    local ok, isPlayer = pcall(Osi.IsPlayer, character, 1)
    return ok and isPlayer == 1
end

local function IsPartyMemberSafe(character)
    if not character or character == "" or type(Osi.IsPartyMember) ~= "function" then
        return false
    end
    local ok, isParty = pcall(Osi.IsPartyMember, character, 1)
    return ok and isParty == 1
end

local function IsInPartyWithSafe(character, owner)
    if not character or character == "" or not owner or owner == "" or owner == NULL_UUID then
        return false
    end
    if type(Osi.IsInPartyWith) ~= "function" then
        return false
    end
    local ok, inParty = pcall(Osi.IsInPartyWith, character, owner, 1)
    return ok and inParty == 1
end

local function GetNPCModeRestoreState(character, owner)
    if IsPlayerControlledSafe(character) then
        return true, "IsPlayer"
    end
    if IsPartyMemberSafe(character) then
        return true, "IsPartyMember"
    end
    if IsInPartyWithSafe(character, owner) then
        return true, "IsInPartyWithOwner"
    end

    local host = GetHostCharacterSafe()
    if host and host ~= owner and IsInPartyWithSafe(character, host) then
        return true, "IsInPartyWithHost"
    end

    return false, string.format(
        "IsPlayer=%s IsPartyMember=%s IsInPartyWithOwner=%s",
        tostring(IsPlayerControlledSafe(character)),
        tostring(IsPartyMemberSafe(character)),
        tostring(IsInPartyWithSafe(character, owner))
    )
end

local function ClearNPCModeCombatStatuses(character)
    for _, npcCombatStatus in pairs(Config.CombatStatusNPCMap) do
        RemoveStatusIfPresent(character, npcCombatStatus, 3)
    end
end

local function HasAnyNPCModeCombatStatus(character)
    for _, npcCombatStatus in pairs(Config.CombatStatusNPCMap) do
        if HasStatusSafe(character, npcCombatStatus) then
            return true, npcCombatStatus
        end
    end
    return false, nil
end

local function AnyTrackedCompanionInCombat()
    if not _G.UTAC_Companions then
        return false
    end

    local combatDb = Osi.DB_Is_InCombat
    if combatDb and type(combatDb.Get) == "function" then
        local ok, rows = pcall(function()
            return combatDb:Get(nil, nil)
        end)
        if ok and rows then
            for _, row in ipairs(rows) do
                local combatantKey = CC_Normalize(row[1])
                if combatantKey and _G.UTAC_Companions[combatantKey] then
                    return true
                end
            end
        end
    end

    for key, isCompanion in pairs(_G.UTAC_Companions) do
        if isCompanion then
            for _, candidate in ipairs({ RuntimeNPCModeTarget[key], RuntimeCharacterByKey[key], key }) do
                if candidate and candidate ~= "" and type(Osi.IsInCombat) == "function" then
                    local ok, inCombat = pcall(Osi.IsInCombat, candidate)
                    if ok and inCombat == 1 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

local function RestorePlayerControlFromNPCMode(character, reason, options)
    local key = CC_Normalize(character)
    if not key then
        return false
    end
    RuntimeNPCModeCombatMonitor[key] = nil

    if RuntimeNPCRestorePending[key] and not (options and options.force) then
        InfoPrint(string.format(
            "NPC restore already pending for %s; new reason=%s",
            tostring(key),
            tostring(reason or "unknown")
        ))
        return true
    end

    local targetForRestore = RuntimeNPCModeTarget[key] or character
    local owner = (options and options.owner) or GetPreferredMakePlayerOwner(targetForRestore, key)
    RuntimeNPCRestoreSeq = RuntimeNPCRestoreSeq + 1
    local token = RuntimeNPCRestoreSeq
    RuntimeNPCRestorePending[key] = {
        token = token,
        target = targetForRestore,
        owner = owner,
        reason = reason or "unknown",
    }

    local delays = { 0, 250, 1000, 3000, 6000 }

    local function attemptRestore(attempt)
        local pending = RuntimeNPCRestorePending[key]
        if not pending or pending.token ~= token then
            return
        end

        local target = pending.target
        if not IsExistingCharacter(target) and IsExistingCharacter(key) then
            target = key
            pending.target = key
        end

        local restored, state = GetNPCModeRestoreState(target, pending.owner)
        if restored then
            RuntimeNPCRestorePending[key] = nil
            if not HasStatusSafe(key, "UTAC_TOGGLE_IS_NPC") then
                RuntimeNPCModeOwner[key] = nil
                RuntimeNPCModeTarget[key] = nil
            end
            InfoPrint(string.format("NPC restore confirmed for %s via %s", tostring(key), tostring(state)))
            return
        end

        ClearNPCModeCombatStatuses(target)
        MakePlayerSafe(target, pending.owner)

        restored, state = GetNPCModeRestoreState(target, pending.owner)
        if restored then
            RuntimeNPCRestorePending[key] = nil
            if not HasStatusSafe(key, "UTAC_TOGGLE_IS_NPC") then
                RuntimeNPCModeOwner[key] = nil
                RuntimeNPCModeTarget[key] = nil
            end
            InfoPrint(string.format("NPC restore confirmed for %s via %s after MakePlayer", tostring(key), tostring(state)))
            return
        end

        if attempt >= #delays then
            RuntimeNPCRestorePending[key] = nil
            if not HasStatusSafe(key, "UTAC_TOGGLE_IS_NPC") then
                RuntimeNPCModeOwner[key] = nil
                RuntimeNPCModeTarget[key] = nil
            end
            InfoPrint(string.format(
                "NPC restore failed for %s after %d attempts; reason=%s state=%s owner=%s",
                tostring(key),
                attempt,
                tostring(pending.reason),
                tostring(state),
                tostring(pending.owner)
            ))
            return
        end

        local nextAttempt = attempt + 1
        local delay = delays[nextAttempt]
        if Ext and Ext.Timer and type(Ext.Timer.WaitFor) == "function" then
            Ext.Timer.WaitFor(delay, function()
                attemptRestore(nextAttempt)
            end)
        else
            attemptRestore(nextAttempt)
        end
    end

    InfoPrint(string.format(
        "NPC restore scheduled for %s; reason=%s owner=%s",
        tostring(key),
        tostring(reason or "unknown"),
        tostring(owner)
    ))
    attemptRestore(1)
    return true
end

local function ScheduleNPCModePostCombatRestore(character, reason)
    local key = CC_Normalize(character)
    if not key then
        return false
    end

    RuntimeNPCModeCombatMonitorSeq = RuntimeNPCModeCombatMonitorSeq + 1
    local token = RuntimeNPCModeCombatMonitorSeq
    RuntimeNPCModeCombatMonitor[key] = token

    local outOfCombatTicks = 0
    local function monitor()
        if RuntimeNPCModeCombatMonitor[key] ~= token then
            return
        end

        if not IsModEnabled() then
            RuntimeNPCModeCombatMonitor[key] = nil
            return
        end

        if not (_G.UTAC_Companions and _G.UTAC_Companions[key]) then
            RuntimeNPCModeCombatMonitor[key] = nil
            return
        end

        local restored = GetNPCModeRestoreState(key, GetPreferredMakePlayerOwner(key, key))
        if restored then
            RuntimeNPCModeCombatMonitor[key] = nil
            return
        end

        if AnyTrackedCompanionInCombat() then
            outOfCombatTicks = 0
        else
            outOfCombatTicks = outOfCombatTicks + 1
            if outOfCombatTicks >= 8 then
                RuntimeNPCModeCombatMonitor[key] = nil
                RestorePlayerControlFromNPCMode(key, reason or "NPC-mode combat monitor", { force = true })
                return
            end
        end

        if Ext and Ext.Timer and type(Ext.Timer.WaitFor) == "function" then
            Ext.Timer.WaitFor(1000, monitor)
        end
    end

    InfoPrint(string.format("NPC-mode combat monitor started for %s; reason=%s", tostring(key), tostring(reason or "unknown")))
    if Ext and Ext.Timer and type(Ext.Timer.WaitFor) == "function" then
        Ext.Timer.WaitFor(1000, monitor)
    else
        monitor()
    end
    return true
end

_G.UTAC_RestorePlayerControlFromNPCMode = nil

local HealerTacticsCreate = Ext.Require("Server/HealerTactics.lua")
local HealerTactics = HealerTacticsCreate(GetHealerTriageThreshold, GetCombatParticipants)
local AnalyzeCombatState = HealerTactics.AnalyzeCombatState

local ArchetypeTacticsCreate = Ext.Require("Server/ArchetypeTactics.lua")
local ArchetypeTactics = ArchetypeTacticsCreate({
    GetMCM_Bool = GetMCM_Bool,
    GetMCM_Number = GetMCM_Number,
    GetHealerTriageThreshold = GetHealerTriageThreshold,
    PostHealActive = PostHealActive,
    EncourageSpellcasting = EncourageSpellcasting,
    GetAvailableCasterResource = GetAvailableCasterResource,
    HighestSpellSlotLevelAvailable = CombatCache.HighestSpellSlotLevelAvailable,
    UTAC_DistanceToNearestEnemy = CombatCache.UTAC_DistanceToNearestEnemy,
    UTAC_DistanceToNearestAlly = CombatCache.UTAC_DistanceToNearestAlly,
    UTAC_HasAdvantage = CombatCache.UTAC_HasAdvantage,
    HasManualFocusTarget = HasManualFocusTarget,
    HasManualIgnoreTarget = HasManualIgnoreTarget,
    NZ = Config.NZ,
})
local UpdateTargetPriorities = ArchetypeTactics.UpdateTargetPriorities
local ManageCombatTactics = ArchetypeTactics.ManageCombatTactics

-- =================================================================================
-- ||                        CORE MOD LOGIC & STATE MANAGEMENT                    ||
-- =================================================================================

function ReinforceUTACControl()
    if not _G.UTAC_Companions then return end
    for uuid, isControlled in pairs(_G.UTAC_Companions) do
        if isControlled and Osi.Exists(uuid) == 1 then
            local baseStatus = _G.UTAC_BaseStatusByCharacter[uuid]
            if baseStatus and Osi.HasActiveStatus(uuid, baseStatus) == 0 then
                Osi.ApplyStatus(uuid, baseStatus, -1, 1)
            end
            if Osi.HasActiveStatus(uuid, "UTAC_IS_CONTROLLED") == 0 then
                Osi.ApplyStatus(uuid, "UTAC_IS_CONTROLLED", -1, 1)
            end
            if Osi.HasActiveStatus(uuid, "UTAC_ALLY") == 0 then
                Osi.ApplyStatus(uuid, "UTAC_ALLY", -1, 1)
            end
            if Osi.HasActiveStatus(uuid, "UTAC_AVOID_DANGER") == 0 then
                Osi.ApplyStatus(uuid, "UTAC_AVOID_DANGER", -1, 1)
            end
            if Osi.HasActiveStatus(uuid, "AI_TRAP_AWARENESS") == 0 then
                Osi.ApplyStatus(uuid, "AI_TRAP_AWARENESS", -1, 1)
            end
            SyncSculptSpellsHelperForCharacter(uuid, GetMCM_Bool("MCM_EnableSculptSpellsHelper", false))
            pcall(function()
                if Osi.HasPassive(uuid, "UTAC_ToggleNPC") == 0 then
                    Osi.AddPassive(uuid, "UTAC_ToggleNPC")
                    InfoPrint("ReinforceUTACControl: Granted UTAC_ToggleNPC to " .. tostring(uuid))
                end
            end)
        end
    end
end

local function ClearTemporaryHelpers(character)
    for _, status in ipairs(Config.TemporaryHelpers) do
        if Osi.HasActiveStatus(character, status) == 1 then
            Osi.RemoveStatus(character, status)
        end
    end
end

local function UpdateHealerUrgencyOverride(character, combatState)
    local triage = (combatState and combatState.triageThreshold) or GetHealerTriageThreshold()
    local selfHP = (combatState and type(combatState.selfHP) == "number" and combatState.selfHP)
        or ((type(Osi.GetHitpointsPercentage) == "function") and Osi.GetHitpointsPercentage(character) or 100)
    local hasUrgentNeed =
        Config.NZ(combatState and combatState.downedAlliesNearby, 0) > 0
        or Config.NZ(combatState and combatState.alliesLowHP, 0) > 0
        or Config.NZ(combatState and combatState.urgentHealCandidates, 0) > 0
        or (combatState and combatState.selfLowHP == true)
        or (type(selfHP) == "number" and selfHP <= triage)

    local hasOverride = Osi.HasActiveStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE") == 1
    if hasUrgentNeed then
        if hasOverride then
            Osi.RemoveStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE")
        end
    else
        if not hasOverride then
            Osi.ApplyStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE", -1, 1)
        end
    end
    return hasUrgentNeed
end

local GetBaseStatusForCharacter

local function ApplyCombatStatus(character)
    if not IsModEnabled() then return end
    local cKey = CC_Normalize(character)
    if not cKey or not _G.UTAC_Companions[cKey] then return end

    InfoPrint("ApplyCombatStatus for tracked companion: " .. tostring(character))

    local isNPCMode = Osi.HasActiveStatus(character, "UTAC_TOGGLE_IS_NPC") == 1
    local statusToApply = nil
    local baseStatusForCombat = nil

    for baseStatus, _ in pairs(Config.CombatStatusMap) do
        if Osi.HasActiveStatus(character, baseStatus) == 1 then
            baseStatusForCombat = baseStatus
            if isNPCMode then
                statusToApply = Config.CombatStatusNPCMap[baseStatus]
            else
                statusToApply = Config.CombatStatusMap[baseStatus]
            end
            break
        end
    end

    if not statusToApply then
        baseStatusForCombat = GetBaseStatusForCharacter(character)
        if baseStatusForCombat then
            statusToApply = isNPCMode and Config.CombatStatusNPCMap[baseStatusForCombat] or Config.CombatStatusMap[baseStatusForCombat]
        end
    end

    if statusToApply then
        if isNPCMode then
            Osi.MakeNPC(character)
            InfoPrint(string.format("MakeNPC called for %s (NPC toggle active)", tostring(character)))
        end
        if not HasStatusSafe(character, statusToApply) and not HasStatusSafe(cKey, statusToApply) then
            ApplyStatusIfMissing(character, statusToApply, -1)
            if cKey and cKey ~= character then
                ApplyStatusIfMissing(cKey, statusToApply, -1)
            end
            InfoPrint(string.format("Applied combat status '%s' to %s", statusToApply, tostring(character)))
        else
            InfoPrint(string.format("Combat status '%s' already active on %s", statusToApply, tostring(character)))
        end
        if baseStatusForCombat == "UTAC_HEALER" and Osi.HasActiveStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE") == 0 then
            Osi.ApplyStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE", -1, 1)
        end
    else
        InfoPrint("FAILED: No base archetype status found on " .. tostring(character) .. " to determine combat status.")
    end

    UTACSpellPolicy.SyncForCharacter(character, nil, nil, nil, "ApplyCombatStatus")
end

local function TableCount(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

local function DetectBaseArchetypeStatus(character)
    for status, _ in pairs(Config.StatusToArchetype) do
        if HasStatusSafe(character, status) then
            return status
        end
    end
    return nil
end

local ENHANCED_HELPER_STATUSES = {
    "AI_BRUISER_BLOODLUST_ENHANCED",
    "AI_SPELLCASTER_FOCUS_ENHANCED",
}

local TARGET_PRIORITY_STATUSES = {
    "UTAC_PRIORITY_LOW_HP",
    "UTAC_PRIORITY_CONCENTRATION",
    "UTAC_PRIORITY_DANGEROUS",
}

local MOD_DISABLE_RUNTIME_STATUSES = {
    "UTAC_ALLY",
    "UTAC_AVOID_DANGER",
    SHADOW_CURSE_IMMUNITY_STATUS,
    "AI_TRAP_AWARENESS",
    "UTAC_HEALER_NONURGENT_OVERRIDE",
    "UTAC_DASHING_DISABLED",
    "UTAC_THROWING_DISABLED",
    "UTAC_JUMPING_DISABLED",
    "UTAC_SHOVING_DISABLED",
    "UTAC_SURFACE_ESCAPE",
    "AI_HELPER_DIPWEAPON",
    "AI_HELPER_AVOIDAREA",
    "UTAC_REAPPLY_NPC_NEEDED",
    "UTAC_REAPPLY_NPC",
    SCULPT_SPELLS_HELPER_STATUS,
}

local function RemovePassiveIfPresent(character, passive)
    if not character or character == "" or not passive then return end
    local removePassive = type(RemovePassive) == "function" and RemovePassive or Osi.RemovePassive
    if type(removePassive) ~= "function" then return end

    if HasPassiveSafe(character, passive) then
        pcall(removePassive, character, passive)
        return true
    end
    return false
end

GetBaseStatusForCharacter = function(character)
    local key = CC_Normalize(character)
    if not key then return nil end

    local tracked = _G.UTAC_BaseStatusByCharacter and _G.UTAC_BaseStatusByCharacter[key]
    if tracked and Config.StatusToArchetype[tracked] then
        return tracked
    end
    local liveCharacter = RuntimeCharacterByKey[key] or character
    return DetectBaseArchetypeStatus(liveCharacter) or DetectBaseArchetypeStatus(key)
end

local function IsKnownUTACCharacter(character)
    local key = CC_Normalize(character)
    if not key then return false end

    if _G.UTAC_Companions and _G.UTAC_Companions[key] then
        return true
    end
    if _G.UTAC_BaseStatusByCharacter and _G.UTAC_BaseStatusByCharacter[key] then
        return true
    end
    local liveCharacter = RuntimeCharacterByKey[key] or character
    if HasStatusSafe(key, "UTAC_IS_CONTROLLED") or HasStatusSafe(liveCharacter, "UTAC_IS_CONTROLLED") then
        return true
    end
    return GetBaseStatusForCharacter(key) ~= nil
end

local function IsEnemySafe(left, right)
    if not left or left == "" or not right or right == "" or type(Osi.IsEnemy) ~= "function" then
        return false
    end
    local ok, isEnemy = pcall(Osi.IsEnemy, left, right)
    return ok and isEnemy == 1
end

local function IsSummonSafe(character)
    if not character or character == "" or type(Osi.IsSummon) ~= "function" then
        return false
    end
    local ok, isSummon = pcall(Osi.IsSummon, character)
    return ok and isSummon == 1
end

local function IsTaggedSafe(character, tag)
    if not character or character == "" or not tag or tag == "" or type(Osi.IsTagged) ~= "function" then
        return false
    end
    local ok, isTagged = pcall(Osi.IsTagged, character, tag)
    return ok and isTagged == 1
end

local function GetCharacterOwnerSafe(character)
    if not character or character == "" then
        return nil
    end
    local ownerCalls = {
        type(CharacterGetOwner) == "function" and CharacterGetOwner or nil,
        type(Osi.CharacterGetOwner) == "function" and Osi.CharacterGetOwner or nil,
    }
    for _, getOwner in ipairs(ownerCalls) do
        if type(getOwner) == "function" then
            local ok, owner = pcall(getOwner, character)
            if ok and owner and owner ~= "" and owner ~= NULL_UUID then
                return owner
            end
        end
    end
    return nil
end

local function NormalizeUuidToken(value)
    if type(value) ~= "string" then
        return nil
    end

    return value:lower():match("(%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x)")
end

local function ExtractUuidFromTemplateValue(value, depth)
    if not value or depth > 2 then
        return nil
    end

    if type(value) == "string" then
        return NormalizeUuidToken(value)
    end

    if type(value) ~= "table" then
        return nil
    end

    local directKeys = {
        "TemplateId",
        "TemplateGuid",
        "Template",
        "RootTemplate",
        "RootTemplateId",
        "RootTemplateGuid",
        "ParentTemplate",
        "ParentTemplateId",
        "ResourceUUID",
        "ResourceGuid",
        "UUID",
        "Uuid",
        "Guid",
        "Id",
    }

    for _, key in ipairs(directKeys) do
        local ok, candidate = pcall(function()
            return value[key]
        end)
        if ok then
            local uuid = ExtractUuidFromTemplateValue(candidate, depth + 1)
            if uuid then
                return uuid
            end
        end
    end

    local okEntityUuid, entityUuid = pcall(function()
        return value.Uuid and value.Uuid.EntityUuid or nil
    end)
    if okEntityUuid then
        return NormalizeUuidToken(entityUuid)
    end

    return nil
end

local function AddTemplateCandidate(candidates, seen, value)
    local uuid = ExtractUuidFromTemplateValue(value, 0)
    if uuid and not seen[uuid] then
        seen[uuid] = true
        table.insert(candidates, uuid)
    end
end

local function GetCharacterTemplateUuidSafe(character)
    if not character or character == "" then
        return nil
    end

    local candidates = {}
    local seen = {}

    local templateCalls = {
        type(Osi.GetTemplate) == "function" and Osi.GetTemplate or nil,
        type(GetTemplate) == "function" and GetTemplate or nil,
    }
    for _, getTemplate in ipairs(templateCalls) do
        if type(getTemplate) == "function" then
            local ok, template = pcall(getTemplate, character)
            if ok then
                AddTemplateCandidate(candidates, seen, template)
            end
        end
    end

    if Ext and Ext.Entity and type(Ext.Entity.Get) == "function" then
        local okEntity, entity = pcall(Ext.Entity.Get, character)
        if okEntity and entity then
            local okCollect = pcall(function()
                AddTemplateCandidate(candidates, seen, entity.Template)
                AddTemplateCandidate(candidates, seen, entity.TemplateId)
                AddTemplateCandidate(candidates, seen, entity.RootTemplate)
                AddTemplateCandidate(candidates, seen, entity.RootTemplateId)

                local serverCharacter = entity.ServerCharacter
                if serverCharacter then
                    AddTemplateCandidate(candidates, seen, serverCharacter.Template)
                    AddTemplateCandidate(candidates, seen, serverCharacter.TemplateId)
                    AddTemplateCandidate(candidates, seen, serverCharacter.TemplateGuid)
                    AddTemplateCandidate(candidates, seen, serverCharacter.RootTemplate)
                    AddTemplateCandidate(candidates, seen, serverCharacter.RootTemplateId)
                    AddTemplateCandidate(candidates, seen, serverCharacter.RootTemplateGuid)
                end

                local gameObjectVisual = entity.GameObjectVisual
                if gameObjectVisual then
                    AddTemplateCandidate(candidates, seen, gameObjectVisual.RootTemplate)
                    AddTemplateCandidate(candidates, seen, gameObjectVisual.RootTemplateId)
                    AddTemplateCandidate(candidates, seen, gameObjectVisual.RootTemplateGuid)
                end
            end)
            if not okCollect then
                -- Fail open; template resolution is a compatibility convenience, not a hard requirement.
            end
        end
    end

    return candidates[1]
end

local function GetCombatGuidForSafe(character)
    if not character or character == "" or type(Osi.CombatGetGuidFor) ~= "function" then
        return nil
    end
    local ok, combatGuid = pcall(Osi.CombatGetGuidFor, character)
    if ok and combatGuid and combatGuid ~= "" then
        return combatGuid
    end
    return nil
end

local function GetTemporaryPartyFollowerOwner(character)
    if not character or character == "" or not Ext or not Ext.Entity or type(Ext.Entity.Get) ~= "function" then
        return nil
    end

    local ok, entity = pcall(Ext.Entity.Get, character)
    if not ok or not entity then
        return nil
    end

    local isTemporary = false
    local serverCharacter = entity.ServerCharacter
    if serverCharacter and serverCharacter.Temporary == true then
        isTemporary = true
    end

    local follower = entity.PartyFollower
    local following = follower and follower.Following or nil
    local leader = nil
    if following then
        if type(following) == "string" then
            leader = following
        elseif following.Uuid and following.Uuid.EntityUuid then
            leader = following.Uuid.EntityUuid
        end
    end

    if isTemporary and leader and leader ~= "" then
        return leader
    end
    return nil
end

local function IsAutoSummonOwnerAllowed(owner, candidateKey, candidateHandle)
    if not owner or owner == "" or owner == NULL_UUID then
        return false
    end

    local ownerHandle, ownerKey, ownerExists = ResolveCharacterHandle(owner)
    if not ownerKey or ownerKey == candidateKey or not ownerExists then
        return false
    end
    if IsEnemySafe(candidateHandle or candidateKey, ownerHandle) or IsEnemySafe(ownerHandle, candidateHandle or candidateKey) then
        return false
    end

    return IsPartyMemberSafe(ownerHandle)
        or IsPartyFollowerSafe(ownerHandle)
        or IsPlayerControlledSafe(ownerHandle)
        or (_G.UTAC_Companions and _G.UTAC_Companions[ownerKey] == true)
        or HasStatusSafe(ownerHandle, "UTAC_IS_CONTROLLED")
end

local function GetKnownSummonCandidates(seed)
    local candidates = {}
    local seen = {}

    local function add(candidate)
        local key = CC_Normalize(candidate)
        if not key or key == "" or seen[key] then return end
        seen[key] = true
        table.insert(candidates, candidate)
    end

    add(seed)

    local function addDbRows(db)
        if not (db and type(db.Get) == "function") then return end
        local ok, rows = pcall(function()
            return db:Get(nil)
        end)
        if not ok or not rows then return end
        for _, row in ipairs(rows) do
            add(row[1])
        end
    end

    addDbRows(Osi.DB_PlayerSummons)
    addDbRows(Osi.DB_PartyFollowers)

    return candidates
end

local function IsInOsirisCharacterDb(db, key)
    if not key or key == "" or not (db and type(db.Get) == "function") then
        return false
    end
    local ok, rows = pcall(function()
        return db:Get(nil)
    end)
    if not ok or not rows then
        return false
    end
    for _, row in ipairs(rows) do
        if CC_Normalize(row[1]) == key then
            return true
        end
    end
    return false
end

local function IsLikelyAlliedSummon(candidate)
    local liveCharacter, key, exists = ResolveCharacterHandle(candidate)
    if not key then
        return false, "missing character key", nil
    end
    if not exists then
        return false, "character no longer exists", nil
    end
    RememberCharacterHandle(liveCharacter)

    local isSummon = IsSummonSafe(liveCharacter)
    local hasSummonTag = IsTaggedSafe(liveCharacter, SUMMON_TAG)
    local owner = GetCharacterOwnerSafe(liveCharacter)
    local followerOwner = GetTemporaryPartyFollowerOwner(liveCharacter)
    local hasOwnerSignal = owner ~= nil and not IsPartyMemberSafe(liveCharacter)
    local isKnownPlayerSummon = IsInOsirisCharacterDb(Osi.DB_PlayerSummons, key)
    local isKnownPartyFollower = IsInOsirisCharacterDb(Osi.DB_PartyFollowers, key)
    local hasSummonSignal = isKnownPlayerSummon or isSummon or hasSummonTag or isKnownPartyFollower or followerOwner ~= nil or hasOwnerSignal

    if not hasSummonSignal then
        return false, "not a summon or temporary party follower", nil
    end

    if isKnownPlayerSummon then
        local dbOwner = owner or followerOwner or GetHostCharacterSafe()
        if dbOwner and not IsEnemySafe(liveCharacter, dbOwner) then
            return true, "DB_PlayerSummons", dbOwner
        end
        return true, "DB_PlayerSummons", nil
    end

    local allowedOwner = nil
    if IsAutoSummonOwnerAllowed(owner, key, liveCharacter) then
        allowedOwner = owner
    elseif IsAutoSummonOwnerAllowed(followerOwner, key, liveCharacter) then
        allowedOwner = followerOwner
    end

    if allowedOwner then
        return true, "owner is party/UTAC ally", allowedOwner
    end

    local host = GetHostCharacterSafe()
    if host and (isSummon or hasSummonTag or followerOwner ~= nil) and not IsEnemySafe(liveCharacter, host) then
        return true, "summon is not hostile to host", host
    end

    return false, "owner is not a party/UTAC ally", owner or followerOwner
end

local function ScheduleSummonCombatStatus(character, reason)
    local liveCharacter, key, exists = ResolveCharacterHandle(character)
    if not key or not exists or not _G.UTAC_Companions[key] or not IsInCombatSafe(liveCharacter) then
        return
    end

    RuntimeAutoSummonCombat[key] = GetCombatGuidForSafe(liveCharacter) or true
    Ext.Timer.WaitFor(100, function()
        local target = RuntimeCharacterByKey[key] or liveCharacter
        local resolvedTarget, _, targetExists = ResolveCharacterHandle(target)
        if targetExists and _G.UTAC_Companions[key] and IsInCombatSafe(resolvedTarget) then
            InfoPrint(string.format("Auto summon applying combat status to %s; reason=%s", tostring(key), tostring(reason)))
            ApplyCombatStatus(key)
            ApplyCombatStatus(resolvedTarget)
        end
    end)
end

local function LogAutoSummonSkip(reason, message)
    local reasonText = tostring(reason or "")
    if string.find(reasonText, "^EnteredCombat") then
        return
    end
    InfoPrint(message)
end

local function AddStatusTarget(targets, seen, candidate)
    if not candidate or candidate == "" then return end
    local id = tostring(candidate)
    if id == "" or seen[id] then return end
    seen[id] = true
    table.insert(targets, candidate)
end

local function GetStatusTargetVariants(candidate, liveCharacter, key, extraTargets)
    local targets = {}
    local seen = {}
    key = key or CC_Normalize(candidate) or CC_Normalize(liveCharacter)

    -- Prefer the live entity handle; DB_PlayerSummons often reports only a bare
    -- UUID, but the status event lands on the resolved summon handle.
    AddStatusTarget(targets, seen, liveCharacter)
    if key then
        AddStatusTarget(targets, seen, RuntimeCharacterByKey[key])
        AddStatusTarget(targets, seen, FindEntityCharacterHandleByKey(key))
    end
    -- Keep the raw IDs as fallback because some Osiris calls accept them.
    AddStatusTarget(targets, seen, candidate)
    AddStatusTarget(targets, seen, key)
    if type(extraTargets) == "table" then
        for _, target in ipairs(extraTargets) do
            AddStatusTarget(targets, seen, target)
        end
    end

    return targets
end

local function GetOwnerForStatusTargets(statusTargets, targetKey)
    for _, target in ipairs(statusTargets or {}) do
        local owner = GetCharacterOwnerSafe(target)
        if owner and owner ~= "" and owner ~= NULL_UUID and CC_Normalize(owner) ~= targetKey then
            return owner
        end
    end

    local partyOwner = GetPartyOwnerCandidate(targetKey, true)
    if partyOwner and partyOwner ~= "" and CC_Normalize(partyOwner) ~= targetKey then
        return partyOwner
    end

    local host = GetHostCharacterSafe()
    if host and host ~= "" and CC_Normalize(host) ~= targetKey then
        return host
    end
    return nil
end

local function HasAutoSummonControlOnTargets(targets)
    for _, target in ipairs(targets or {}) do
        if HasAutoSummonControl(target) then
            return true, target
        end
    end
    return false, nil
end

local function GetBaseStatusForTargets(targets)
    for _, target in ipairs(targets or {}) do
        local baseStatus = GetBaseStatusForCharacter(target)
        if baseStatus then
            return baseStatus, target
        end
    end
    return nil, nil
end

local function BuildAutoSummonExclusionSet()
    local set = {}
    if UTACSettings and type(UTACSettings.GetAutoSummonExclusionTokens) == "function" then
        for _, uuid in ipairs(UTACSettings.GetAutoSummonExclusionTokens()) do
            set[uuid] = true
        end
    end
    return set
end

local function GetExcludedAutoSummonTemplate(candidate, liveCharacter, key)
    local exclusions = BuildAutoSummonExclusionSet()
    if not next(exclusions) then
        return false, nil
    end

    local targets = GetStatusTargetVariants(candidate, liveCharacter, key)
    for _, target in ipairs(targets) do
        local templateUuid = GetCharacterTemplateUuidSafe(target)
        if templateUuid and exclusions[templateUuid] then
            return true, templateUuid
        end
    end

    return false, nil
end

local function LogAutoSummonExcluded(key, templateUuid, reason)
    if not key then return end
    local marker = tostring(templateUuid or "unknown")
    if RuntimeAutoSummonExcludedLog[key] == marker then
        return
    end
    RuntimeAutoSummonExcludedLog[key] = marker
    InfoPrint(string.format(
        "Auto summon excluded by root/template UUID: %s template=%s reason=%s",
        tostring(key),
        tostring(templateUuid or "unknown"),
        tostring(reason)
    ))
end

local function LogAutoSummonTemplateMiss(key, reason)
    if not key or RuntimeAutoSummonTemplateMissLog[key] then
        return
    end
    RuntimeAutoSummonTemplateMissLog[key] = true
    InfoPrint(string.format(
        "Auto summon exclusion check could not resolve root/template UUID for %s; failing open. reason=%s",
        tostring(key),
        tostring(reason)
    ))
end

local function ClearAutoSummonControlForExcluded(candidate, reason, templateUuid, statusTargets)
    local liveCharacter, key, exists = ResolveCharacterHandle(candidate)
    key = key or CC_Normalize(candidate)
    if not key then
        return false
    end

    statusTargets = statusTargets or GetStatusTargetVariants(candidate, liveCharacter, key)
    local tracked = _G.UTAC_Companions and _G.UTAC_Companions[key] == true
    local baseStatus = (_G.UTAC_BaseStatusByCharacter and _G.UTAC_BaseStatusByCharacter[key]) or GetBaseStatusForTargets(statusTargets)
    local hasAutoSummonStatus = false
    for _, target in ipairs(statusTargets) do
        if HasStatusSafe(target, "UTAC_SUMMON")
            or HasStatusSafe(target, "UTAC_SUMMON_COMBAT")
            or HasStatusSafe(target, "UTAC_GENERAL")
            or HasStatusSafe(target, "UTAC_GENERAL_COMBAT") then
            hasAutoSummonStatus = true
            break
        end
    end

    local hasManualNonSummonBase = baseStatus ~= nil
        and baseStatus ~= AUTO_SUMMON_DEFAULT_STATUS
        and baseStatus ~= "UTAC_GENERAL"
    local isKnownSummonDb = IsInOsirisCharacterDb(Osi.DB_PlayerSummons, key)
        or IsInOsirisCharacterDb(Osi.DB_PartyFollowers, key)
    local shouldClear = RuntimeAutoSummonCombat[key] ~= nil
        or baseStatus == AUTO_SUMMON_DEFAULT_STATUS
        or baseStatus == "UTAC_GENERAL"
        or hasAutoSummonStatus
        or (tracked and isKnownSummonDb and not hasManualNonSummonBase)

    if not shouldClear then
        LogAutoSummonExcluded(key, templateUuid, reason)
        return false
    end

    for _, target in ipairs(statusTargets) do
        RemoveStatusIfPresent(target, "UTAC_SUMMON_COMBAT")
        RemoveStatusIfPresent(target, "UTAC_GENERAL_COMBAT")
        RemoveStatusIfPresent(target, "UTAC_SUMMON")
        RemoveStatusIfPresent(target, "UTAC_GENERAL")
        RemoveStatusIfPresent(target, "UTAC_IS_CONTROLLED")
        SyncShadowCurseProtectionForCharacter(target, false)
        SyncSculptSpellsHelperForCharacter(target, false)
    end

    if UTACSpellPolicy and type(UTACSpellPolicy.ClearForCharacter) == "function" then
        UTACSpellPolicy.ClearForCharacter(key, "auto summon excluded: " .. tostring(reason))
    end

    if _G.UTAC_Companions then
        _G.UTAC_Companions[key] = nil
    end
    if _G.UTAC_BaseStatusByCharacter and (baseStatus == AUTO_SUMMON_DEFAULT_STATUS or baseStatus == "UTAC_GENERAL") then
        _G.UTAC_BaseStatusByCharacter[key] = nil
    end
    RuntimeAutoSummonCombat[key] = nil
    RuntimeReleaseOwner[key] = nil
    RuntimeAutoSummonExcludedLog[key] = nil

    LogAutoSummonExcluded(key, templateUuid, reason)
    return exists ~= false
end

local function IsAutoSummonCandidateExcluded(candidate, reason, shouldClear, liveCharacter, key, statusTargets)
    key = key or CC_Normalize(candidate) or CC_Normalize(liveCharacter)
    if not key then
        return false
    end

    if liveCharacter == nil then
        local resolved, resolvedKey = ResolveCharacterHandle(candidate)
        liveCharacter = resolved
        key = key or resolvedKey
    end

    local excluded, templateUuid = GetExcludedAutoSummonTemplate(candidate, liveCharacter, key)
    if excluded then
        if shouldClear then
            ClearAutoSummonControlForExcluded(candidate, reason, templateUuid, statusTargets)
        else
            LogAutoSummonExcluded(key, templateUuid, reason)
        end
        return true
    end

    if next(BuildAutoSummonExclusionSet()) and not GetCharacterTemplateUuidSafe(liveCharacter or candidate) then
        LogAutoSummonTemplateMiss(key, reason)
    end

    return false
end

local function ResyncAutoSummonExclusions(reason)
    local seen = {}
    local candidates = {}

    local function add(candidate)
        local key = CC_Normalize(candidate)
        if not key or seen[key] then return end
        seen[key] = true
        table.insert(candidates, candidate)
    end

    for _, candidate in ipairs(GetKnownSummonCandidates(nil)) do
        add(candidate)
    end
    for key, tracked in pairs(_G.UTAC_Companions or {}) do
        if tracked then
            add(key)
        end
    end
    for key, _ in pairs(RuntimeAutoSummonCombat) do
        add(key)
    end

    for _, candidate in ipairs(candidates) do
        IsAutoSummonCandidateExcluded(candidate, reason or "summon exclusion resync", true)
    end
end

local function ApplyStatusToSingleSummonTarget(target, status, source)
    if not target or target == "" or not status then
        return false
    end
    if HasStatusSafe(target, status) then
        return true
    end

    if source and source ~= "" and source ~= NULL_UUID and ApplyStatusRaw(target, status, -1.0, 1, source) then
        return true
    end
    if ApplyStatusRaw(target, status, -1.0, 1) then
        return true
    end
    -- Match Automated Summons SE's simple status application shape.
    if ApplyStatusRaw(target, status, -1.0) then
        return true
    end

    return HasStatusSafe(target, status)
end

local function ApplySummonStatusAndConfirm(character, status, source, statusTargets)
    if not character or character == "" or not status then
        return false, nil
    end

    local targets = GetStatusTargetVariants(character, nil, nil, statusTargets)
    for _, target in ipairs(targets) do
        if HasStatusSafe(target, status) then
            return true, target
        end
    end
    for _, target in ipairs(targets) do
        if ApplyStatusToSingleSummonTarget(target, status, source) then
            return true, target
        end
    end
    return false, nil
end

local function FinalizeAutoSummonApplied(liveCharacter, key, baseStatus, owner, why, reason)
    _G.UTAC_Companions[key] = true
    _G.UTAC_BaseStatusByCharacter[key] = baseStatus
    SyncShadowCurseProtectionForCharacter(liveCharacter, GetMCM_Bool("MCM_EnableShadowCurseProtection", false))
    SyncSculptSpellsHelperForCharacter(liveCharacter, GetMCM_Bool("MCM_EnableSculptSpellsHelper", false))

    InfoPrint(string.format(
        "Auto summon applied: %s handle=%s base=%s owner=%s source=%s reason=%s",
        tostring(key),
        tostring(liveCharacter),
        tostring(baseStatus),
        tostring(owner or "none"),
        tostring(why),
        tostring(reason)
    ))
    ScheduleSummonCombatStatus(liveCharacter, reason)
end

local function TryAutoApplySummonAI(candidate, reason)
    if not IsModEnabled() then return false end
    if not UTACSettings.GetBool("MCM_AutoApplySummons", true) then
        return false
    end

    local liveCharacter, key, exists = ResolveCharacterHandle(candidate)
    if not key then
        LogAutoSummonSkip(reason, "Auto summon skipped: missing key; reason=" .. tostring(reason))
        return false
    end
    if not exists then
        LogAutoSummonSkip(reason, "Auto summon skipped: " .. tostring(key) .. " (character no longer exists); reason=" .. tostring(reason))
        return false
    end
    RememberCharacterHandle(liveCharacter)
    local statusTargets = GetStatusTargetVariants(candidate, liveCharacter, key)

    if IsAutoSummonCandidateExcluded(candidate, reason, true, liveCharacter, key, statusTargets) then
        return false
    end

    local alreadyTracked = _G.UTAC_Companions and _G.UTAC_Companions[key] == true

    local alreadyControlled = false
    alreadyControlled = HasAutoSummonControlOnTargets(statusTargets)
    if alreadyControlled then
        if not alreadyTracked then
            local existingBaseStatus = GetBaseStatusForTargets(statusTargets) or AUTO_SUMMON_DEFAULT_STATUS
            FinalizeAutoSummonApplied(liveCharacter, key, existingBaseStatus, nil, "existing control", reason)
            return true
        end
        return false
    end
    if alreadyTracked then
        return false
    end

    local reasonText = tostring(reason or "")
    local allied = false
    local why = nil
    local owner = nil
    if string.find(reasonText, "^DB_PlayerSummons") then
        allied = true
        why = "DB_PlayerSummons"
        owner = GetOwnerForStatusTargets(statusTargets, key)
    else
        allied, why, owner = IsLikelyAlliedSummon(liveCharacter)
        if not allied then
            LogAutoSummonSkip(reason, "Auto summon skipped: " .. tostring(key) .. " (" .. tostring(why) .. "); reason=" .. tostring(reason))
            return false
        end
    end

    local baseStatus = GetBaseStatusForTargets(statusTargets)
    if owner and owner ~= "" and owner ~= NULL_UUID then
        RuntimeReleaseOwner[key] = owner
    end

    local appliedControl = ApplySummonStatusAndConfirm(candidate, "UTAC_IS_CONTROLLED", owner, statusTargets)
    if baseStatus then
        appliedControl = ApplySummonStatusAndConfirm(candidate, baseStatus, owner, statusTargets) or appliedControl
    else
        appliedControl = ApplySummonStatusAndConfirm(candidate, AUTO_SUMMON_DEFAULT_STATUS, owner, statusTargets) or appliedControl
        baseStatus = AUTO_SUMMON_DEFAULT_STATUS
    end

    local hasControl = false
    hasControl = HasAutoSummonControlOnTargets(statusTargets)
    if not appliedControl or not hasControl then
        local resolvedAgain = FindEntityCharacterHandleByKey(key)
        if resolvedAgain and resolvedAgain ~= liveCharacter then
            liveCharacter = resolvedAgain
            statusTargets = GetStatusTargetVariants(candidate, liveCharacter, key)
            appliedControl = ApplySummonStatusAndConfirm(candidate, "UTAC_IS_CONTROLLED", owner, statusTargets) or appliedControl
            if baseStatus then
                appliedControl = ApplySummonStatusAndConfirm(candidate, baseStatus, owner, statusTargets) or appliedControl
            end
            hasControl = HasAutoSummonControlOnTargets(statusTargets)
        end
    end

    hasControl = HasAutoSummonControlOnTargets(statusTargets)
    if appliedControl or hasControl then
        local applySource = hasControl and why or (tostring(why) .. " status queued")
        FinalizeAutoSummonApplied(liveCharacter, key, baseStatus, owner, applySource, reason)
        return true
    end

    LogAutoSummonSkip(reason, "Auto summon failed to apply UTAC statuses on " .. tostring(key) .. " handle=" .. tostring(liveCharacter) .. "; reason=" .. tostring(reason))
    return false
end

local function ScheduleAutoSummonRetry(candidate, reason)
    if not candidate or candidate == "" then return end

    local liveCharacter, key, exists = ResolveCharacterHandle(candidate)
    if key and exists and _G.UTAC_Companions and _G.UTAC_Companions[key] then
        if IsAutoSummonCandidateExcluded(candidate, reason, true, liveCharacter, key) then
            return
        end
        return
    end
    if key and exists and IsAutoSummonCandidateExcluded(candidate, reason, true, liveCharacter, key) then
        return
    end

    TryAutoApplySummonAI(candidate, reason or "immediate")
    for _, delay in ipairs(AUTO_SUMMON_RETRY_DELAYS_MS) do
        Ext.Timer.WaitFor(delay, function()
            local liveCharacter, key, exists = ResolveCharacterHandle(candidate)
            local statusTargets = GetStatusTargetVariants(candidate, liveCharacter, key)
            if key and exists and IsAutoSummonCandidateExcluded(candidate, string.format("%s retry %sms", tostring(reason or "scheduled"), tostring(delay)), true, liveCharacter, key, statusTargets) then
                return
            end
            if key and exists
                and not (_G.UTAC_Companions and _G.UTAC_Companions[key])
                and not HasAutoSummonControlOnTargets(statusTargets) then
                TryAutoApplySummonAI(candidate, string.format("%s retry %sms", tostring(reason or "scheduled"), tostring(delay)))
            end
        end)
    end
end

local function ScanKnownSummonCandidates(reason, seed)
    for _, candidate in ipairs(GetKnownSummonCandidates(seed)) do
        ScheduleAutoSummonRetry(candidate, reason)
    end
end

local function CollectKnownUTACCharacters(includeCombatCache)
    local out = {}
    local seen = {}

    local function add(char)
        local key = CC_Normalize(char)
        if not key or key == "" or seen[key] then return end
        seen[key] = true
        if IsKnownUTACCharacter(key) then
            table.insert(out, key)
        end
    end

    for uuid, tracked in pairs(_G.UTAC_Companions or {}) do
        if tracked then
            add(uuid)
        end
    end
    for uuid, _ in pairs(_G.UTAC_BaseStatusByCharacter or {}) do
        add(uuid)
    end

    if Osi.DB_PartyMembers and Osi.DB_PartyMembers.Get then
        local okParty, partyRows = pcall(function()
            return Osi.DB_PartyMembers:Get(nil)
        end)
        if okParty and partyRows then
            for _, row in ipairs(partyRows) do
                add(row[1])
            end
        end
    end

    if Osi.DB_PartOfTheTeam and Osi.DB_PartOfTheTeam.Get then
        local okTeam, teamRows = pcall(function()
            return Osi.DB_PartOfTheTeam:Get(nil)
        end)
        if okTeam and teamRows then
            for _, row in ipairs(teamRows) do
                add(row[1])
            end
        end
    end

    if includeCombatCache and _G.UTAC_CombatCache and _G.UTAC_CombatCache.charToCombat then
        for uuid, _ in pairs(_G.UTAC_CombatCache.charToCombat) do
            add(uuid)
        end
    end

    return out
end

local function RepairStuckNPCModeCharacters(source)
    for _, key in ipairs(CollectKnownUTACCharacters(true)) do
        if IsExistingCharacter(key)
            and _G.UTAC_Companions
            and _G.UTAC_Companions[key]
            and Osi.IsInCombat(key) ~= 1 then
            local owner = GetPreferredMakePlayerOwner(key, key)
            local restored = GetNPCModeRestoreState(key, owner)
            if not restored then
                Osi.MakePlayer(RuntimeCharacterByKey[key] or key)
                InfoPrint("Repair: MakePlayer for stuck NPC-mode character " .. tostring(key) .. " (" .. tostring(source or "repair") .. ")")
            end
        end
    end
end

local function CollectCombatCacheCharacters()
    local out = {}
    local seen = {}
    if _G.UTAC_CombatCache and _G.UTAC_CombatCache.charToCombat then
        for uuid, _ in pairs(_G.UTAC_CombatCache.charToCombat) do
            local key = CC_Normalize(uuid)
            if key and key ~= "" and not seen[key] then
                seen[key] = true
                table.insert(out, key)
            end
        end
    end
    return out
end

local function ClearTargetPriorityStatuses(character)
    for _, status in ipairs(TARGET_PRIORITY_STATUSES) do
        RemoveStatusIfPresent(character, status)
    end
end

local function RemovePreferredTargetTag(character)
    if character and character ~= "" and type(Osi.RemovePreferredAiTargetTag) == "function" then
        pcall(Osi.RemovePreferredAiTargetTag, character, "AI_PREFERRED_TARGET")
    end
end

local function ApplyPreferredTargetTag(character)
    if character and character ~= "" and type(Osi.AddPreferredAiTargetTag) == "function" then
        pcall(Osi.AddPreferredAiTargetTag, character, "AI_PREFERRED_TARGET")
    end
end

local function SyncManualPreferredTargetTags()
    local focusTarget = ManualTargetOrders.focusTarget
    local hasLiveFocus = focusTarget and Osi.Exists(focusTarget) == 1 and HasManualFocusTarget(focusTarget)

    for _, key in ipairs(CollectKnownUTACCharacters(true)) do
        if Osi.Exists(key) == 1 then
            if hasLiveFocus then
                ApplyPreferredTargetTag(key)
            else
                RemovePreferredTargetTag(key)
            end
        end
    end
end

local function ClearManualTargetOrders(reason)
    local targets = {}
    if ManualTargetOrders.focusTarget then
        targets[ManualTargetOrders.focusTarget] = true
    end
    for target in pairs(ManualTargetOrders.ignoreTargets or {}) do
        targets[target] = true
    end

    ManualTargetOrders.focusTarget = nil
    ManualTargetOrders.ignoreTargets = {}

    for target in pairs(targets) do
        if Osi.Exists(target) == 1 then
            RemoveStatusIfPresent(target, "UTAC_FOCUS_TARGET")
            RemoveStatusIfPresent(target, "UTAC_IGNORE_TARGET")
            ClearTargetPriorityStatuses(target)
        end
    end

    for _, key in ipairs(CollectKnownUTACCharacters(true)) do
        RemovePreferredTargetTag(key)
    end

    InfoPrint("Cleared manual target orders: " .. tostring(reason or "unknown"))
end

local function PruneManualTargetOrders(enemies)
    local focusTarget = ManualTargetOrders.focusTarget
    if focusTarget and (Osi.Exists(focusTarget) ~= 1 or not HasManualFocusTarget(focusTarget)) then
        ManualTargetOrders.focusTarget = nil
    end

    for target in pairs(ManualTargetOrders.ignoreTargets or {}) do
        if Osi.Exists(target) ~= 1 or not HasManualIgnoreTarget(target) then
            ManualTargetOrders.ignoreTargets[target] = nil
        end
    end

    if enemies then
        for _, enemy in ipairs(enemies) do
            local key = CC_Normalize(enemy)
            if key and HasManualIgnoreTarget(key) then
                ManualTargetOrders.ignoreTargets[key] = true
            end
            if key and HasManualFocusTarget(key) then
                ManualTargetOrders.focusTarget = key
            end
        end
    end

    SyncManualPreferredTargetTags()
end

local function RegisterManualTargetOrder(caster, target, orderType)
    local targetKey = CC_Normalize(target)
    if not targetKey or Osi.Exists(targetKey) ~= 1 then
        return
    end

    if orderType == "focus" then
        local oldFocus = ManualTargetOrders.focusTarget
        if oldFocus and oldFocus ~= targetKey and Osi.Exists(oldFocus) == 1 then
            RemoveStatusIfPresent(oldFocus, "UTAC_FOCUS_TARGET")
        end

        ManualTargetOrders.focusTarget = targetKey
        ManualTargetOrders.ignoreTargets[targetKey] = nil
        RemoveStatusIfPresent(targetKey, "UTAC_IGNORE_TARGET")
        Osi.ApplyStatus(targetKey, "UTAC_FOCUS_TARGET", 6, 1)
        InfoPrint(string.format("Manual target order: global focus target=%s caster=%s", tostring(targetKey), tostring(caster)))
    elseif orderType == "ignore" then
        if ManualTargetOrders.focusTarget == targetKey then
            ManualTargetOrders.focusTarget = nil
        end

        ManualTargetOrders.ignoreTargets[targetKey] = true
        RemoveStatusIfPresent(targetKey, "UTAC_FOCUS_TARGET")
        Osi.ApplyStatus(targetKey, "UTAC_IGNORE_TARGET", 6, 1)
        InfoPrint(string.format("Manual target order: global ignore target=%s caster=%s", tostring(targetKey), tostring(caster)))
    end

    ClearTargetPriorityStatuses(targetKey)
    SyncManualPreferredTargetTags()
end

local function ClearBaseArchetypeStatuses(character)
    for status, _ in pairs(Config.StatusToArchetype) do
        RemoveStatusIfPresent(character, status)
    end
end

local function ClearArchetypeHelperStatuses(character)
    local seen = {}
    for _, data in pairs(Config.StatusToArchetype) do
        if data.Helpers then
            for _, helper in ipairs(data.Helpers) do
                if not seen[helper] then
                    seen[helper] = true
                    RemoveStatusIfPresent(character, helper)
                end
            end
        end
    end
end

local function ApplyArchetypeHelperStatuses(character)
    if not IsModEnabled() then return end
    if not GetMCM_Bool("MCM_EnableArchetypeBuffs", false) then return end

    local baseStatus = GetBaseStatusForCharacter(character)
    local data = baseStatus and Config.StatusToArchetype[baseStatus]
    if not data or not data.Helpers then
        return
    end

    for _, helper in ipairs(data.Helpers) do
        ApplyStatusIfMissing(character, helper, -1)
    end
end

local function ClearEnhancedHelperStatuses(character)
    for _, status in ipairs(ENHANCED_HELPER_STATUSES) do
        RemoveStatusIfPresent(character, status)
    end
end

local function ApplyEnhancedHelperStatuses(character)
    if not IsModEnabled() then return end
    if not GetMCM_Bool("MCM_EnableEnhancedBuffs", false) then return end

    local baseStatus = GetBaseStatusForCharacter(character)
    if baseStatus == "UTAC_BRUISER" then
        ApplyStatusIfMissing(character, "AI_BRUISER_BLOODLUST_ENHANCED", -1)
        RemoveStatusIfPresent(character, "AI_SPELLCASTER_FOCUS_ENHANCED")
    elseif baseStatus == "UTAC_SPELLCASTER" then
        ApplyStatusIfMissing(character, "AI_SPELLCASTER_FOCUS_ENHANCED", -1)
        RemoveStatusIfPresent(character, "AI_BRUISER_BLOODLUST_ENHANCED")
    else
        ClearEnhancedHelperStatuses(character)
    end
end

local function ApplyArchetypeHelperStatusesForCurrentBase(character)
    local baseStatus = GetBaseStatusForCharacter(character)
    local data = baseStatus and Config.StatusToArchetype[baseStatus]
    if not data or not data.Helpers then
        return
    end

    for _, helper in ipairs(data.Helpers) do
        ApplyStatusIfMissing(character, helper, -1)
    end
end

local function SyncArchetypeHelperToggleForCharacter(character, enabled)
    if enabled == true and IsModEnabled() then
        ApplyArchetypeHelperStatusesForCurrentBase(character)
    else
        ClearArchetypeHelperStatuses(character)
    end
end

local function SyncEnhancedHelperToggleForCharacter(character, enabled)
    if not (enabled == true and IsModEnabled()) then
        ClearEnhancedHelperStatuses(character)
        return
    end

    local baseStatus = GetBaseStatusForCharacter(character)
    if baseStatus == "UTAC_BRUISER" then
        ApplyStatusIfMissing(character, "AI_BRUISER_BLOODLUST_ENHANCED", -1)
        RemoveStatusIfPresent(character, "AI_SPELLCASTER_FOCUS_ENHANCED")
    elseif baseStatus == "UTAC_SPELLCASTER" then
        ApplyStatusIfMissing(character, "AI_SPELLCASTER_FOCUS_ENHANCED", -1)
        RemoveStatusIfPresent(character, "AI_BRUISER_BLOODLUST_ENHANCED")
    else
        ClearEnhancedHelperStatuses(character)
    end
end

local function SyncCombatBlockStatuses(character)
    if Osi.Exists(character) ~= 1 then return end

    local inCombat = Osi.IsInCombat(character) == 1
    if inCombat and GetMCM_Bool("MCM_DisableUTACDash", false) then
        ApplyStatusIfMissing(character, "UTAC_DASHING_DISABLED", -1)
    else
        RemoveStatusIfPresent(character, "UTAC_DASHING_DISABLED")
    end

    if inCombat and GetMCM_Bool("MCM_DisableUTACThrow", false) then
        ApplyStatusIfMissing(character, "UTAC_THROWING_DISABLED", -1)
    else
        RemoveStatusIfPresent(character, "UTAC_THROWING_DISABLED")
    end

    if inCombat and GetMCM_Bool("MCM_DisableUTACJump", false) then
        ApplyStatusIfMissing(character, "UTAC_JUMPING_DISABLED", -1)
    else
        RemoveStatusIfPresent(character, "UTAC_JUMPING_DISABLED")
    end

    if inCombat and GetMCM_Bool("MCM_DisableUTACShove", false) then
        ApplyStatusIfMissing(character, "UTAC_SHOVING_DISABLED", -1)
    else
        RemoveStatusIfPresent(character, "UTAC_SHOVING_DISABLED")
    end
end

local function ClearCombatControlStatuses(character)
    for _, combatStatus in pairs(Config.CombatStatusMap) do
        RemoveStatusIfPresent(character, combatStatus)
    end
    for _, npcCombatStatus in pairs(Config.CombatStatusNPCMap) do
        RemoveStatusIfPresent(character, npcCombatStatus)
    end
end

local function ReleaseUTACControl(character, ownerCharacter, reason)
    local liveCharacter, key, exists = ResolveCharacterHandle(character)
    if not key or not exists then
        return false
    end
    if RuntimeReleaseInProgress[key] then
        return false
    end

    RuntimeReleaseInProgress[key] = true
    local releaseOwner = ownerCharacter
    if releaseOwner and releaseOwner ~= "" then
        RuntimeReleaseOwner[key] = releaseOwner
    elseif RuntimeReleaseOwner[key] then
        releaseOwner = RuntimeReleaseOwner[key]
    end

    _G.UTAC_Companions[key] = nil
    _G.UTAC_BaseStatusByCharacter[key] = nil
    if _G.UTAC_CombatCache and _G.UTAC_CombatCache.charToCombat then
        _G.UTAC_CombatCache.charToCombat[key] = nil
    end

    UTACSpellPolicy.ClearForCharacter(liveCharacter, reason or "release control")
    ClearCombatControlStatuses(liveCharacter)
    ClearTemporaryHelpers(liveCharacter)
    ClearBaseArchetypeStatuses(liveCharacter)
    ClearPermanentHelpers(liveCharacter)
    ClearArchetypeHelperStatuses(liveCharacter)
    ClearEnhancedHelperStatuses(liveCharacter)
    ClearTargetPriorityStatuses(liveCharacter)
    RemovePreferredTargetTag(liveCharacter)

    for _, status in ipairs(MOD_DISABLE_RUNTIME_STATUSES) do
        RemoveStatusIfPresent(liveCharacter, status)
    end

    RemoveStatusIfPresent(liveCharacter, "UTAC_IS_CONTROLLED")
    RemoveStatusIfPresent(liveCharacter, "UTAC_TOGGLE_IS_NPC")
    RemoveStatusIfPresent(liveCharacter, "UTAC_REAPPLY_NPC_NEEDED")
    RemoveStatusIfPresent(liveCharacter, "UTAC_REAPPLY_NPC")
    UTAC_ModifySpells(liveCharacter, false)
    RemovePassiveIfPresent(liveCharacter, "UTAC_ToggleNPC")
    for _, target in ipairs(GetStatusTargetVariants(character, liveCharacter, key)) do
        if target ~= liveCharacter then
            UTACSpellPolicy.ClearForCharacter(target, reason or "release control")
            ClearCombatControlStatuses(target)
            ClearTemporaryHelpers(target)
            ClearBaseArchetypeStatuses(target)
            ClearPermanentHelpers(target)
            ClearArchetypeHelperStatuses(target)
            ClearEnhancedHelperStatuses(target)
            ClearTargetPriorityStatuses(target)
            RemovePreferredTargetTag(target)
            for _, status in ipairs(MOD_DISABLE_RUNTIME_STATUSES) do
                RemoveStatusIfPresent(target, status)
            end
            RemoveStatusIfPresent(target, "UTAC_IS_CONTROLLED")
            RemoveStatusIfPresent(target, "UTAC_TOGGLE_IS_NPC")
            RemoveStatusIfPresent(target, "UTAC_REAPPLY_NPC_NEEDED")
            RemoveStatusIfPresent(target, "UTAC_REAPPLY_NPC")
            RemovePassiveIfPresent(target, "UTAC_ToggleNPC")
        end
    end
    MakePlayerSafe(liveCharacter, releaseOwner)

    RuntimeNPCModeOwner[key] = nil
    RuntimeNPCModeTarget[key] = nil
    RuntimeNPCRestorePending[key] = nil
    RuntimeNPCModeCombatMonitor[key] = nil
    RuntimeReleaseOwner[key] = nil
    RuntimeCharacterByKey[key] = nil
    RuntimeReleaseInProgress[key] = nil
    InfoPrint(string.format("Released UTAC control for %s (%s)", tostring(key), tostring(reason or "unknown")))
    return true
end

local function GetDisabledAssignmentSnapshot()
    local vars = GetUTACModVars()
    if vars then
        if type(vars.DisabledAssignmentSnapshot) ~= "table" then
            vars.DisabledAssignmentSnapshot = {}
        end
        return vars.DisabledAssignmentSnapshot
    end

    _G.UTAC_DisabledAssignmentSnapshotFallback = _G.UTAC_DisabledAssignmentSnapshotFallback or {}
    return _G.UTAC_DisabledAssignmentSnapshotFallback
end

local function SetDisabledAssignmentSnapshot(snapshot)
    snapshot = snapshot or {}
    if SetModVar("DisabledAssignmentSnapshot", snapshot) then
        return
    end
    _G.UTAC_DisabledAssignmentSnapshotFallback = snapshot
end

local function IsDisabledAssignmentSnapshotActive()
    local vars = GetUTACModVars()
    if vars then
        return vars.DisabledAssignmentSnapshotActive == true
    end
    return _G.UTAC_DisabledAssignmentSnapshotActiveFallback == true
end

local function SetDisabledAssignmentSnapshotActive(active)
    if SetModVar("DisabledAssignmentSnapshotActive", active == true) then
        return
    end
    _G.UTAC_DisabledAssignmentSnapshotActiveFallback = active == true
end

local function MigratePersistentVarsSnapshot()
    if type(PersistentVars) ~= "table" then
        return
    end

    local oldSnapshot = PersistentVars.disabledAssignmentSnapshot
    local oldActive = PersistentVars.disabledAssignmentSnapshotActive == true
    if type(oldSnapshot) == "table" then
        local hasEntries = false
        for _ in pairs(oldSnapshot) do
            hasEntries = true
            break
        end
        if hasEntries and not IsDisabledAssignmentSnapshotActive() then
            SetDisabledAssignmentSnapshot(oldSnapshot)
            SetDisabledAssignmentSnapshotActive(oldActive)
            InfoPrint("Migrated legacy PersistentVars.disabledAssignmentSnapshot to registered ModVars.")
        end
    end

    PersistentVars.disabledAssignmentSnapshot = nil
    PersistentVars.disabledAssignmentSnapshotActive = nil
    PersistentVars.justHealed = nil
end

local function SnapshotDisabledAssignmentState(character)
    local key = CC_Normalize(character)
    if not key or Osi.Exists(key) ~= 1 then
        return nil, nil
    end

    local baseStatus = GetBaseStatusForCharacter(key)
    local wasControlled = ((_G.UTAC_Companions or {})[key] == true) or HasStatusSafe(key, "UTAC_IS_CONTROLLED")
    local wasNPCMode = HasStatusSafe(key, "UTAC_TOGGLE_IS_NPC") or HasStatusSafe(key, "UTAC_REAPPLY_NPC_NEEDED") or HasStatusSafe(key, "UTAC_REAPPLY_NPC")

    if not wasControlled and not baseStatus and not wasNPCMode then
        return key, nil
    end

    return key, {
        wasControlled = wasControlled == true,
        baseStatus = baseStatus,
        wasNPCMode = wasNPCMode == true,
    }
end

local function PersistDisabledAssignmentSnapshot(characters)
    local snapshot = {}

    for _, character in ipairs(characters or {}) do
        local key, entry = SnapshotDisabledAssignmentState(character)
        if key and entry then
            snapshot[key] = entry
        end
    end

    SetDisabledAssignmentSnapshot(snapshot)
    SetDisabledAssignmentSnapshotActive(true)
end

local function ClearDisabledAssignmentMarkers(character)
    local key = CC_Normalize(character)
    if not key or Osi.Exists(key) ~= 1 then return end

    RemoveStatusIfPresent(key, "UTAC_IS_CONTROLLED")
    ClearBaseArchetypeStatuses(key)
    RemoveStatusIfPresent(key, "UTAC_TOGGLE_IS_NPC")
    RemoveStatusIfPresent(key, "UTAC_REAPPLY_NPC_NEEDED")
    RemoveStatusIfPresent(key, "UTAC_REAPPLY_NPC")
    RemoveStatusIfPresent(key, SCULPT_SPELLS_HELPER_STATUS)
end

local function RestoreDisabledAssignmentSnapshot()
    MigratePersistentVarsSnapshot()

    if not IsDisabledAssignmentSnapshotActive() then
        return false
    end

    local restoredAny = false
    for key, entry in pairs(GetDisabledAssignmentSnapshot()) do
        if key and entry and Osi.Exists(key) == 1 then
            if entry.wasControlled then
                ApplyStatusIfMissing(key, "UTAC_IS_CONTROLLED", -1)
                restoredAny = true
            end
            if entry.baseStatus and Config.StatusToArchetype[entry.baseStatus] then
                ApplyStatusIfMissing(key, entry.baseStatus, -1)
                restoredAny = true
            end
            if entry.wasNPCMode then
                ApplyStatusIfMissing(key, "UTAC_TOGGLE_IS_NPC", -1)
                ApplyStatusIfMissing(key, "UTAC_REAPPLY_NPC_NEEDED", -1)
                restoredAny = true
            end
        end
    end

    SetDisabledAssignmentSnapshotActive(false)
    return restoredAny
end

local function DisableUTACRuntimeForCharacter(character)
    local key = CC_Normalize(character)
    if not key or Osi.Exists(key) ~= 1 then return end

    ReleaseUTACControl(key, nil, "runtime disabled")
end

local function SyncUTACSpellPolicyForCharacter(character, reason)
    if not character or character == "" then return end

    local archetype = nil
    local combatState = nil
    local casterResource = nil

    if Osi.Exists(character) == 1 and Osi.IsInCombat(character) == 1 then
        local baseStatus = GetBaseStatusForCharacter(character)
        local data = baseStatus and Config.StatusToArchetype[baseStatus] or nil
        archetype = data and data.Arch or nil

        if archetype then
            local allies, enemies
            if archetype == "Support_Healer" then
                allies, enemies = GetHealerCombatParticipants(character)
            else
                allies, enemies = GetCombatParticipants(character)
            end
            combatState = AnalyzeCombatState(character, allies or {}, enemies or {})
            casterResource = GetAvailableCasterResource(character)
        end
    end

    UTACSpellPolicy.SyncForCharacter(character, archetype, combatState, casterResource, reason)
end

local function ApplyCurrentStatefulSettingsToTrackedCharacters()
    if not IsModEnabled() then return end

    for _, key in ipairs(CollectKnownUTACCharacters(true)) do
        if Osi.Exists(key) == 1 then
            ClearArchetypeHelperStatuses(key)
            ApplyArchetypeHelperStatuses(key)
            ClearEnhancedHelperStatuses(key)
            ApplyEnhancedHelperStatuses(key)
            SyncCombatBlockStatuses(key)
            SyncShadowCurseProtectionForCharacter(key, GetMCM_Bool("MCM_EnableShadowCurseProtection", false))
            SyncSculptSpellsHelperForCharacter(key, GetMCM_Bool("MCM_EnableSculptSpellsHelper", false))
            SyncUTACSpellPolicyForCharacter(key, "stateful settings")
            ClearTargetPriorityStatuses(key)

            if Osi.IsInCombat(key) == 1 then
                ApplyCombatStatus(key)
            else
                ClearCombatControlStatuses(key)
                RemoveStatusIfPresent(key, "UTAC_HEALER_NONURGENT_OVERRIDE")
            end
        end
    end
end

local function DisableUTACRuntimeState()
    local knownCharacters = CollectKnownUTACCharacters(true)
    PersistDisabledAssignmentSnapshot(knownCharacters)

    for _, key in ipairs(knownCharacters) do
        DisableUTACRuntimeForCharacter(key)
        ClearDisabledAssignmentMarkers(key)
    end

    for _, key in ipairs(CollectCombatCacheCharacters()) do
        if Osi.Exists(key) == 1 then
            ClearTargetPriorityStatuses(key)
        end
    end

    UTACSpellPolicy.ClearAll("mod disabled")
    ClearManualTargetOrders("mod disabled")
    RuntimeJustHealed = {}
    _G.UTAC_TransformedForDialog = {}
    _G.UTAC_CombatCache = { combats = {}, charToCombat = {} }
    _G.UTAC_Companions = {}
    _G.UTAC_BaseStatusByCharacter = {}

    if type(_G.UTAC_DisableHostSpellPolicy) == "function" then
        _G.UTAC_DisableHostSpellPolicy()
    end
end

local function RebuildCompanionTrackingFromWorld()
    local host = GetHostCharacterSafe()
    if not host then
        return false, "GetHostCharacter unavailable"
    end

    local candidates = {}

    local function addCandidate(char)
        local key = CC_Normalize(char)
        if key and key ~= "" then
            candidates[key] = true
        end
    end

    for uuid, tracked in pairs(_G.UTAC_Companions or {}) do
        if tracked then addCandidate(uuid) end
    end
    for uuid, _ in pairs(_G.UTAC_BaseStatusByCharacter or {}) do
        addCandidate(uuid)
    end

    if _G.UTAC_CombatCache and _G.UTAC_CombatCache.charToCombat then
        for uuid, _ in pairs(_G.UTAC_CombatCache.charToCombat) do
            addCandidate(uuid)
        end
    end

    addCandidate(host)

    local partyRows = nil
    if Osi.DB_PartyMembers and Osi.DB_PartyMembers.Get then
        local okParty, rows = pcall(function()
            return Osi.DB_PartyMembers:Get(nil)
        end)
        if okParty then
            partyRows = rows
        end
    end
    if partyRows then
        for _, row in ipairs(partyRows) do
            addCandidate(row[1])
        end
    end

    local teamRows = nil
    if Osi.DB_PartOfTheTeam and Osi.DB_PartOfTheTeam.Get then
        local okTeam, rows = pcall(function()
            return Osi.DB_PartOfTheTeam:Get(nil)
        end)
        if okTeam then
            teamRows = rows
        end
    end
    if teamRows then
        for _, row in ipairs(teamRows) do
            addCandidate(row[1])
        end
    end

    local rebuiltCompanions = {}
    local rebuiltBaseStatus = {}
    local oldBaseStatus = _G.UTAC_BaseStatusByCharacter or {}

    for uuid, _ in pairs(candidates) do
        local okExists, existsVal = pcall(Osi.Exists, uuid)
        if okExists and existsVal == 1 then
            local baseStatus = DetectBaseArchetypeStatus(uuid)
            local okControlled, controlledVal = pcall(Osi.HasActiveStatus, uuid, "UTAC_IS_CONTROLLED")
            local isControlled = ((okControlled and controlledVal == 1) or (baseStatus ~= nil))
            if isControlled then
                rebuiltCompanions[uuid] = true
                if baseStatus and Config.StatusToArchetype[baseStatus] then
                    rebuiltBaseStatus[uuid] = baseStatus
                elseif oldBaseStatus[uuid] and Config.StatusToArchetype[oldBaseStatus[uuid]] then
                    rebuiltBaseStatus[uuid] = oldBaseStatus[uuid]
                end
            end
        end
    end

    _G.UTAC_Companions = rebuiltCompanions
    _G.UTAC_BaseStatusByCharacter = rebuiltBaseStatus

    InfoPrint(string.format(
        "SessionLoaded: rebuilt tracking from world -> companions=%d baseStatuses=%d candidates=%d",
        TableCount(rebuiltCompanions), TableCount(rebuiltBaseStatus), TableCount(candidates)
    ))
    return true
end

local function RebuildAndReinforceAfterLoad(attempt)
    attempt = attempt or 1
    local ok, successOrErr, maybeErr = pcall(RebuildCompanionTrackingFromWorld)
    if ok and successOrErr == true then
        ReinforceUTACControl()
        ApplyCurrentStatefulSettingsToTrackedCharacters()
        RepairStuckNPCModeCharacters("SessionLoaded")
        return
    end

    local err = nil
    if ok then
        err = maybeErr or successOrErr
    else
        err = successOrErr
    end
    err = tostring(err or "unknown")
    local restricted = err:find("restricted context", 1, true) ~= nil

    if restricted and Ext and Ext.Timer and Ext.Timer.WaitFor and attempt < 6 then
        local delay = 150 * attempt
        InfoPrint(string.format("SessionLoaded: restricted context during rebuild; retry in %dms (attempt %d/6).", delay, attempt + 1))
        Ext.Timer.WaitFor(delay, function()
            RebuildAndReinforceAfterLoad(attempt + 1)
        end)
        return
    end

    InfoPrint("SessionLoaded: rebuild skipped; reason=" .. err)
end

local function EnableUTACRuntimeState()
    RestoreDisabledAssignmentSnapshot()
    RefreshTrackedSpellResources()

    local ok, successOrErr, maybeErr = pcall(RebuildCompanionTrackingFromWorld)
    if ok and successOrErr == true then
        ReinforceUTACControl()
        ApplyCurrentStatefulSettingsToTrackedCharacters()
        RepairStuckNPCModeCharacters("EnableUTACRuntimeState")
        if type(_G.UTAC_ApplyHostSpellPolicy) == "function" then
            _G.UTAC_ApplyHostSpellPolicy()
        end
        return true
    end

    local err = nil
    if ok then
        err = maybeErr or successOrErr
    else
        err = successOrErr
    end
    err = tostring(err or "unknown")

    if err:find("restricted context", 1, true) ~= nil then
        if type(_G.UTAC_ApplyHostSpellPolicy) == "function" then
            _G.UTAC_ApplyHostSpellPolicy()
        end
        RebuildAndReinforceAfterLoad(1)
        return false
    end

    InfoPrint("EnableUTACRuntimeState: rebuild skipped; reason=" .. err)
    return false
end

local function RefreshTrackedCharactersForSettingsSync(source)
    local ok, successOrErr, maybeErr = pcall(RebuildCompanionTrackingFromWorld)
    if ok and successOrErr == true then
        return true
    end

    local err = nil
    if ok then
        err = maybeErr or successOrErr
    else
        err = successOrErr
    end

    InfoPrint(string.format(
        "Settings sync: tracking rebuild skipped during %s; reason=%s",
        tostring(source or "unknown"),
        tostring(err or "unknown")
    ))
    return false
end

local function ResyncTrackedCharactersForSetting(source, syncFn)
    if type(syncFn) ~= "function" then
        return
    end

    local function runPass(label)
        RefreshTrackedCharactersForSettingsSync(label)
        for _, key in ipairs(CollectKnownUTACCharacters(true)) do
            if Osi.Exists(key) == 1 then
                syncFn(key)
            end
        end
    end

    runPass(source)

    if Ext and Ext.Timer and Ext.Timer.WaitFor then
        Ext.Timer.WaitFor(75, function()
            runPass(string.format("%s:delayed", tostring(source)))
        end)
    end
end

UTACSettings.RegisterHook("MCM_CustomSpellResources", function(newValue, oldValue, context)
    RefreshTrackedSpellResources()
    InfoPrint(string.format("Settings apply: MCM_CustomSpellResources updated via %s", tostring((context and context.source) or "unknown")))
end)

UTACSettings.RegisterHook("MCM_EnableMod", function(newValue, oldValue, context)
    if newValue == oldValue then return end

    if newValue == false then
        DisableUTACRuntimeState()
        InfoPrint(string.format(
            "Settings apply: MCM_EnableMod=false via %s; cleared UTAC runtime surfaces and hid assignment markers in the persistent disable snapshot.",
            tostring((context and context.source) or "unknown")
        ))
        return
    end

    EnableUTACRuntimeState()
    InfoPrint(string.format(
        "Settings apply: MCM_EnableMod=true via %s; restored assignment markers from the persistent disable snapshot and rebuilt UTAC runtime surfaces.",
        tostring((context and context.source) or "unknown")
    ))
end)

UTACSettings.RegisterHook("MCM_EnableArchetypeBuffs", function(newValue, oldValue, context)
    if newValue == oldValue then return end

    ResyncTrackedCharactersForSetting("MCM_EnableArchetypeBuffs", function(key)
        SyncArchetypeHelperToggleForCharacter(key, newValue == true)
    end)

    InfoPrint(string.format(
        "Settings apply: MCM_EnableArchetypeBuffs=%s via %s; archetype helper statuses synced immediately.",
        tostring(newValue),
        tostring((context and context.source) or "unknown")
    ))
end)

UTACSettings.RegisterHook("MCM_EnableEnhancedBuffs", function(newValue, oldValue, context)
    if newValue == oldValue then return end

    ResyncTrackedCharactersForSetting("MCM_EnableEnhancedBuffs", function(key)
        SyncEnhancedHelperToggleForCharacter(key, newValue == true)
    end)

    InfoPrint(string.format(
        "Settings apply: MCM_EnableEnhancedBuffs=%s via %s; enhanced helper statuses synced immediately.",
        tostring(newValue),
        tostring((context and context.source) or "unknown")
    ))
end)

UTACSettings.RegisterHook("MCM_EnableShadowCurseProtection", function(newValue, oldValue, context)
    if newValue == oldValue then return end

    ResyncTrackedCharactersForSetting("MCM_EnableShadowCurseProtection", function(key)
        SyncShadowCurseProtectionForCharacter(key, newValue == true)
    end)

    InfoPrint(string.format(
        "Settings apply: MCM_EnableShadowCurseProtection=%s via %s; shadow-curse helper synced immediately.",
        tostring(newValue),
        tostring((context and context.source) or "unknown")
    ))
end)

UTACSettings.RegisterHook("MCM_EnableSculptSpellsHelper", function(newValue, oldValue, context)
    if newValue == oldValue then return end

    ResyncTrackedCharactersForSetting("MCM_EnableSculptSpellsHelper", function(key)
        SyncSculptSpellsHelperForCharacter(key, newValue == true)
    end)

    InfoPrint(string.format(
        "Settings apply: MCM_EnableSculptSpellsHelper=%s via %s; Sculpt Spells helper synced immediately.",
        tostring(newValue),
        tostring((context and context.source) or "unknown")
    ))
end)

local function RegisterCombatBlockSettingHook(settingId)
    UTACSettings.RegisterHook(settingId, function(newValue, oldValue, context)
        if newValue == oldValue then return end

        ResyncTrackedCharactersForSetting(settingId, function(key)
            SyncCombatBlockStatuses(key)
        end)

        InfoPrint(string.format(
            "Settings apply: %s=%s via %s; combat block statuses synced immediately.",
            tostring(settingId),
            tostring(newValue),
            tostring((context and context.source) or "unknown")
        ))
    end)
end

RegisterCombatBlockSettingHook("MCM_DisableUTACDash")
RegisterCombatBlockSettingHook("MCM_DisableUTACThrow")
RegisterCombatBlockSettingHook("MCM_DisableUTACJump")
RegisterCombatBlockSettingHook("MCM_DisableUTACShove")

UTACSettings.RegisterHook("MCM_AutoSummonExclusionList", function(newValue, oldValue, context)
    if newValue == oldValue then return end

    local source = string.format(
        "MCM_AutoSummonExclusionList via %s",
        tostring((context and context.source) or "unknown")
    )
    ResyncAutoSummonExclusions(source)
    ScanKnownSummonCandidates(source)

    InfoPrint("Settings apply: summon auto-apply exclusions synced.")
end)

local function RegisterSpellPolicySettingHook(settingId)
    UTACSettings.RegisterHook(settingId, function(newValue, oldValue, context)
        if newValue == oldValue then return end

        local source = string.format("%s via %s", tostring(settingId), tostring((context and context.source) or "unknown"))
        UTACSpellPolicy.RefreshSettings(source)
        ResyncTrackedCharactersForSetting(settingId, function(key)
            SyncUTACSpellPolicyForCharacter(key, source)
        end)

        InfoPrint(string.format(
            "Settings apply: %s changed via %s; spell policy/slot limiter synced.",
            tostring(settingId),
            tostring((context and context.source) or "unknown")
        ))
    end)
end

RegisterSpellPolicySettingHook("MCM_EnableUTACSpellPolicy")
RegisterSpellPolicySettingHook("MCM_UTACBlockedSpellList")
RegisterSpellPolicySettingHook("MCM_EnableSpellSlotLimiter")
RegisterSpellPolicySettingHook("MCM_SpellSlotLimiter_MinLevel")
RegisterSpellPolicySettingHook("MCM_SpellSlotLimiter_AllowEnemiesAtLeast")

UTACSpellPolicy.Initialize({
    ModuleUUID = ModuleUUID,
    Settings = UTACSettings,
    InfoPrint = InfoPrint,
    IsModEnabled = IsModEnabled,
    GetMCM_Bool = GetMCM_Bool,
    GetMCM_Number = GetMCM_Number,
    HasStatusSafe = HasStatusSafe,
    ApplyStatusIfMissing = ApplyStatusIfMissing,
    RemoveStatusIfPresent = RemoveStatusIfPresent,
    CC_Normalize = CC_Normalize,
    ResolveCharacterHandle = ResolveCharacterHandle,
    GetStatusTargetVariants = GetStatusTargetVariants,
    CollectKnownUTACCharacters = CollectKnownUTACCharacters,
})

UTACSettings.Initialize({ source = "module_load" })
RefreshTrackedSpellResources()
ResyncAutoSummonExclusions("module_load")
UTACSpellPolicy.RefreshSettings("module_load")
InfoPrint("SCRIPT LOADED. Build=" .. BUILD_TAG)

Ext.Osiris.RegisterListener("LevelGameplayStarted", 2, "after", function(_, _)
    UTACSettings.RefreshFromMCM({ source = "LevelGameplayStarted" })
    ResyncAutoSummonExclusions("LevelGameplayStarted")
    UTACSpellPolicy.RefreshSettings("LevelGameplayStarted")
    if not IsModEnabled() then
        return
    end
    EnableUTACRuntimeState()
end)

-- =================================================================================
-- ||                        EVENT LISTENERS                                      ||
-- =================================================================================

Ext.Osiris.RegisterListener("StatusApplied", 4, "after", function(character, status, causee, _)
    if not IsModEnabled() then return end
    local key = RememberCharacterHandle(character)
    if not key then return end
    local liveCharacter = RuntimeCharacterByKey[key] or character
    local data = Config.StatusToArchetype[status]
    local shouldDedupe = status == "UTAC_IS_CONTROLLED" or data ~= nil or AUTO_SUMMON_CONTROL_STATUSES[status] == true
    if shouldDedupe then
        local processedKey = tostring(key) .. "|" .. tostring(status)
        if RuntimeProcessedStatusApplied[processedKey] then
            return
        end
        RuntimeProcessedStatusApplied[processedKey] = true
    end

    if status == "UTAC_IS_CONTROLLED" then
        local ownerHandle, ownerKey, ownerExists = ResolveCharacterHandle(causee)
        if ownerKey and ownerKey ~= key and ownerExists then
            RuntimeReleaseOwner[key] = ownerHandle
        else
            RuntimeReleaseOwner[key] = nil
        end
        _G.UTAC_Companions[key] = true
        local isAutoSummon = RuntimeAutoSummonCombat[key] ~= nil
            or IsInOsirisCharacterDb(Osi.DB_PlayerSummons, key)
            or IsInOsirisCharacterDb(Osi.DB_PartyFollowers, key)
        if isAutoSummon then
            _G.UTAC_BaseStatusByCharacter[key] = _G.UTAC_BaseStatusByCharacter[key] or AUTO_SUMMON_DEFAULT_STATUS
        else
            ApplyStatusIfMissing(liveCharacter, "UTAC_ALLY", -1)
            UTAC_ModifySpells(liveCharacter, true)
            ApplyStatusIfMissing(liveCharacter, "UTAC_AVOID_DANGER", -1)
            ApplyStatusIfMissing(liveCharacter, "AI_TRAP_AWARENESS", -1)
            pcall(function()
                if Osi.HasPassive(liveCharacter, "UTAC_ToggleNPC") == 0 then
                    Osi.AddPassive(liveCharacter, "UTAC_ToggleNPC")
                    InfoPrint("Granted UTAC_ToggleNPC passive to " .. tostring(key))
                end
            end)
        end
        SyncShadowCurseProtectionForCharacter(liveCharacter, GetMCM_Bool("MCM_EnableShadowCurseProtection", false))
        SyncSculptSpellsHelperForCharacter(liveCharacter, GetMCM_Bool("MCM_EnableSculptSpellsHelper", false))
        SyncUTACSpellPolicyForCharacter(liveCharacter, "StatusApplied UTAC_IS_CONTROLLED")
    end

    if data then
        _G.UTAC_BaseStatusByCharacter[key] = status
        local isAutoSummon = RuntimeAutoSummonCombat[key] ~= nil
            or IsInOsirisCharacterDb(Osi.DB_PlayerSummons, key)
            or IsInOsirisCharacterDb(Osi.DB_PartyFollowers, key)
        if not isAutoSummon then
            ClearArchetypeHelperStatuses(liveCharacter)
            ApplyArchetypeHelperStatuses(liveCharacter)
            ClearEnhancedHelperStatuses(liveCharacter)
            ApplyEnhancedHelperStatuses(liveCharacter)
        end
        SyncShadowCurseProtectionForCharacter(liveCharacter, GetMCM_Bool("MCM_EnableShadowCurseProtection", false))
        SyncSculptSpellsHelperForCharacter(liveCharacter, GetMCM_Bool("MCM_EnableSculptSpellsHelper", false))
        SyncUTACSpellPolicyForCharacter(liveCharacter, "StatusApplied " .. tostring(status))
    end
end)

Ext.Osiris.RegisterListener("StatusRemoved", 4, "after", function(character, status, _, _)
    if not IsModEnabled() then return end
    local key = RememberCharacterHandle(character)
    if not key then return end
    RuntimeProcessedStatusApplied[tostring(key) .. "|" .. tostring(status)] = nil

    if status == "UTAC_IS_CONTROLLED" then
        ReleaseUTACControl(key, nil, "UTAC_IS_CONTROLLED removed")
        return
    end

    if status == "UTAC_FOCUS_TARGET" and ManualTargetOrders.focusTarget == key then
        ManualTargetOrders.focusTarget = nil
        SyncManualPreferredTargetTags()
    elseif status == "UTAC_IGNORE_TARGET" and ManualTargetOrders.ignoreTargets then
        ManualTargetOrders.ignoreTargets[key] = nil
    end

    if status == "UTAC_TOGGLE_IS_NPC" then
        if not RuntimeReleaseInProgress[key] and Osi.Exists(key) == 1 then
            RemoveStatusIfPresent(key, "UTAC_REAPPLY_NPC_NEEDED")
            RemoveStatusIfPresent(key, "UTAC_REAPPLY_NPC")
            ClearNPCModeCombatStatuses(character)

            if Osi.IsInCombat(character) == 1 then
                local baseStatus = GetBaseStatusForCharacter(key)
                local regularCombatStatus = baseStatus and Config.CombatStatusMap[baseStatus]
                if regularCombatStatus then
                    ApplyStatusIfMissing(character, regularCombatStatus, -1)
                    InfoPrint(string.format("NPC toggle removed in combat for %s; applied regular combat status '%s'", tostring(key), tostring(regularCombatStatus)))
                end
            end

            Osi.MakePlayer(character)
            InfoPrint("MakePlayer called for " .. tostring(character) .. " (NPC toggle removed)")
        end
    end

    if Config.IsNPCCombatStatus(status) then
        if not RuntimeReleaseInProgress[key] and Osi.Exists(key) == 1 then
            Osi.MakePlayer(character)
            InfoPrint("MakePlayer called for " .. tostring(character) .. " (NPC combat status '" .. status .. "' removed)")
        end
    end

    -- Handle revival: When DYING status is removed, restore combat status if character is still in combat
    if status == "DYING" and key and _G.UTAC_Companions[key] then
        if Osi.Exists(key) == 1 and Osi.IsInCombat(key) == 1 then
            InfoPrint("Character " .. tostring(key) .. " was revived. Restoring AI control.")
            -- Use a small delay to ensure revival state is fully settled
            Ext.Timer.WaitFor(200, function()
                if Osi.Exists(key) == 1 and Osi.IsInCombat(key) == 1 and _G.UTAC_Companions[key] then
                    ApplyCombatStatus(key)
                end
            end)
        end
    end

    local data = Config.StatusToArchetype[status]
    if data and data.Helpers then
        ClearArchetypeHelperStatuses(key)
        ClearEnhancedHelperStatuses(key)
    end
end)

Ext.Osiris.RegisterListener("CharacterMadePlayer", 1, "after", function(character)
    local key = RememberCharacterHandle(character)
    if not key then return end
    if RuntimeNPCRestorePending[key] then
        RuntimeNPCRestorePending[key] = nil
        InfoPrint("NPC restore confirmed by CharacterMadePlayer for " .. tostring(key))
    end
    if not HasStatusSafe(key, "UTAC_TOGGLE_IS_NPC") then
        RuntimeNPCModeOwner[key] = nil
        RuntimeNPCModeTarget[key] = nil
    end
end)

Ext.Osiris.RegisterListener("CharacterJoinedParty", 1, "after", function(character)
    local key = RememberCharacterHandle(character)
    if not key then return end
    if RuntimeNPCRestorePending[key] then
        RuntimeNPCRestorePending[key] = nil
        InfoPrint("NPC restore confirmed by CharacterJoinedParty for " .. tostring(key))
    end
    ScheduleAutoSummonRetry(character, "CharacterJoinedParty")
end)

Ext.Osiris.RegisterListener("CharacterLeftParty", 1, "after", function(character)
    local key = RememberCharacterHandle(character)
    if key and _G.UTAC_Companions and _G.UTAC_Companions[key] then
        InfoPrint("Tracked UTAC character left party: " .. tostring(key))
    end
end)

Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", function(character, combatGuid)
    if not IsModEnabled() then return end

    if Osi.IsSpeakerReserved(character) == 1 then
        InfoPrint("Character " .. tostring(character) .. " is in dialogue. AI control will not be applied.")
        return
    end

    TryAutoApplySummonAI(character, "EnteredCombat")

    local charKey = RememberCharacterHandle(character)
    if (charKey and _G.UTAC_Companions[charKey]) or Osi.HasActiveStatus(character, "UTAC_IS_CONTROLLED") == 1 then
        if charKey and not _G.UTAC_Companions[charKey] then
            _G.UTAC_Companions[charKey] = true
            InfoPrint("Restored missing companion: " .. tostring(charKey))
        end
        Ext.Timer.WaitFor(100, function()
            ApplyCombatStatus(character)
        end)
    end
end)

Ext.Osiris.RegisterListener("DB_PlayerSummons", 1, "after", function(character)
    if not IsModEnabled() then return end
    ScheduleAutoSummonRetry(character, "DB_PlayerSummons")
end)

Ext.Osiris.RegisterListener("DB_PartyFollowers", 1, "after", function(character)
    if not IsModEnabled() then return end
    ScheduleAutoSummonRetry(character, "DB_PartyFollowers")
end)

Ext.Osiris.RegisterListener("CombatStarted", 1, "after", function(combatGuid)
    if not IsModEnabled() then return end
    ScanKnownSummonCandidates("CombatStarted " .. tostring(combatGuid))
end)

Ext.Osiris.RegisterListener("CombatEnded", 1, "after", function(combatGuid)
    for key, trackedCombat in pairs(RuntimeAutoSummonCombat) do
        if trackedCombat == true or trackedCombat == combatGuid then
            RuntimeAutoSummonCombat[key] = nil
        end
    end
    UTACSpellPolicy.ClearNonCombat("CombatEnded " .. tostring(combatGuid))
end)

Ext.Osiris.RegisterListener("LeftCombat", 2, "after", function(character, _)
    if not IsModEnabled() then return end

    local key = RememberCharacterHandle(character)
    if not key then return end
    RuntimeAutoSummonCombat[key] = nil
    UTACSpellPolicy.ClearForCharacter(key, "LeftCombat")
    SyncCombatBlockStatuses(key)

    if _G.UTAC_Companions and _G.UTAC_Companions[key] then
        ApplyStatusIfMissing(key, "UTAC_AVOID_DANGER", -1)
        ApplyStatusIfMissing(key, "AI_TRAP_AWARENESS", -1)
        SyncShadowCurseProtectionForCharacter(key, GetMCM_Bool("MCM_EnableShadowCurseProtection", false))
        SyncSculptSpellsHelperForCharacter(key, GetMCM_Bool("MCM_EnableSculptSpellsHelper", false))
        if HasStatusSafe(key, "UTAC_TOGGLE_IS_NPC") then
            for _, npcStatus in pairs(Config.CombatStatusNPCMap) do
                if Osi.HasActiveStatus(character, npcStatus) == 1 then
                    Osi.RemoveStatus(character, npcStatus)
                end
            end
            Osi.MakePlayer(character)
            InfoPrint("Safety: MakePlayer on LeftCombat for " .. tostring(character))
        end
    end

    if (_G.UTAC_Companions and _G.UTAC_Companions[key])
        or ManualTargetOrders.focusTarget == key
        or (ManualTargetOrders.ignoreTargets and ManualTargetOrders.ignoreTargets[key] == true) then
        ClearManualTargetOrders("combat ended")
    end
end)

Ext.Osiris.RegisterListener("TurnStarted", 1, "after", function(character)
    if not IsModEnabled() then return end
    local cKey = RememberCharacterHandle(character)
    if not cKey or not _G.UTAC_Companions[cKey] or Osi.IsInCombat(character) ~= 1 then return end

    -- Safeguard: Check if character should have combat status but doesn't (e.g., lost control during dialogue or after revival)
    local hasBaseStatus = false
    local hasCombatStatus = false
    local foundBaseStatus = nil
    local isNPCMode = Osi.HasActiveStatus(character, "UTAC_TOGGLE_IS_NPC") == 1

    for baseStatus, combatStatus in pairs(Config.CombatStatusMap) do
        if HasStatusSafe(character, baseStatus) or HasStatusSafe(cKey, baseStatus) then
            hasBaseStatus = true
            foundBaseStatus = baseStatus
            local expectedCombatStatus = isNPCMode and Config.CombatStatusNPCMap[baseStatus] or combatStatus
            if HasStatusSafe(character, expectedCombatStatus) or HasStatusSafe(cKey, expectedCombatStatus) then
                hasCombatStatus = true
            else
                -- Also check if they have the wrong combat status (NPC vs regular)
                local wrongCombatStatus = isNPCMode and combatStatus or Config.CombatStatusNPCMap[baseStatus]
                if HasStatusSafe(character, wrongCombatStatus) then
                    InfoPrint("TurnStarted: Character " .. tostring(character) .. " has wrong combat status type. Removing and reapplying.")
                    Osi.RemoveStatus(character, wrongCombatStatus)
                end
            end
            break
        end
    end

    if not hasBaseStatus then
        foundBaseStatus = GetBaseStatusForCharacter(character)
        local expectedCombatStatus = foundBaseStatus and (isNPCMode and Config.CombatStatusNPCMap[foundBaseStatus] or Config.CombatStatusMap[foundBaseStatus]) or nil
        if expectedCombatStatus then
            hasBaseStatus = true
            hasCombatStatus = HasStatusSafe(character, expectedCombatStatus) or HasStatusSafe(cKey, expectedCombatStatus)
        end
    end

    if hasBaseStatus and not hasCombatStatus then
        InfoPrint(string.format("TurnStarted: Character %s has base status '%s' but missing combat status. Restoring control.", tostring(character), foundBaseStatus or "unknown"))
        ApplyCombatStatus(character)
    end

    ClearTemporaryHelpers(character)

    if Osi.HasActiveStatus(character, "UTAC_ALLY") == 0 then
        Osi.ApplyStatus(character, "UTAC_ALLY", -1, 1)
    end
    SyncSculptSpellsHelperForCharacter(character, GetMCM_Bool("MCM_EnableSculptSpellsHelper", false))

    if GetMCM_Bool("MCM_DisableUTACDash", false) then
        Osi.ApplyStatus(character, "UTAC_DASHING_DISABLED", -1, 1)
    elseif Osi.HasActiveStatus(character, "UTAC_DASHING_DISABLED") == 1 then
        Osi.RemoveStatus(character, "UTAC_DASHING_DISABLED")
    end
    if GetMCM_Bool("MCM_DisableUTACThrow", false) then
        Osi.ApplyStatus(character, "UTAC_THROWING_DISABLED", -1, 1)
    elseif Osi.HasActiveStatus(character, "UTAC_THROWING_DISABLED") == 1 then
        Osi.RemoveStatus(character, "UTAC_THROWING_DISABLED")
    end
    if GetMCM_Bool("MCM_DisableUTACJump", false) then
        Osi.ApplyStatus(character, "UTAC_JUMPING_DISABLED", -1, 1)
    elseif Osi.HasActiveStatus(character, "UTAC_JUMPING_DISABLED") == 1 then
        Osi.RemoveStatus(character, "UTAC_JUMPING_DISABLED")
    end
    if GetMCM_Bool("MCM_DisableUTACShove", false) then
        Osi.ApplyStatus(character, "UTAC_SHOVING_DISABLED", -1, 1)
    elseif Osi.HasActiveStatus(character, "UTAC_SHOVING_DISABLED") == 1 then
        Osi.RemoveStatus(character, "UTAC_SHOVING_DISABLED")
    end

    ClearEnhancedHelperStatuses(character)
    ApplyEnhancedHelperStatuses(character)

    local archetype = nil
    for status, data in pairs(Config.StatusToArchetype) do
        if Osi.HasActiveStatus(character, status) == 1 then
            archetype = data.Arch
            break
        end
    end

    if archetype then
        local allies, enemies, participantMeta
        if archetype == "Support_Healer" then
            allies, enemies, participantMeta = GetHealerCombatParticipants(character)
        else
            allies, enemies, participantMeta = GetCombatParticipants(character)
        end
        local combatState = AnalyzeCombatState(character, allies, enemies)
        local healerUrgent = nil
        if archetype == "Support_Healer" then
            healerUrgent = UpdateHealerUrgencyOverride(character, combatState)
        elseif Osi.HasActiveStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE") == 1 then
            Osi.RemoveStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE")
        end

        PruneManualTargetOrders(enemies)
        UpdateTargetPriorities(character, enemies)
        local casterResource = GetAvailableCasterResource(character)
        UTACSpellPolicy.SyncForCharacter(character, archetype, combatState, casterResource, "TurnStarted")
        ManageCombatTactics(character, archetype, combatState, casterResource)

        local resourceLabel = "none"
        if casterResource then
            if casterResource.level then
                local amount = Osi.GetActionResourceValuePersonal(character, casterResource.name, casterResource.level) or 0
                resourceLabel = string.format("%s:L%d(%d)", casterResource.name, casterResource.level, amount)
            else
                local amount = Osi.GetActionResourceValuePersonal(character, casterResource.name, 0) or 0
                resourceLabel = string.format("%s(%d)", casterResource.name, amount)
            end
        end

        local healerMode = "n/a"
        if archetype == "Support_Healer" then
            healerMode = (healerUrgent == true) and "urgent" or "nonurgent"
        end
        if archetype == "Support_Healer" then
            local function boolLabel(value)
                return value and "true" or "false"
            end
            local function numberLabel(value)
                if type(value) ~= "number" or value < 0 or value == math.huge then return "none" end
                return string.format("%.1f", value)
            end
            local meta = participantMeta or {}
            local lowestTarget = combatState.lowestHealTarget
            local lowestKey = lowestTarget and CC_Normalize(lowestTarget) or nil
            local lowestLabel = lowestKey and (RuntimeCharacterByKey[lowestKey] or lowestKey) or "none"
            local lowestHP = (type(combatState.lowestHealHP) == "number" and combatState.lowestHealHP >= 0)
                and tostring(math.floor(combatState.lowestHealHP))
                or "none"
            local nonUrgentOverride = Osi.HasActiveStatus(character, "UTAC_HEALER_NONURGENT_OVERRIDE") == 1
            InfoPrint(string.format(
                "[UTAC] HealerTriage %s mode=%s selfHP=%d triage=%d allies=%d enemies=%d nearbyAllies=%d lowAllies=%d downed=%d urgentCandidates=%d partyInCombat=%d trackedInCombat=%d dbFallback=%s dbAdded=%d supplemental=%s knownAdded=%d downedIncluded=%d downedExcluded=%d lowest=%s lowestLabel=%s lowestHP=%s lowestDist=%s selfLow=%s override=%s resourceHelpers=%s resource=%s",
                character,
                healerMode,
                math.floor(combatState.selfHP or Osi.GetHitpointsPercentage(character) or 0),
                combatState.triageThreshold or GetHealerTriageThreshold(),
                #allies,
                #enemies,
                combatState.alliesNearby or 0,
                combatState.alliesLowHP or 0,
                combatState.downedAlliesNearby or 0,
                combatState.urgentHealCandidates or 0,
                meta.partyMembersInCombat or 0,
                meta.trackedInCombat or 0,
                boolLabel(meta.dbFallbackRan),
                meta.dbFallbackAdded or 0,
                boolLabel(meta.supplementalRan),
                (meta.partySupplementAdded or 0) + (meta.trackedSupplementAdded or 0),
                meta.downedAlliesIncluded or 0,
                meta.downedAlliesExcluded or 0,
                tostring(lowestKey or "none"),
                tostring(lowestLabel),
                lowestHP,
                numberLabel(combatState.lowestHealDist),
                boolLabel(combatState.selfLowHP == true),
                boolLabel(nonUrgentOverride),
                boolLabel(GetMCM_Bool("MCM_EnableResourceHelpers", false)),
                resourceLabel
            ))
        else
            InfoPrint(string.format(
                "[UTAC] TurnStart %s archetype=%s healerMode=%s totalEnemies=%d totalAllies=%d nearbyEnemies=%d nearbyAllies=%d alliesLowHP=%d triage=%d resource=%s hp=%d%%",
                character, archetype,
                healerMode,
                #enemies, #allies,
                combatState.enemiesNearby or 0, combatState.alliesNearby or 0, combatState.alliesLowHP or 0,
                combatState.triageThreshold or GetHealerTriageThreshold(),
                resourceLabel, math.floor(Osi.GetHitpointsPercentage(character) or 0)
            ))
        end

        local trackedStatuses = {}
        local seenStatuses = {}
        local function track(statusId)
            if statusId and seenStatuses[statusId] ~= true then
                seenStatuses[statusId] = true
                table.insert(trackedStatuses, statusId)
            end
        end
        for status, data in pairs(Config.StatusToArchetype) do
            if Osi.HasActiveStatus(character, status) == 1 then track(status) end
            if data.Helpers then
                for _, helper in ipairs(data.Helpers) do
                    if Osi.HasActiveStatus(character, helper) == 1 then track(helper) end
                end
            end
        end
        for _, helper in ipairs(Config.TemporaryHelpers) do
            if Osi.HasActiveStatus(character, helper) == 1 then track(helper) end
        end
        if #trackedStatuses > 0 then
            InfoPrint("[UTAC] Active statuses -> " .. table.concat(trackedStatuses, ", "))
        else
            InfoPrint("[UTAC] Active statuses -> none")
        end
    end

    if GetMCM_Bool("MCM_EnableMovementHelpers", false) then
        local x, y, z = Osi.GetPosition(character)
        if Osi.IsInDangerousSurfaceFor(x, y, z, character, -1.0, 0) == 1 then
            Osi.ApplyStatus(character, "UTAC_SURFACE_ESCAPE", 100, 1)
        end
    end
end)

local RALLY_MAX_DISTANCE = nil

Ext.Osiris.RegisterListener("UsingSpell", 5, "before", function(caster, spellId, _, _, _)
    if not IsModEnabled() then return end
    LogThrowSpellDiagnostic(caster, spellId)
    UTACSpellPolicy.OnUsingSpell(caster, spellId)
end)

Ext.Osiris.RegisterListener("UsingSpellAtPosition", 8, "after", function(caster, x, y, z, spell, _, _, _)
    if not IsModEnabled() then return end
    if spell ~= "Shout_UTAC_Rally" then return end
    if Osi.IsInCombat and Osi.IsInCombat(caster) == 1 then return end

    local casterKey = CC_Normalize(caster)
    local FX = "VFX_Spells_Cast_Intent_Utility_TargetJump_MistyStep_BodyFX_01"
    local DELAY_MS = 120

    for uuid, isCompanion in pairs(_G.UTAC_Companions) do
        if isCompanion and Osi.Exists(uuid) == 1 and casterKey and uuid ~= casterKey then
            if RALLY_MAX_DISTANCE == nil or Osi.GetDistanceTo(uuid, caster) <= RALLY_MAX_DISTANCE then
                if Osi.PlayEffect then Osi.PlayEffect(uuid, FX, "", 1.0) end
                if Osi.PlayEffectAtPosition then
                    local cx, cy, cz = Osi.GetPosition(uuid)
                    Osi.PlayEffectAtPosition(FX, cx, cy, cz, 1.0)
                end
                Osi.TeleportTo(uuid, caster, "", 1, 1, 1, 0, 1)
                if Ext and Ext.Timer and Ext.Timer.WaitFor then
                    Ext.Timer.WaitFor(DELAY_MS, function()
                        if Osi.Exists(uuid) == 1 and Osi.PlayEffect then
                            Osi.PlayEffect(uuid, FX, "", 1.0)
                        end
                    end)
                end
            end
        end
    end
end)

Ext.Osiris.RegisterListener("UsingSpellOnTarget", 6, "after", function(caster, target, spell, _, _, _)
    if not IsModEnabled() then return end

    if spell == "Target_UTAC_FocusTarget" then
        RegisterManualTargetOrder(caster, target, "focus")
    elseif spell == "Target_UTAC_IgnoreTarget" then
        RegisterManualTargetOrder(caster, target, "ignore")
    elseif spell == "Target_UTAC_ReleaseControl" then
        ReleaseUTACControl(target, caster, "release spell")
    elseif spell == "Target_UTAC_CheckArchetype" then
        InfoPrint("========================================")
        InfoPrint("Archetype Check on: " .. tostring(target))
        InfoPrint("  - Base Game Archetype: " .. tostring(Osi.GetBaseArchetype(target)))
        local targetKey = CC_Normalize(target)
        local statusTargets = GetStatusTargetVariants(target, target, targetKey)
        local utacStatuses = {}
        local seenUtacStatuses = {}
        for status, _ in pairs(Config.StatusToArchetype) do
            if HasStatusSafe(target, status) or HasStatusSafe(targetKey, status) then
                seenUtacStatuses[status] = true
                table.insert(utacStatuses, status)
            end
        end
        local trackedBaseStatus = GetBaseStatusForCharacter(target)
        if trackedBaseStatus and not seenUtacStatuses[trackedBaseStatus] then
            seenUtacStatuses[trackedBaseStatus] = true
            table.insert(utacStatuses, trackedBaseStatus .. " (tracked)")
        end
        local combatStatuses = {}
        for _, combatStatus in pairs(Config.CombatStatusMap) do
            if HasStatusSafe(target, combatStatus) or HasStatusSafe(targetKey, combatStatus) then table.insert(combatStatuses, combatStatus) end
        end
        for _, combatStatus in pairs(Config.CombatStatusNPCMap) do
            if HasStatusSafe(target, combatStatus) or HasStatusSafe(targetKey, combatStatus) then table.insert(combatStatuses, combatStatus) end
        end
        local helperStatuses = {}
        local seenHelpers = {}
        for _, data in pairs(Config.StatusToArchetype) do
            if data.Helpers then
                for _, helper in ipairs(data.Helpers) do
                    if not seenHelpers[helper] and Osi.HasActiveStatus(target, helper) == 1 then
                        seenHelpers[helper] = true
                        table.insert(helperStatuses, helper)
                    end
                end
            end
        end
        local enhancedStatuses = {}
        for _, statusId in ipairs(ENHANCED_HELPER_STATUSES) do
            if Osi.HasActiveStatus(target, statusId) == 1 then
                table.insert(enhancedStatuses, statusId)
            end
        end
        local isControlled = Osi.HasActiveStatus(target, "UTAC_IS_CONTROLLED")
        if isControlled ~= 1 and targetKey and _G.UTAC_Companions and _G.UTAC_Companions[targetKey] then
            isControlled = 1
        end
        if isControlled ~= 1 and HasAutoSummonControlOnTargets(statusTargets) then
            isControlled = 1
        end
        InfoPrint("  - UTAC Base Statuses: " .. ((#utacStatuses > 0 and table.concat(utacStatuses, ", ")) or "none"))
        InfoPrint("  - UTAC Combat Statuses: " .. ((#combatStatuses > 0 and table.concat(combatStatuses, ", ")) or "none"))
        InfoPrint("  - Archetype Helper Statuses: " .. ((#helperStatuses > 0 and table.concat(helperStatuses, ", ")) or "none"))
        InfoPrint("  - Enhanced Helper Statuses: " .. ((#enhancedStatuses > 0 and table.concat(enhancedStatuses, ", ")) or "none"))
        InfoPrint("  - Is in Combat: " .. tostring(Osi.IsInCombat(target)))
        InfoPrint("  - Is UTAC Controlled: " .. tostring(isControlled))
        InfoPrint("========================================")
    end
end)

-- =================================================================================
-- ||                        DIALOGUE HANDLING                                    ||
-- =================================================================================

Ext.Osiris.RegisterListener("DialogStarted", 2, "after", function(dialog, instanceID)
    if not IsModEnabled() then return end
    _G.UTAC_TransformedForDialog = {}
end)

Ext.Osiris.RegisterListener("DialogActorJoined", 4, "after", function(dialog, instanceID, actor, speakerIndex)
    if not IsModEnabled() then return end
    local actorKey = CC_Normalize(actor)

    -- Only remove AI control for dialogue if character is NOT in combat
    -- If they're in combat, dialogue shouldn't interrupt AI control
    if actorKey and _G.UTAC_Companions[actorKey] and Osi.IsInCombat(actor) ~= 1 then
        local isUnderAIControl = false
        local wasNPCMode = false

        for _, combatStatus in pairs(Config.CombatStatusMap) do
            if Osi.HasActiveStatus(actor, combatStatus) == 1 then
                isUnderAIControl = true
                Osi.RemoveStatus(actor, combatStatus)
                break
            end
        end

        if not isUnderAIControl then
            for _, npcCombatStatus in pairs(Config.CombatStatusNPCMap) do
                if Osi.HasActiveStatus(actor, npcCombatStatus) == 1 then
                    isUnderAIControl = true
                    wasNPCMode = true
                    Osi.RemoveStatus(actor, npcCombatStatus)
                    Osi.MakePlayer(actor)
                    break
                end
            end
        end

        if isUnderAIControl then
            InfoPrint("Restored player control to " .. tostring(actor) .. " for dialogue." .. (wasNPCMode and " (was NPC)" or ""))
            _G.UTAC_TransformedForDialog[actorKey] = { wasNPC = wasNPCMode }
        end
    elseif actorKey and _G.UTAC_Companions[actorKey] and Osi.IsInCombat(actor) == 1 then
        InfoPrint("DialogActorJoined: Character " .. tostring(actor) .. " is in combat, preserving AI control.")
    end
end)

Ext.Osiris.RegisterListener("DialogEnded", 2, "after", function(dialog, instanceID)
    if not IsModEnabled() then return end
    for actorUUID, dialogData in pairs(_G.UTAC_TransformedForDialog) do
        if dialogData and Osi.Exists(actorUUID) == 1 then
            if Osi.IsInCombat(actorUUID) == 1 then
                InfoPrint("Re-applying AI control to " .. tostring(actorUUID) .. " after dialogue." .. (dialogData.wasNPC and " (restoring NPC mode)" or ""))
                -- Use a small delay to ensure dialogue state is fully cleared
                Ext.Timer.WaitFor(100, function()
                    ApplyCombatStatus(actorUUID)
                end)
            end
        end
    end
    _G.UTAC_TransformedForDialog = {}
end)

Ext.Osiris.RegisterListener("ShortRested", 1, "after", function(character)
    if not IsModEnabled() then return end
    ReinforceUTACControl()
    ApplyCurrentStatefulSettingsToTrackedCharacters()
end)

Ext.Events.SessionLoaded:Subscribe(function()
    MigratePersistentVarsSnapshot()
    UTACSettings.RefreshFromMCM({ source = "SessionLoaded" })
    UTACSpellPolicy.RefreshSettings("SessionLoaded")
    if not IsModEnabled() then
        InfoPrint("SessionLoaded: UTAC is disabled via MCM_EnableMod; skipping companion rebuild.")
        return
    end
    RefreshTrackedSpellResources()
    RebuildAndReinforceAfterLoad(1)
end)
