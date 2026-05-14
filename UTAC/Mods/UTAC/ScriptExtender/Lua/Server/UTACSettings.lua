-- UTACSettings.lua
-- Authoritative runtime settings owner for UTAC.
local Config = Ext.Require("Server/Config.lua")

local Settings = {}

local UTAC_MOD_UUID = "300fb883-8af8-4be9-a101-171b56698dc5"
local DEFAULT_AUTO_SUMMON_EXCLUSION_LIST = {
    enabled = true,
    elements = {
        { name = "242bfc84-42ad-4719-8b34-ff854332317d", enabled = true },
        { name = "c04db4ef-3902-4ffb-9b84-e0f443b12bb3", enabled = true },
        { name = "99c92762-14b2-4660-9781-6a365f8ccebd", enabled = true },
        { name = "0d6d85ce-c985-4a1f-be91-a2aaba8e3c57", enabled = true },
        { name = "6d730ba9-0573-4351-8227-f077c0181082", enabled = true },
        { name = "b99d4d1f-c68f-4ed7-8962-7cb2d288a89b", enabled = true },
        { name = "1a8fe2e9-518c-4e64-bfef-54b1ebb5d242", enabled = true },
        { name = "58712c7a-84fa-46a7-beaf-d7e8c480203d", enabled = true },
    },
}

local DEFAULTS = {
    MCM_EnableMod = true,
    MCM_AutoApplySummons = true,
    MCM_AutoSummonExclusionList = DEFAULT_AUTO_SUMMON_EXCLUSION_LIST,
    MCM_EnableBuffHelpers = false,
    MCM_EnableMovementHelpers = false,
    MCM_EnableShadowCurseProtection = false,
    MCM_EnableSculptSpellsHelper = false,
    MCM_EnableResourceHelpers = false,
    MCM_DisableUTACDash = false,
    MCM_DisableUTACThrow = false,
    MCM_DisableUTACJump = false,
    MCM_DisableUTACShove = false,
    MCM_EnableUTACSpellPolicy = false,
    MCM_UTACBlockedSpellList = {
        enabled = true,
        elements = {
            { name = "Shout_FeatherFall", enabled = true },
            { name = "Target_FogCloud", enabled = true },
            { name = "Target_BlessingOfTheTrickster", enabled = true },
        },
    },
    MCM_EnableArchetypeBuffs = false,
    MCM_EnableEnhancedBuffs = false,
    MCM_SpellSlotRestorationChance = 0,
    MCM_ActionSurgeThreshold = 50,
    MCM_EnableSpellSlotLimiter = false,
    MCM_SpellSlotLimiter_MinLevel = 3,
    MCM_SpellSlotLimiter_AllowEnemiesAtLeast = 3,
    ConserveHighSlots = true,
    ConserveHighSlots_MinLevel = 3,
    ConserveHighSlots_AllowEnemiesAtLeast = 3,
    Healer_TriageThreshold = 60,
    MCM_CustomSpellResources = "",
    MCM_DebugLogging = false,
    ArchetypePresetIndex = 0,
}
Settings.DEFAULTS = DEFAULTS

-- Explicitly watched IDs. ArchetypePresetIndex is last so preset-linked values win.
local WATCHED_IDS = {
    "MCM_EnableMod",
    "MCM_AutoApplySummons",
    "MCM_AutoSummonExclusionList",
    "MCM_EnableBuffHelpers",
    "MCM_EnableMovementHelpers",
    "MCM_EnableShadowCurseProtection",
    "MCM_EnableSculptSpellsHelper",
    "MCM_EnableResourceHelpers",
    "MCM_DisableUTACDash",
    "MCM_DisableUTACThrow",
    "MCM_DisableUTACJump",
    "MCM_DisableUTACShove",
    "MCM_EnableUTACSpellPolicy",
    "MCM_UTACBlockedSpellList",
    "MCM_EnableArchetypeBuffs",
    "MCM_EnableEnhancedBuffs",
    "MCM_SpellSlotRestorationChance",
    "MCM_ActionSurgeThreshold",
    "MCM_EnableSpellSlotLimiter",
    "MCM_SpellSlotLimiter_MinLevel",
    "MCM_SpellSlotLimiter_AllowEnemiesAtLeast",
    "ConserveHighSlots",
    "ConserveHighSlots_MinLevel",
    "ConserveHighSlots_AllowEnemiesAtLeast",
    "Healer_TriageThreshold",
    "MCM_CustomSpellResources",
    "MCM_DebugLogging",
    "ArchetypePresetIndex",
}
Settings.WATCHED_IDS = WATCHED_IDS

