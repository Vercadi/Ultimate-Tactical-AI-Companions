-- UTAC ArchetypeTactics.lua — ManageCombatTactics and UpdateTargetPriorities
-- deps: GetMCM_Bool, GetMCM_Number, GetHealerTriageThreshold, PostHealActive, EncourageSpellcasting,
--       GetAvailableCasterResource, HighestSpellSlotLevelAvailable, UTAC_DistanceToNearestEnemy,
--       UTAC_DistanceToNearestAlly, UTAC_HasAdvantage, NZ

return function(deps)
    local GetMCM_Bool = deps.GetMCM_Bool
    local GetMCM_Number = deps.GetMCM_Number
    local GetHealerTriageThreshold = deps.GetHealerTriageThreshold
    local PostHealActive = deps.PostHealActive
    local EncourageSpellcasting = deps.EncourageSpellcasting
    local GetAvailableCasterResource = deps.GetAvailableCasterResource
    local HighestSpellSlotLevelAvailable = deps.HighestSpellSlotLevelAvailable
    local UTAC_DistanceToNearestEnemy = deps.UTAC_DistanceToNearestEnemy
    local UTAC_DistanceToNearestAlly = deps.UTAC_DistanceToNearestAlly
    local UTAC_HasAdvantage = deps.UTAC_HasAdvantage
    local HasManualFocusTarget = deps.HasManualFocusTarget
    local HasManualIgnoreTarget = deps.HasManualIgnoreTarget
    local NZ = deps.NZ
    local function UpdateTargetPriorities(character, enemies)
        if not enemies then return end

        local hasManualFocus = false
        if type(HasManualFocusTarget) == "function" then
            for _, enemy in ipairs(enemies) do
                if enemy and Osi.Exists(enemy) == 1 and HasManualFocusTarget(enemy) then
                    hasManualFocus = true
                    break
                end
            end
        end

        for _, enemy in ipairs(enemies) do
            if enemy and Osi.Exists(enemy) == 1 then
                Osi.RemoveStatus(enemy, "UTAC_PRIORITY_LOW_HP")
                Osi.RemoveStatus(enemy, "UTAC_PRIORITY_CONCENTRATION")
                Osi.RemoveStatus(enemy, "UTAC_PRIORITY_DANGEROUS")

                local isIgnored = type(HasManualIgnoreTarget) == "function" and HasManualIgnoreTarget(enemy)
                local isFocused = type(HasManualFocusTarget) == "function" and HasManualFocusTarget(enemy)
                if not isIgnored and (not hasManualFocus or isFocused) then
                    local hp   = (type(Osi.GetHitpointsPercentage) == "function") and Osi.GetHitpointsPercentage(enemy) or nil
                    local dist = (type(Osi.GetDistanceTo) == "function") and Osi.GetDistanceTo(character, enemy) or nil
                    hp   = (type(hp)   == "number") and hp   or 100
                    dist = (type(dist) == "number") and dist or math.huge
                    if type(Osi.HasActiveStatusWithGroup) == "function" and Osi.HasActiveStatusWithGroup(enemy, "CONCENTRATION") == 1 then
                        Osi.ApplyStatus(enemy, "UTAC_PRIORITY_CONCENTRATION", 100, 1)
                    elseif hp < 25 then
                        Osi.ApplyStatus(enemy, "UTAC_PRIORITY_LOW_HP", 100, 1)
                    elseif dist <= 4 then
                        Osi.ApplyStatus(enemy, "UTAC_PRIORITY_DANGEROUS", 100, 1)
                    end
                end
            end
        end
    end

    local function ManageCombatTactics(character, archetype, combatState, casterResource)
        local function DistEnemy()
            return NZ(UTAC_DistanceToNearestEnemy(character), math.huge)
        end
        local function DistAlly()
            return NZ(UTAC_DistanceToNearestAlly(character, true), math.huge)
        end

        local conserveHigh   = GetMCM_Bool("ConserveHighSlots", true)
        local highSlotLevel  = GetMCM_Number("ConserveHighSlots_MinLevel", 3)
        local allowEnemies   = GetMCM_Number("ConserveHighSlots_AllowEnemiesAtLeast", 3)

        local function ShouldSpendHighSlotNow()
            return NZ(combatState and combatState.enemiesNearby, 0) >= allowEnemies
        end

        local function EncourageWithEconomy(isHealer)
            if not GetMCM_Bool("MCM_EnableResourceHelpers", false) then return end
            if not (casterResource and type(EncourageSpellcasting) == "function") then return end
            local isSlot = (casterResource.isSpellSlot == true)
            if conserveHigh and isSlot then
                local highest = HighestSpellSlotLevelAvailable(character)
                if highest >= highSlotLevel then
                    if not ShouldSpendHighSlotNow() then
                        return
                    end
                end
            end
            EncourageSpellcasting(character, casterResource)
        end

        if NZ(combatState and combatState.downedAlliesNearby, 0) > 0 then
            if GetMCM_Bool("MCM_EnableResourceHelpers", false) then
                Osi.ApplyStatus(character, "UTAC_ENCOURAGE_ABILITIES", 100, 1)
                Osi.ApplyStatus(character, "UTAC_ENCOURAGE_CONSUMABLES", 100, 1)
                EncourageWithEconomy(false)
            end
            return
        end

        if archetype == "Support_Healer" and NZ(combatState and combatState.alliesVeryLowHP, 0) > 0 then
            EncourageWithEconomy(true)
            return
        end

        if GetMCM_Bool("MCM_EnableBuffHelpers", false)
            and NZ(combatState and combatState.enemiesNearby, 0) > NZ(combatState and combatState.alliesNearby, 0) + 1 then
            Osi.ApplyStatus(character, "AI_HELPER_MINDSANCTUARY", 100, 1)
        end

        if NZ(combatState and combatState.alliesLowHP, 0) > 0 then
            if archetype == "Support_Healer" then
                EncourageWithEconomy(true)
            elseif archetype == "Protector" then
                if GetMCM_Bool("MCM_EnableResourceHelpers", false) then
                    Osi.ApplyStatus(character, "UTAC_ENCOURAGE_ABILITIES", 100, 1)
                end
            end
        end

        local _postHeal = PostHealActive(character)

        if GetMCM_Bool("MCM_EnableBuffHelpers", false)
            and NZ(combatState and combatState.enemiesLowHP, 0) >= 2
            and not _postHeal then
            Osi.ApplyStatus(character, "AI_HELPER_BUFF_LARGE", 100, 1)
        end

        if GetMCM_Bool("MCM_EnableBuffHelpers", false)
            and NZ(combatState and combatState.clusteredEnemies, 0) >= 3
            and archetype == "AoE_Specialist"
            and not _postHeal then
            Osi.ApplyStatus(character, "AI_HELPER_BUFF_MASSIVE", 100, 1)
            EncourageWithEconomy(false)
        end

        if GetMCM_Bool("MCM_EnableMovementHelpers", false) and archetype == "Melee_Bruiser" and DistEnemy() > 5 then
            Osi.ApplyStatus(character, "AI_HELPER_LONGJUMP", 100, 1)
        elseif GetMCM_Bool("MCM_EnableMovementHelpers", false)
            and archetype == "Melee_Skirmisher"
            and DistEnemy() < 3 then
            Osi.ApplyStatus(character, "AI_HELPER_LONGJUMP", 100, 1)
        elseif GetMCM_Bool("MCM_EnableBuffHelpers", false)
            and archetype == "Hybrid_Assassin"
            and (not UTAC_HasAdvantage(character)) then
            Osi.ApplyStatus(character, "AI_HELPER_TRUESTRIKE", 100, 1)
        elseif GetMCM_Bool("MCM_EnableMovementHelpers", false)
            and archetype == "Ranged_Marksman"
            and DistEnemy() < 8 then
            Osi.ApplyStatus(character, "AI_HELPER_LONGJUMP", 100, 1)
        elseif GetMCM_Bool("MCM_EnableMovementHelpers", false)
            and archetype == "Protector"
            and NZ(combatState and combatState.alliesLowHP, 0) > 0
            and DistAlly() > 6 then
            Osi.ApplyStatus(character, "AI_HELPER_LONGJUMP", 100, 1)
        elseif GetMCM_Bool("MCM_EnableMovementHelpers", false)
            and ((archetype == "Spellcaster" or archetype == "AoE_Specialist")
            or (archetype == "Support_Healer" and NZ(combatState and combatState.alliesLowHP, 0) == 0))
            and DistEnemy() < 4 then
            Osi.ApplyStatus(character, "AI_HELPER_LONGJUMP", 100, 1)
        elseif archetype == "General_AI" and GetMCM_Bool("MCM_EnableBuffHelpers", false) then
            local myHP = (type(Osi.GetHitpointsPercentage) == "function") and Osi.GetHitpointsPercentage(character) or 100
            if myHP < 75 then
                Osi.ApplyStatus(character, "AI_HELPER_BUFF_SMALL", 100, 1)
            end
        end

        local hasCastingResource = casterResource ~= nil

        if archetype == "Melee_Bruiser" then
            local actionSurgeThreshold = GetMCM_Number("MCM_ActionSurgeThreshold", 35)
            local myHP = (type(Osi.GetHitpointsPercentage) == "function") and Osi.GetHitpointsPercentage(character) or 100
            local asp = (type(Osi.GetActionResourceValuePersonal) == "function") and Osi.GetActionResourceValuePersonal(character, "ActionSurgePoint", 0) or 0
            if GetMCM_Bool("MCM_EnableResourceHelpers", false)
                and asp > 0 and myHP < actionSurgeThreshold then
                Osi.ApplyStatus(character, "UTAC_ENCOURAGE_ABILITIES", 100, 1)
            end
            if GetMCM_Bool("MCM_EnableResourceHelpers", false) and myHP < 50 then
                Osi.ApplyStatus(character, "UTAC_ENCOURAGE_CONSUMABLES", 100, 1)
            end
        elseif archetype == "Spellcaster" or archetype == "AoE_Specialist" then
            if hasCastingResource and GetMCM_Bool("MCM_EnableResourceHelpers", false) then
                EncourageWithEconomy(false)
                if casterResource.isSpellSlot then
                    local restorationChance = GetMCM_Number("MCM_SpellSlotRestorationChance", 0)
                    if NZ(combatState and combatState.enemiesNearby, 0) > 2
                        and Ext and Ext.Utils and Ext.Utils.Random
                        and Ext.Utils.Random(1, 100) <= restorationChance then
                        Osi.ApplyStatus(character, "UTAC_RESTORE_SPELL_SLOT", 1, 1)
                    end
                end
            elseif GetMCM_Bool("MCM_EnableResourceHelpers", false) then
                Osi.ApplyStatus(character, "UTAC_ENCOURAGE_CONSUMABLES", 100, 1)
            end
        elseif archetype == "Support_Healer" then
            if hasCastingResource and GetMCM_Bool("MCM_EnableResourceHelpers", false) then
                local triageThreshold = GetHealerTriageThreshold()
                local selfHP = (type(Osi.GetHitpointsPercentage) == "function") and Osi.GetHitpointsPercentage(character) or 100
                local hasUrgentNeed =
                    NZ(combatState and combatState.downedAlliesNearby, 0) > 0
                    or NZ(combatState and combatState.alliesLowHP, 0) > 0
                    or (type(selfHP) == "number" and selfHP <= triageThreshold)

                if hasUrgentNeed then
                    EncourageWithEconomy(true)
                end

                if casterResource.isSpellSlot then
                    local restorationChance = GetMCM_Number("MCM_SpellSlotRestorationChance", 0)
                    if hasUrgentNeed
                        and Ext and Ext.Utils and Ext.Utils.Random
                        and Ext.Utils.Random(1, 100) <= restorationChance then
                        Osi.ApplyStatus(character, "UTAC_RESTORE_SPELL_SLOT", 1, 1)
                    end
                end
            end
        elseif archetype == "Hybrid_Assassin" and GetMCM_Bool("MCM_EnableResourceHelpers", false) then
            Osi.ApplyStatus(character, "UTAC_ENCOURAGE_CONSUMABLES", 100, 1)
            Osi.ApplyStatus(character, "UTAC_ENCOURAGE_ABILITIES", 100, 1)
        end
    end

    return {
        UpdateTargetPriorities = UpdateTargetPriorities,
        ManageCombatTactics = ManageCombatTactics,
    }
end
