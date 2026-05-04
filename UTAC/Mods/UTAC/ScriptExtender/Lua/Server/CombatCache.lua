-- UTAC CombatCache.lua — Combat-state cache (CC_*) and combat participant / ally–enemy logic
local Config = Ext.Require("Server/Config.lua")

_G.UTAC_CombatCache = _G.UTAC_CombatCache or { combats = {}, charToCombat = {} }

local function InfoPrint(...)
    if _G.UTAC_InfoPrint then
        _G.UTAC_InfoPrint(...)
    end
end

-- Normalize character identifiers to UUID so cache lookups work regardless of format
local function CC_Normalize(char)
    if not char then return nil end
    local ok, uuid = pcall(Osi.GetUUID, char)
    if ok and uuid and uuid ~= "" then return uuid end
    return tostring(char)
end

local function IsCombatCharacterUnit(char, includeDowned)
    local key = CC_Normalize(char)
    if not key then return false end

    if Osi.Exists(key) ~= 1 then return false end
    if type(Osi.IsCharacter) == "function" then
        local okChar, isChar = pcall(Osi.IsCharacter, key)
        if okChar and isChar ~= 1 then return false end
    end
    if Osi.IsInCombat(key) ~= 1 then return false end

    if type(Osi.IsDead) == "function" then
        local okDead, dead = pcall(Osi.IsDead, key)
        if okDead and dead == 1 then return false end
    end
    local isDowned = false
    if type(Osi.HasActiveStatus) == "function" then
        local okDying, dying = pcall(Osi.HasActiveStatus, key, "DYING")
        isDowned = okDying and dying == 1
    end
    if type(Osi.GetHitpointsPercentage) == "function" then
        local okHP, hp = pcall(Osi.GetHitpointsPercentage, key)
        if okHP and type(hp) == "number" and hp <= 0 then isDowned = true end
    end

    if isDowned and not includeDowned then return false end
    return true
end

-- Filter to living, character-like combatants only.
local function IsActiveCombatUnit(char)
    return IsCombatCharacterUnit(char, false)
end

local function IsDownedCombatUnit(char)
    if not IsCombatCharacterUnit(char, true) then return false end
    local key = CC_Normalize(char)
    if type(Osi.HasActiveStatus) == "function" then
        local okDying, dying = pcall(Osi.HasActiveStatus, key, "DYING")
        if okDying and dying == 1 then return true end
    end
    if type(Osi.GetHitpointsPercentage) == "function" then
        local okHP, hp = pcall(Osi.GetHitpointsPercentage, key)
        if okHP and type(hp) == "number" and hp <= 0 then return true end
    end
    return false
end

local function CC_Add(char, combatId)
    if not char or not combatId then return end
    local key = CC_Normalize(char)
    if not key then return end
    local C = _G.UTAC_CombatCache
    C.combats[combatId] = C.combats[combatId] or { members = {} }
    C.combats[combatId].members[key] = true
    C.charToCombat[key] = combatId
end

local function CC_Remove(char)
    if not char then return end
    local key = CC_Normalize(char)
    if not key then return end
    local C = _G.UTAC_CombatCache
    local cid = C.charToCombat[key]
    if cid and C.combats[cid] then
        C.combats[cid].members[key] = nil
        local empty = true
        for _ in pairs(C.combats[cid].members) do empty = false; break end
        if empty then C.combats[cid] = nil end
    end
    C.charToCombat[key] = nil
end

local function CC_CombatMembersFor(char)
    local C = _G.UTAC_CombatCache
    local key = CC_Normalize(char)
    local cid = key and C.charToCombat[key]
    local out = {}
    if cid and C.combats[cid] then
        for uuid in pairs(C.combats[cid].members) do
            if IsActiveCombatUnit(uuid) then
                table.insert(out, CC_Normalize(uuid))
            else
                C.combats[cid].members[uuid] = nil
                C.charToCombat[uuid] = nil
            end
        end
    end
    return out
end

local function AddCombatId(ids, combatId)
    if combatId and combatId ~= "" then
        ids[tostring(combatId)] = true
    end
end