-- Stateful settings need explicit apply/unapply handling because their effects persist
-- through statuses, assignments, or synced MCM/runtime state.
local STATEFUL_IDS = {
    MCM_EnableMod = true,
    MCM_AutoSummonExclusionList = true,
    MCM_EnableArchetypeBuffs = true,
    MCM_EnableEnhancedBuffs = true,
    MCM_EnableShadowCurseProtection = true,
    MCM_EnableSculptSpellsHelper = true,
    MCM_DisableUTACDash = true,
    MCM_DisableUTACThrow = true,
    MCM_DisableUTACJump = true,
    MCM_DisableUTACShove = true,
    MCM_EnableUTACSpellPolicy = true,
    MCM_UTACBlockedSpellList = true,
    MCM_EnableSpellSlotLimiter = true,
    MCM_SpellSlotLimiter_MinLevel = true,
    MCM_SpellSlotLimiter_AllowEnemiesAtLeast = true,
    MCM_CustomSpellResources = true,
    ArchetypePresetIndex = true,
}
Settings.STATEFUL_IDS = STATEFUL_IDS

local WATCHED_ID_SET = {}
for _, id in ipairs(WATCHED_IDS) do
    WATCHED_ID_SET[id] = true
end

local BOOLEAN_IDS = {
    MCM_EnableMod = true,
    MCM_AutoApplySummons = true,
    MCM_EnableBuffHelpers = true,
    MCM_EnableMovementHelpers = true,
    MCM_EnableShadowCurseProtection = true,
    MCM_EnableSculptSpellsHelper = true,
    MCM_EnableResourceHelpers = true,
    MCM_DisableUTACDash = true,
    MCM_DisableUTACThrow = true,
    MCM_DisableUTACJump = true,
    MCM_DisableUTACShove = true,
    MCM_EnableUTACSpellPolicy = true,
    MCM_EnableSpellSlotLimiter = true,
    MCM_EnableArchetypeBuffs = true,
    MCM_EnableEnhancedBuffs = true,
    ConserveHighSlots = true,
    MCM_DebugLogging = true,
}

local NUMBER_RULES = {
    MCM_SpellSlotRestorationChance = { min = 0, max = 100, integer = true },
    MCM_ActionSurgeThreshold = { min = 10, max = 100, integer = true },
    MCM_SpellSlotLimiter_MinLevel = { min = 2, max = 6, integer = true },
    MCM_SpellSlotLimiter_AllowEnemiesAtLeast = { min = 0, max = 6, integer = true },
    ConserveHighSlots_MinLevel = { min = 2, max = 6, integer = true },
    ConserveHighSlots_AllowEnemiesAtLeast = { min = 0, max = 6, integer = true },
    Healer_TriageThreshold = { min = 10, max = 100, integer = true },
    ArchetypePresetIndex = { min = 0, max = 3, integer = true },
}

local PRESET_NAMES = {
    [0] = "Default",
    [1] = "Defensive Healer",
    [2] = "Proactive Healer",
    [3] = "Battle Cleric",
}

local PRESET_NAME_TO_INDEX = {}
for idx, name in pairs(PRESET_NAMES) do
    PRESET_NAME_TO_INDEX[name] = idx
end

local RuntimeSettings = {}
local Hooks = {}
local lastAppliedPresetIndex = nil
local initialized = false
local mcmEventsSubscribed = false
local lastInvalidAutoSummonExclusionWarning = nil

local function CloneValue(value)
    if type(value) ~= "table" then
        return value
    end
    local out = {}
    for key, child in pairs(value) do
        out[key] = CloneValue(child)
    end
    return out
end

local function ValuesEqual(left, right)
    if type(left) ~= type(right) then
        return false
    end
    if type(left) ~= "table" then
        return left == right
    end
    for key, value in pairs(left) do
        if not ValuesEqual(value, right[key]) then
            return false
        end
    end
    for key, _ in pairs(right) do
        if left[key] == nil then
            return false
        end
    end
    return true
end

local function ResetSnapshot()
    for key in pairs(RuntimeSettings) do
        RuntimeSettings[key] = nil
    end
    for key, value in pairs(DEFAULTS) do
        RuntimeSettings[key] = CloneValue(value)
    end
end

ResetSnapshot()

