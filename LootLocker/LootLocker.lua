-- LootLocker - ESO Inventory Management Addon
-- Author: Benjamin Niccum
-- Version: 1.0.0

LootLocker = {}
LootLocker.name = "LootLocker"
LootLocker.version = "1.0.0"

-- Addon initialization
function LootLocker.OnAddOnLoaded(event, addonName)
    if addonName == LootLocker.name then
        -- Initialize addon
        LootLocker.Initialize()
        
        -- Unregister the event
        EVENT_MANAGER:UnregisterForEvent(LootLocker.name, EVENT_ADD_ON_LOADED)
    end
end

-- Initialize the addon
function LootLocker.Initialize()
    -- Initialize saved variables
    LootLocker.savedVariables = ZO_SavedVars:NewAccountWide("LootLockerSavedVars", 1, nil, {})
    
    -- Set up addon
    d("LootLocker addon loaded successfully!")
end

-- Register for addon loaded event
EVENT_MANAGER:RegisterForEvent(LootLocker.name, EVENT_ADD_ON_LOADED, LootLocker.OnAddOnLoaded)