local function CombatIdsFor(char)
    local ids = {}
    local key = CC_Normalize(char)
    if not key then return ids end

    local cached = _G.UTAC_CombatCache and _G.UTAC_CombatCache.charToCombat and _G.UTAC_CombatCache.charToCombat[key]
    AddCombatId(ids, cached)

    if type(Osi.CombatGetGuidFor) == "function" then
        local ok, combatId = pcall(Osi.CombatGetGuidFor, key)
        if ok then
            AddCombatId(ids, combatId)
        end
    end

    local db = Osi.DB_Is_InCombat
    if db and type(db.Get) == "function" then
        local seenCandidate = {}
        for _, candidate in ipairs({ char, key }) do
            if candidate and candidate ~= "" and not seenCandidate[candidate] then
                seenCandidate[candidate] = true
                local ok, rows = pcall(function()
                    return db:Get(candidate, nil)
                end)
                if ok and rows then
                    for _, row in ipairs(rows) do
                        AddCombatId(ids, row[2])
                    end
                end
            end
        end
    end

    return ids
end

local function HasAnyCombatId(ids)
    for _ in pairs(ids or {}) do
        return true
    end
    return false
end

local function IsInRelatedCombat(character, candidate)
    local candidateKey = CC_Normalize(candidate)
    if not candidateKey or Osi.Exists(candidateKey) ~= 1 or Osi.IsInCombat(candidateKey) ~= 1 then
        return false
    end

    local sourceIds = CombatIdsFor(character)
    local candidateIds = CombatIdsFor(candidateKey)
    if HasAnyCombatId(sourceIds) and HasAnyCombatId(candidateIds) then
        for combatId in pairs(candidateIds) do
            if sourceIds[combatId] then
                return true
            end
        end
        return false
    end

    -- If Osiris has not populated combat IDs yet, fall back to "in combat".
    -- Distance and ally checks later prevent this from becoming a hard command.
    return true
end

local function AddDBCombatParticipants(character, addParticipant)
    local db = Osi.DB_Is_InCombat
    if not (db and type(db.Get) == "function") then
        return 0
    end

    -- Do not use IterateActiveObjectsInSameCombatGroup here. Its event-name
    -- parameters must resolve to compiled story symbols; Lua-only custom names
    -- produce BG3SE "Symbol not found in story" registration errors.
    local combatIds = CombatIdsFor(character)
    local hasCombatId = false
    for _ in pairs(combatIds) do
        hasCombatId = true
        break
    end
    if not hasCombatId then
        return 0
    end

    local ok, rows = pcall(function()
        return db:Get(nil, nil)
    end)
    if not ok or not rows then
        return 0
    end

    local added = 0
    for _, row in ipairs(rows) do
        local object = row[1]
        local combatId = row[2] and tostring(row[2]) or nil
        if object and combatId and combatIds[combatId] then
            if addParticipant(object) then
                added = added + 1
            end
        end
    end

    if added > 0 then
        InfoPrint(string.format("GetCombatParticipants: DB_Is_InCombat fallback added %d members for %s", added, tostring(character)))
    end
    return added
end

-- Osiris: combat tracking
Ext.Osiris.RegisterListener("EnteredCombat", 2, "after", function(char, combatGuid)
    CC_Add(char, combatGuid or ("CG_" .. tostring(char)))
end)

Ext.Osiris.RegisterListener("LeftCombat", 2, "after", function(char, _)
    CC_Remove(char)
    local charKey = CC_Normalize(char)
    if charKey and _G.UTAC_Companions and _G.UTAC_Companions[charKey] and Osi.HasActiveStatus(charKey, "UTAC_TOGGLE_IS_NPC") == 1 then
        local stillNPC = false
        for _, npcStatus in pairs(Config.CombatStatusNPCMap) do
            if Osi.HasActiveStatus(charKey, npcStatus) == 1 then
                Osi.RemoveStatus(charKey, npcStatus)
                stillNPC = true
            end
        end
        if stillNPC then
            Osi.MakePlayer(char)
            InfoPrint("Safety: MakePlayer on LeftCombat for " .. tostring(char))
        end
    end
end)

Ext.Osiris.RegisterListener("Died", 1, "after", function(char)
    CC_Remove(char)
end)

local function NewParticipantMetadata()
    return {
        cacheReturned = 0,
        dbFallbackRan = false,
        dbFallbackAdded = 0,
        supplementalRan = false,
        partyMembersInCombat = 0,
        trackedInCombat = 0,
        partySupplementAdded = 0,
        trackedSupplementAdded = 0,
        downedAlliesIncluded = 0,
        downedAlliesExcluded = 0,
    }
end