local function SettingsLog(...)
    if RuntimeSettings.MCM_DebugLogging == true then
        if Ext and Ext.Utils and Ext.Utils.Print then
            Ext.Utils.Print("[UTAC][Settings]", ...)
        else
            print("[UTAC][Settings]", ...)
        end
    end
end

local function NormalizeBoolean(value, fallback)
    if value == nil then
        return fallback
    end
    if value == true or value == false then
        return value
    end

    local lowered = tostring(value):lower()
    if lowered == "true" or lowered == "1" then
        return true
    end
    if lowered == "false" or lowered == "0" then
        return false
    end
    return fallback
end

local function NormalizeNumber(value, fallback, rule)
    local number = tonumber(value)
    if number == nil then
        return fallback
    end
    if rule and rule.integer then
        number = math.floor(number + 0.5)
    end
    if rule and rule.min and number < rule.min then
        number = rule.min
    end
    if rule and rule.max and number > rule.max then
        number = rule.max
    end
    return number
end

local function NormalizePresetIndex(value, fallback)
    if type(value) == "string" then
        local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
        if PRESET_NAME_TO_INDEX[trimmed] ~= nil then
            return PRESET_NAME_TO_INDEX[trimmed]
        end
        value = trimmed
    end
    return NormalizeNumber(value, fallback, NUMBER_RULES.ArchetypePresetIndex)
end

local function NormalizeListV2(value, fallback, settingId)
    local source = value
    if source == nil then
        source = fallback
    end

    local out = {
        enabled = true,
        elements = {},
    }

    if type(source) == "string" then
        for entry in source:gmatch("[^,;\r\n]+") do
            local trimmed = entry:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed ~= "" then
                table.insert(out.elements, { name = trimmed, enabled = true })
            end
        end
        return out
    end

    if type(source) ~= "table" then
        return out
    end

    if type(source.settings) == "table" and settingId ~= nil and source.settings[settingId] ~= nil then
        source = source.settings[settingId]
    end
    if type(source.Default) == "table" then
        source = source.Default
    end
    if type(source) ~= "table" then
        return out
    end

    out.enabled = source.enabled ~= false
    local elements = source.elements or source.list or source.values or source.value or source
    if type(elements) ~= "table" then
        return out
    end

    for _, entry in ipairs(elements) do
        if type(entry) == "string" then
            local trimmed = entry:gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed ~= "" then
                table.insert(out.elements, { name = trimmed, enabled = true })
            end
        elseif type(entry) == "table" then
            local name = entry.name or entry.value or entry.id or entry.Name or entry.Id
            if type(name) == "string" then
                local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
                if trimmed ~= "" then
                    table.insert(out.elements, { name = trimmed, enabled = entry.enabled ~= false })
                end
            end
        end
    end

    return out
end

local function IsListV2Setting(settingId)
    return settingId == "MCM_UTACBlockedSpellList" or settingId == "MCM_AutoSummonExclusionList"
end

local function HasListV2Payload(value, settingId)
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
        return HasListV2Payload(value.Default, settingId)
    end
    if type(value.settings) == "table" and settingId ~= nil and value.settings[settingId] ~= nil then
        return HasListV2Payload(value.settings[settingId], settingId)
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

local function GetEnabledListEntries(value, fallback, settingId)
    local normalized = NormalizeListV2(value, fallback, settingId)
    local out = {}
    if normalized.enabled == false then
        return out
    end
    for _, entry in ipairs(normalized.elements or {}) do
        if entry.enabled ~= false and type(entry.name) == "string" and entry.name ~= "" then
            table.insert(out, entry.name)
        end
    end
    return out
end

local function NormalizeValue(settingId, value, fallback)
    if settingId == "ArchetypePresetIndex" then
        return NormalizePresetIndex(value, fallback)
    end
    if settingId == "MCM_UTACBlockedSpellList" or settingId == "MCM_AutoSummonExclusionList" then
        return NormalizeListV2(value, fallback, settingId)
    end
    if BOOLEAN_IDS[settingId] == true then
        return NormalizeBoolean(value, fallback)
    end
    if NUMBER_RULES[settingId] ~= nil then
        return NormalizeNumber(value, fallback, NUMBER_RULES[settingId])
    end
    if settingId == "MCM_CustomSpellResources" then
        if value == nil then
            return fallback
        end
        return tostring(value)
    end
    if value == nil then
        return fallback
    end
    return value
end

Settings.NormalizeValue = NormalizeValue

