local MODULE_UUID = "300fb883-8af8-4be9-a101-171b56698dc5"
local HOST_ONLY_SPELLS = {
    "Target_UTAC",
    "Target_UTAC_Orders",
    "Shout_UTAC_Rally",
}
local BOOTSTRAP_DEBUG = false

local function Log(msg)
    if BOOTSTRAP_DEBUG then
        print("[UTAC Bootstrap] " .. tostring(msg))
    end
end

local function LogError(msg)
    print("[UTAC Bootstrap] ERROR: " .. tostring(msg))
end

local function TryUUID(character)
    if not character then return nil end
    if type(Osi.GetUUID) == "function" then
        local ok, uuid = pcall(Osi.GetUUID, character)
        if ok and uuid and uuid ~= "" then
            return uuid
        end
    end
    return tostring(character)
end

local function IsMainPlayer(character)
    if not character then return false end
    if type(Osi.IsPartyFollower) ~= "function" then
        -- Fail-open if the API is unavailable.
        return true
    end
    return Osi.IsPartyFollower(character, 1) == 0
end

local function EnsureHostSpell(character, spell)
    if Osi.HasSpell(character, spell) == 1 then
        return
    end

    local ok, err = pcall(function()
        Osi.AddSpell(character, spell, 0, 1)
    end)
    if not ok then
        LogError(string.format("Failed to add '%s' to %s (%s)", spell, tostring(character), tostring(err)))
    else
        Log(string.format("Added '%s' to %s", spell, tostring(character)))
    end
end

local function EnsureHostSpellSet(character)
    for _, spell in ipairs(HOST_ONLY_SPELLS) do
        EnsureHostSpell(character, spell)
    end
end

local function StripHostSpellSet(character)
    if not character then
        return
    end

    for _, spell in ipairs(HOST_ONLY_SPELLS) do
        if Osi.HasSpell(character, spell) == 1 then
            pcall(function()
                Osi.RemoveSpell(character, spell, 1)
            end)
            Log(string.format("Removed '%s' from %s", spell, tostring(character)))
        end
    end
end

local function StripHostSpellsFromFollowers(host)
    if type(Osi.IsPartyFollower) ~= "function" then
        return
    end

    local hostId = TryUUID(host)
    local partyRows = Osi.DB_PartyMembers and Osi.DB_PartyMembers:Get(nil)
    if not partyRows then
        return
    end

    for _, row in ipairs(partyRows) do
        local member = row[1]
        if member then
            local memberId = TryUUID(member)
            if memberId ~= hostId and Osi.IsPartyFollower(member, 1) == 1 then
                for _, spell in ipairs(HOST_ONLY_SPELLS) do
                    if Osi.HasSpell(member, spell) == 1 then
                        pcall(function()
                            Osi.RemoveSpell(member, spell, 1)
                        end)
                        Log(string.format("Removed '%s' from follower %s", spell, tostring(member)))
                    end
                end
            end
        end
    end
end

local function ApplyHostSpellPolicy()
    local host = Osi.GetHostCharacter()
    if not host then
        LogError("No host character available; cannot enforce host spell policy.")
        return
    end

    -- Keep host-only UTAC spells off companions, then ensure host has them.
    StripHostSpellsFromFollowers(host)
    if IsMainPlayer(host) then
        EnsureHostSpellSet(host)
    else
        Log("Host is currently a follower; skipping host spell grant.")
    end
end

local function DisableHostSpellPolicy()
    local host = Osi.GetHostCharacter()
    if not host then
        LogError("No host character available; cannot disable host spell policy.")
        return
    end

    StripHostSpellSet(host)
    StripHostSpellsFromFollowers(host)
end

_G.UTAC_ApplyHostSpellPolicy = ApplyHostSpellPolicy
_G.UTAC_DisableHostSpellPolicy = DisableHostSpellPolicy

local function IsEditorMode(enabled)
    return enabled == true or enabled == 1 or tostring(enabled) == "1" or tostring(enabled) == "true"
end

_G.UTAC_OsirisListenerQueue = _G.UTAC_OsirisListenerQueue or {
    listeners = {},
    registered = false,
}

function _G.UTAC_RegisterOsirisListener(eventName, arity, timing, callback)
    local queue = _G.UTAC_OsirisListenerQueue
    if queue and queue.registered then
        Ext.Osiris.RegisterListener(eventName, arity, timing, callback)
        return
    end
    table.insert(queue.listeners, {
        eventName = eventName,
        arity = arity,
        timing = timing,
        callback = callback,
    })
end

function _G.UTAC_FlushOsirisListeners(reason)
    local queue = _G.UTAC_OsirisListenerQueue
    if not queue or queue.registered then
        return
    end
    queue.registered = true
    for _, listener in ipairs(queue.listeners) do
        Ext.Osiris.RegisterListener(listener.eventName, listener.arity, listener.timing, listener.callback)
    end
    queue.listeners = {}
    Log("Registered deferred Osiris listeners (" .. tostring(reason or "unknown") .. ")")
end

-- Register ModVars at startup so prototypes exist before loading saves.
Ext.Vars.RegisterModVariable(MODULE_UUID, "DisabledAssignmentSnapshot", { Server = true, Client = true, SyncToClient = true })
Ext.Vars.RegisterModVariable(MODULE_UUID, "DisabledAssignmentSnapshotActive", { Server = true, Client = true, SyncToClient = true })

_G.UTAC_RegisterOsirisListener("LevelGameplayStarted", 2, "after", function(_, isEditorMode)
    if IsEditorMode(isEditorMode) then
        return
    end

    ApplyHostSpellPolicy()

    -- Retry once after a short delay in case host/state was not fully ready yet.
    if Ext and Ext.Timer and Ext.Timer.WaitFor then
        Ext.Timer.WaitFor(500, function()
            ApplyHostSpellPolicy()
        end)
    end
end)

-- Load main module.
local ok, err = pcall(function()
    Ext.Require("Server/AIArchetypeManager.lua")
end)
if not ok then
    LogError("Failed to load AIArchetypeManager.lua (" .. tostring(err) .. ")")
end