-- Cached participant lookup + ally/enemy split
local function GetCombatParticipantsInternal(character, options)
    options = options or {}
    local participants = {}
    local seen = {}
    local knownAllyCandidate = {}
    local metadata = NewParticipantMetadata()

    local function addParticipant(char, addOptions)
        addOptions = addOptions or {}
        local key = CC_Normalize(char)
        if not key or seen[key] then return false end
        local includeDowned = addOptions.includeDowned == true
        if addOptions.knownAlly then
            knownAllyCandidate[key] = true
        end
        if IsCombatCharacterUnit(key, includeDowned) then
            table.insert(participants, key)
            seen[key] = true
            if includeDowned and addOptions.knownAlly and IsDownedCombatUnit(key) then
                metadata.downedAlliesIncluded = metadata.downedAlliesIncluded + 1
            end
            return true
        end
        if addOptions.knownAlly and IsDownedCombatUnit(key) then
            metadata.downedAlliesExcluded = metadata.downedAlliesExcluded + 1
        end
        return false
    end

    local function supplementKnownAllies(includeDowned)
        metadata.supplementalRan = true

        local partyRows = Osi.DB_PartyMembers and Osi.DB_PartyMembers:Get(nil)
        if partyRows then
            for _, r in ipairs(partyRows) do
                local partyMember = r[1]
                if partyMember and IsInRelatedCombat(character, partyMember) then
                    metadata.partyMembersInCombat = metadata.partyMembersInCombat + 1
                    if addParticipant(partyMember, { knownAlly = true, includeDowned = includeDowned }) then
                        metadata.partySupplementAdded = metadata.partySupplementAdded + 1
                    end
                end
            end
        end

        if _G.UTAC_Companions then
            for uuid, tracked in pairs(_G.UTAC_Companions) do
                if tracked and IsInRelatedCombat(character, uuid) then
                    metadata.trackedInCombat = metadata.trackedInCombat + 1
                    if addParticipant(uuid, { knownAlly = true, includeDowned = includeDowned }) then
                        metadata.trackedSupplementAdded = metadata.trackedSupplementAdded + 1
                    end
                end
            end
        end
    end

    local cached = CC_CombatMembersFor(character)
    for _, uuid in ipairs(cached) do
        addParticipant(uuid)
    end
    metadata.cacheReturned = #participants
    InfoPrint(string.format("GetCombatParticipants: cache returned %d members for %s", #participants, tostring(character)))

    if Osi.IsInCombat(character) == 1 then
        -- Always include the acting character as an anchor/candidate.
        addParticipant(character)

        -- If cache is sparse (common after load/edge transitions), rebuild from party + tracked UTAC.
        local sparseParticipants = #participants <= 1
        if sparseParticipants or options.forceDBSupplement then
            metadata.dbFallbackRan = true
            metadata.dbFallbackAdded = AddDBCombatParticipants(character, addParticipant)
        end

        if sparseParticipants then
            supplementKnownAllies(false)
        elseif options.supplementKnownAllies then
            supplementKnownAllies(options.includeKnownDownedAllies == true)
        end
    end

    local allies, enemies = {}, {}
    local partyAnchors, anchorSeen = {}, {}

    local function addAnchor(char)
        local key = CC_Normalize(char)
        if not key or anchorSeen[key] then return end
        if Osi.Exists(key) == 1 then
            table.insert(partyAnchors, key)
            anchorSeen[key] = true
        end
    end

    addAnchor(character)
    local host = Osi.GetHostCharacter()
    addAnchor(host)
    local hostKey = CC_Normalize(host)

    for _, uuid in ipairs(participants) do
        if Osi.Exists(uuid) == 1 and Osi.IsPartyMember(uuid, 1) == 1 then
            addAnchor(uuid)
        end
    end

    local function isAllyToParty(target)
        if type(Osi.IsAlly) ~= "function" then return false end
        for _, anchor in ipairs(partyAnchors) do
            if Osi.IsAlly(anchor, target) == 1 then return true end
        end
        return false
    end

    local function isUTACControlled(uuid)
        local n = CC_Normalize(uuid)
        if _G.UTAC_Companions and n and _G.UTAC_Companions[n] then return true end
        local ok, val = pcall(Osi.HasActiveStatus, uuid, "UTAC_IS_CONTROLLED")
        if ok and val == 1 then return true end
        return false
    end

    local function canClassify(uuid)
        if IsActiveCombatUnit(uuid) then return true end
        if knownAllyCandidate[uuid] and IsDownedCombatUnit(uuid) then return true end
        return false
    end

    local allySet = {}
    for _, uuid in ipairs(participants) do
        if canClassify(uuid) then
            local isUTAC = isUTACControlled(uuid)
            local isParty = Osi.IsPartyMember(uuid, 1) == 1
            local isFollower = (type(Osi.IsPartyFollower) == "function") and (Osi.IsPartyFollower(uuid, 1) == 1)
            local isHost = hostKey and (CC_Normalize(uuid) == hostKey)
            if knownAllyCandidate[uuid] or isUTAC or isParty or isFollower or isHost or isAllyToParty(uuid) then
                table.insert(allies, uuid)
                allySet[uuid] = true
            end
        end
    end

    local unresolved = {}
    for _, uuid in ipairs(participants) do
        if IsActiveCombatUnit(uuid) and not allySet[uuid] then
            if type(Osi.IsEnemy) == "function" then
                local hostile = false
                for _, anchor in ipairs(partyAnchors) do
                    if Osi.IsEnemy(anchor, uuid) == 1 then
                        hostile = true
                        break
                    end
                end
                if hostile then
                    table.insert(enemies, uuid)
                else
                    table.insert(unresolved, uuid)
                end
            else
                table.insert(enemies, uuid)
            end
        end
    end

    -- Some edge states can return no explicit IsEnemy() against anchors;
    -- treat unresolved non-allies as hostiles to avoid false "enemies=0".
    if #enemies == 0 and #unresolved > 0 then
        for _, uuid in ipairs(unresolved) do
            table.insert(enemies, uuid)
        end
        InfoPrint(string.format("GetCombatParticipants: fallback -> classified %d unresolved units as enemies for %s", #unresolved, tostring(character)))
    end

    InfoPrint(string.format("GetCombatParticipants: split -> %d allies, %d enemies (participants=%d)", #allies, #enemies, #participants))
    return allies, enemies, metadata
end

local function GetCombatParticipants(character)
    return GetCombatParticipantsInternal(character, nil)
end

local function GetHealerCombatParticipants(character)
    return GetCombatParticipantsInternal(character, {
        forceDBSupplement = true,
        supplementKnownAllies = true,
        includeKnownDownedAllies = true,
    })
end

local function UTAC_DistanceToNearestEnemy(character)
    local _, enemies = GetCombatParticipants(character)
    if not enemies or #enemies == 0 then return 9999 end
    local minDistance = 9999
    for _, enemy in ipairs(enemies) do
        if Osi.Exists(enemy) == 1 then
            local dist = Osi.GetDistanceTo(character, enemy)
            if dist < minDistance then minDistance = dist end
        end
    end
    return minDistance
end

local function UTAC_DistanceToNearestAlly(character, onlyLowHP)
    local allies, _ = GetCombatParticipants(character)
    if not allies or #allies == 0 then return 9999 end
    local minDistance = 9999
    for _, ally in ipairs(allies) do
        if Osi.Exists(ally) == 1 and ally ~= character then
            local considerAlly = not onlyLowHP or Osi.GetHitpointsPercentage(ally) < 50
            if considerAlly then
                local dist = Osi.GetDistanceTo(character, ally)
                if dist < minDistance then minDistance = dist end
            end
        end
    end
    return minDistance
end

local function UTAC_HasAdvantage(character)
    if Osi.HasActiveStatus(character, "INVISIBLE") == 1
        or Osi.HasActiveStatus(character, "SG_Invisible") == 1
        or Osi.HasActiveStatus(character, "TRUE_STRIKE") == 1
        or Osi.HasActiveStatus(character, "RECKLESS_ATTACK") == 1 then
        return true
    end
    return false
end

local function HighestSpellSlotLevelAvailable(uuid)
    if type(Osi.GetActionResourceValuePersonal) ~= "function" then return 0 end
    for lvl = 9, 1, -1 do
        local val = Osi.GetActionResourceValuePersonal(uuid, "SpellSlot", lvl) or 0
        if val > 0 then return lvl end
    end
    return 0
end

return {
    CC_Normalize = CC_Normalize,
    GetCombatParticipants = GetCombatParticipants,
    GetHealerCombatParticipants = GetHealerCombatParticipants,
    UTAC_DistanceToNearestEnemy = UTAC_DistanceToNearestEnemy,
    UTAC_DistanceToNearestAlly = UTAC_DistanceToNearestAlly,
    UTAC_HasAdvantage = UTAC_HasAdvantage,
    HighestSpellSlotLevelAvailable = HighestSpellSlotLevelAvailable,
}
