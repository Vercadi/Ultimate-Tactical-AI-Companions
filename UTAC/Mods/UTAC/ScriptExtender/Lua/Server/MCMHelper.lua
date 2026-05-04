-- UTAC/Server/MCMHelper.lua
-- Compatibility wrapper only. UTACSettings.lua is the authoritative owner.
local Settings = Ext.Require("Server/UTACSettings.lua")

local MCMHelper = {}

function MCMHelper.Get(settingId)
    return Settings.Get(settingId)
end

function MCMHelper.DebugPrint(...)
    if Settings.GetBool("MCM_DebugLogging", false) then
        print("[UTAC]", ...)
    end
end

return MCMHelper


