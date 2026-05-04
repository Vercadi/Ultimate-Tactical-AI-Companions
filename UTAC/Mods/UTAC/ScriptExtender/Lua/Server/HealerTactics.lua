-- UTAC HealerTactics.lua — Triage, revive ladder, and combat state analysis for healer/tactics
local Config = Ext.Require("Server/Config.lua")

-- Factory: pass GetHealerTriageThreshold and GetCombatParticipants from main/CombatCache
return function(GetHealerTriageThreshold, GetCombatParticipants)
    local TRIAGE_RADIUS_M = Config.TRIAGE_RADIUS_M or 20

    local function AnalyzeCombatState(character, allies, enemies)
        local function Exists(uuid)
            return uuid and Osi.Exists(uuid) == 1
        end

        local function Distance(a, b)
            if type(Osi.GetDistanceTo) ~= "function" then return math.huge end
            local ok, dist = pcall(Osi.GetDistanceTo, a, b)
            local numericDist = ok and tonumber(dist) or nil
            if numericDist then return numericDist end
            return math.huge
        end

        local function Hitpoints(uuid)
            if type(Osi.GetHitpointsPercentage) ~= "function" then return 100 end
            local ok, hp = pcall(Osi.GetHitpointsPercentage, uuid)
            local numericHP = ok and tonumber(hp) or nil
            if numericHP then return numericHP end
            return 100
        end

        local function IsDowned(uuid)
            if type(Osi.HasActiveStatus) == "function" and Osi.HasActiveStatus(uuid, "DYING") == 1 then
                return true
            end
            if type(Osi.IsDead) == "function" and Osi.IsDead(uuid) == 1 then
                return false
            end
            return Hitpoints(uuid) <= 0
        end

        local function UpdateLowestHealCandidate(combatState, target, hp, dist)
            if not target then return end
            hp = (type(hp) == "number") and hp or 100
            dist = (type(dist) == "number") and dist or math.huge
            if not combatState.lowestHealTarget
                or hp < combatState.lowestHealHP
                or (hp == combatState.lowestHealHP and dist < combatState.lowestHealDist) then
                combatState.lowestHealTarget = target
                combatState.lowestHealHP = hp
                combatState.lowestHealDist = dist
            end
        end

        local combatState = {
            enemiesNearby        = 0,
            alliesNearby         = 0,
            alliesLowHP          = 0,
            enemiesLowHP         = 0,
            clusteredEnemies     = 0,
            alliesVeryLowHP      = 0,
            nearestVeryLowDist   = -1,
            triageThreshold      = GetHealerTriageThreshold(),
            downedAlliesNearby   = 0,
            nearestDownedDist    = -1,
            selfHP               = 100,
            selfLowHP            = false,
            selfVeryLowHP        = false,
            urgentHealCandidates = 0,
            lowestHealTarget     = nil,
            lowestHealHP         = 101,
            lowestHealDist       = math.huge,
        }

        allies  = allies  or {}
        enemies = enemies or {}
        local triageThreshold = combatState.triageThreshold
        local lowHPThreshold = GetHealerTriageThreshold()

        combatState.selfHP = Hitpoints(character)
        combatState.selfLowHP = combatState.selfHP <= lowHPThreshold
        combatState.selfVeryLowHP = combatState.selfHP <= triageThreshold
        if combatState.selfLowHP then
            combatState.urgentHealCandidates = combatState.urgentHealCandidates + 1
            UpdateLowestHealCandidate(combatState, character, combatState.selfHP, 0)
        end

        for _, enemy in ipairs(enemies) do
            if Exists(enemy) and Osi.IsEnemy(character, enemy) == 1 then
                local dist = Distance(character, enemy)
                if dist <= 12 then
                    combatState.enemiesNearby = combatState.enemiesNearby + 1
                end
                local ehp = Hitpoints(enemy)
                if ehp < 30 then
                    combatState.enemiesLowHP = combatState.enemiesLowHP + 1
                end
            end
        end

        for i = 1, #enemies do
            local e1 = enemies[i]
            if Exists(e1) then
                local nearbyCount = 0
                for j = 1, #enemies do
                    if j ~= i then
                        local e2 = enemies[j]
                        if Exists(e2) then
                            local d = Distance(e1, e2)
                            if d <= 5 then
                                nearbyCount = nearbyCount + 1
                            end
                        end
                    end
                end
                if nearbyCount >= 2 then
                    combatState.clusteredEnemies = combatState.clusteredEnemies + 1
                end
            end
        end

        local veryLowCount, nearestVeryLow = 0, math.huge
        local downedCount, nearestDowned = 0, math.huge
        for _, ally in ipairs(allies) do
            if ally ~= character and Exists(ally) then
                local dist = Distance(character, ally)
                local hp = Hitpoints(ally)
                local isDowned = IsDowned(ally)
                if isDowned then
                    downedCount = downedCount + 1
                    if dist < nearestDowned then nearestDowned = dist end
                    combatState.urgentHealCandidates = combatState.urgentHealCandidates + 1
                    UpdateLowestHealCandidate(combatState, ally, hp, dist)
                end
                if dist <= TRIAGE_RADIUS_M then
                    combatState.alliesNearby = combatState.alliesNearby + 1
                    if hp <= lowHPThreshold then
                        combatState.alliesLowHP = combatState.alliesLowHP + 1
                    end
                    if hp <= triageThreshold then
                        veryLowCount = veryLowCount + 1
                        if dist < nearestVeryLow then nearestVeryLow = dist end
                    end
                    if hp <= triageThreshold and not isDowned then
                        combatState.urgentHealCandidates = combatState.urgentHealCandidates + 1
                        UpdateLowestHealCandidate(combatState, ally, hp, dist)
                    end
                end
            end
        end
        combatState.alliesVeryLowHP    = veryLowCount
        combatState.nearestVeryLowDist = (veryLowCount > 0) and nearestVeryLow or -1
        combatState.downedAlliesNearby = downedCount
        combatState.nearestDownedDist  = (downedCount > 0) and nearestDowned or -1
        if not combatState.lowestHealTarget then
            combatState.lowestHealHP = -1
            combatState.lowestHealDist = -1
        end

        return combatState
    end

    return {
        AnalyzeCombatState = AnalyzeCombatState,
    }
end