local function ReadMCM(settingId)
    local mcmApi = GetMCMAPI()
    if mcmApi then
        local ok, value = pcall(function()
            return mcmApi:GetSettingValue(settingId, UTAC_MOD_UUID)
        end)
        if ok and value ~= nil and (not IsListV2Setting(settingId) or HasListV2Payload(value, settingId)) then
            return value, true
        end
    end

    if not (MCM and type(MCM.Get) == "function") then
        return nil, false
    end

    local ok, value = pcall(function()
        return MCM.Get(settingId, UTAC_MOD_UUID)
    end)
    if ok and value ~= nil then
        return value, true
    end

    ok, value = pcall(function()
        return MCM.Get(settingId)
    end)
    if not ok then
        SettingsLog(string.format("MCM.Get failed for %s", tostring(settingId)))
        return nil, false
    end
    return value, true
end

local function SyncToMCM(settingId, value)
    if not (MCM and type(MCM.Set) == "function") then
        return false
    end

    local ok, err = pcall(function()
        MCM.Set(settingId, value, nil, false)
    end)
    if not ok then
        SettingsLog(string.format("MCM.Set failed for %s: %s", tostring(settingId), tostring(err)))
        return false
    end
    return true
end

local function FireHooks(settingId, newValue, oldValue, context)
    local list = Hooks[settingId]
    if type(list) ~= "table" then
        return
    end

    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, newValue, oldValue, context or {})
        if not ok then
            print(string.format("[UTAC][Settings] Hook failed for %s: %s", tostring(settingId), tostring(err)))
        end
    end
end

local ApplySetting

local function ApplyPresetValues(idx, options)
    local normalizedIdx = NormalizePresetIndex(idx, DEFAULTS.ArchetypePresetIndex)
    if not (options and options.forcePreset == true) and lastAppliedPresetIndex == normalizedIdx then
        return false
    end

    lastAppliedPresetIndex = normalizedIdx

    local preset = Config.PRESETS[normalizedIdx] or Config.PRESETS[DEFAULTS.ArchetypePresetIndex]
    if not preset or type(preset.values) ~= "table" then
        return false
    end

    SettingsLog(string.format("Applying preset-linked settings: %s (idx=%d)", tostring(preset.name or normalizedIdx), normalizedIdx))
    for linkedId, linkedValue in pairs(preset.values) do
        ApplySetting(linkedId, linkedValue, {
            source = string.format("%s:preset:%d", tostring(options and options.source or "settings"), normalizedIdx),
            syncToMCM = true,
        })
    end

    return true
end

function Settings.IsWatched(settingId)
    return WATCHED_ID_SET[settingId] == true
end

function Settings.Get(settingId)
    local value = RuntimeSettings[settingId]
    if value ~= nil then
        return value
    end
    return DEFAULTS[settingId]
end

function Settings.GetBool(settingId, default)
    local fallback = default
    if fallback == nil then
        fallback = DEFAULTS[settingId]
    end
    return NormalizeBoolean(Settings.Get(settingId), fallback)
end

function Settings.GetNumber(settingId, default)
    local fallback = default
    if fallback == nil then
        fallback = DEFAULTS[settingId]
    end
    return NormalizeNumber(Settings.Get(settingId), fallback, NUMBER_RULES[settingId])
end

function Settings.GetList(settingId, default)
    local fallback = default
    if fallback == nil then
        fallback = DEFAULTS[settingId]
    end
    return GetEnabledListEntries(Settings.Get(settingId), fallback, settingId)
end

local function IsUuidToken(value)
    return type(value) == "string"
        and value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") ~= nil
end

function Settings.GetAutoSummonExclusionTokens()
    local tokens = {}
    local seen = {}
    local invalidCount = 0
    local rawForWarning = ""

    for _, entry in ipairs(Settings.GetList("MCM_AutoSummonExclusionList", DEFAULTS.MCM_AutoSummonExclusionList)) do
        rawForWarning = rawForWarning .. ";" .. tostring(entry)
        local trimmed = entry:gsub("^%s+", ""):gsub("%s+$", "")
        if trimmed ~= "" then
            local lowered = trimmed:lower()
            if IsUuidToken(lowered) then
                if not seen[lowered] then
                    seen[lowered] = true
                    table.insert(tokens, lowered)
                end
            else
                invalidCount = invalidCount + 1
            end
        end
    end

    if invalidCount > 0 and lastInvalidAutoSummonExclusionWarning ~= rawForWarning then
        lastInvalidAutoSummonExclusionWarning = rawForWarning
        SettingsLog(string.format("Ignored %d non-UUID summon exclusion token(s); only root/template UUIDs are supported.", invalidCount))
    end

    return tokens
end

function Settings.GetSnapshot()
    return RuntimeSettings
end

function Settings.GetWatchedIds()
    return WATCHED_IDS
end

function Settings.RegisterHook(settingId, fn)
    if type(settingId) ~= "string" or type(fn) ~= "function" then
        return false
    end

    Hooks[settingId] = Hooks[settingId] or {}
    table.insert(Hooks[settingId], fn)
    return true
end

function Settings.ApplySetting(settingId, rawValue, options)
    if DEFAULTS[settingId] == nil then
        return nil, "unknown_setting"
    end

    local normalized = NormalizeValue(settingId, rawValue, DEFAULTS[settingId])
    local oldValue = RuntimeSettings[settingId]
    local changed = not ValuesEqual(oldValue, normalized)

    RuntimeSettings[settingId] = normalized

    if settingId == "ArchetypePresetIndex" then
        ApplyPresetValues(normalized, options)
    end

    if options and options.syncToMCM == true then
        SyncToMCM(settingId, normalized)
    end

    if changed or (options and options.forceHooks == true) then
        FireHooks(settingId, normalized, oldValue, {
            source = (options and options.source) or "apply",
            rawValue = rawValue,
            stateful = STATEFUL_IDS[settingId] == true,
        })
    end

    return normalized, oldValue, changed
end

ApplySetting = Settings.ApplySetting

function Settings.SubscribeMCMEvents()
    if mcmEventsSubscribed == true then
        return true
    end
    if not (Ext and Ext.ModEvents and Ext.ModEvents.BG3MCM) then
        return false
    end

    local bg3mcm = Ext.ModEvents.BG3MCM
    local savedEvent = bg3mcm["MCM_Setting_Saved"]
    local resetEvent = bg3mcm["MCM_Setting_Reset"]
    local subscribedAny = false

    if savedEvent then
        savedEvent:Subscribe(function(payload)
            if not payload or payload.modUUID ~= UTAC_MOD_UUID then
                return
            end

            local settingId = payload.settingId
            if WATCHED_ID_SET[settingId] ~= true then
                return
            end

            local rawValue, ok = ReadMCM(settingId)
            if not ok or rawValue == nil then
                rawValue = payload.value
            end

            Settings.ApplySetting(settingId, rawValue, {
                source = "mcm_saved",
            })
        end)
        subscribedAny = true
    end

    if resetEvent then
        resetEvent:Subscribe(function(payload)
            if not payload or payload.modUUID ~= UTAC_MOD_UUID then
                return
            end

            local settingId = payload.settingId
            if WATCHED_ID_SET[settingId] ~= true then
                return
            end

            local rawValue, ok = ReadMCM(settingId)
            if not ok or rawValue == nil then
                rawValue = DEFAULTS[settingId]
            end

            Settings.ApplySetting(settingId, rawValue, {
                source = "mcm_reset",
                forcePreset = settingId == "ArchetypePresetIndex",
            })
        end)
        subscribedAny = true
    end

    mcmEventsSubscribed = subscribedAny
    return subscribedAny
end

function Settings.RefreshFromMCM(options)
    if not initialized then
        ResetSnapshot()
        lastAppliedPresetIndex = nil
        initialized = true
    end

    Settings.SubscribeMCMEvents()

    local hasMCMGet = MCM and type(MCM.Get) == "function"
    local hasMCMAPI = GetMCMAPI() ~= nil
    if not (hasMCMGet or hasMCMAPI) then
        SettingsLog(string.format("BG3MCM unavailable during %s; keeping current runtime snapshot.", tostring(options and options.source or "refresh")))
        return false
    end

    local pulled = {}
    for _, settingId in ipairs(WATCHED_IDS) do
        local rawValue, ok = ReadMCM(settingId)
        if not ok or rawValue == nil then
            rawValue = DEFAULTS[settingId]
        end
        pulled[settingId] = rawValue
    end

    for _, settingId in ipairs(WATCHED_IDS) do
        Settings.ApplySetting(settingId, pulled[settingId], {
            source = (options and options.source) or "refresh_from_mcm",
            forcePreset = settingId == "ArchetypePresetIndex" and options and options.forcePreset == true,
        })
    end

    return true
end

function Settings.Initialize(options)
    return Settings.RefreshFromMCM({
        source = (options and options.source) or "initialize",
    })
end

return Settings
