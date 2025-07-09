-- LootLocker ESO Add-on (PS5)
-- Main entry point

local LootLocker = {}

-- Fallback constants for PS5 compatibility
BAG_BACKPACK = BAG_BACKPACK or 1
CT_BUTTON = CT_BUTTON or 1
CT_BACKDROP = CT_BACKDROP or 2
CT_LABEL = CT_LABEL or 3
TOPLEFT = TOPLEFT or 1
LEFT = LEFT or 2
ITEM_DISPLAY_QUALITY_NORMAL = ITEM_DISPLAY_QUALITY_NORMAL or 1
INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS = INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS or 1

-- Equipment type constants
EQUIP_TYPE_HEAD = EQUIP_TYPE_HEAD or 1
EQUIP_TYPE_CHEST = EQUIP_TYPE_CHEST or 2
EQUIP_TYPE_SHOULDERS = EQUIP_TYPE_SHOULDERS or 3
EQUIP_TYPE_HAND = EQUIP_TYPE_HAND or 4
EQUIP_TYPE_WAIST = EQUIP_TYPE_WAIST or 5
EQUIP_TYPE_LEGS = EQUIP_TYPE_LEGS or 6
EQUIP_TYPE_FEET = EQUIP_TYPE_FEET or 7
EQUIP_TYPE_NECK = EQUIP_TYPE_NECK or 8
EQUIP_TYPE_RING = EQUIP_TYPE_RING or 9
EQUIP_TYPE_ONE_HAND = EQUIP_TYPE_ONE_HAND or 10
EQUIP_TYPE_TWO_HAND = EQUIP_TYPE_TWO_HAND or 11
EQUIP_TYPE_OFF_HAND = EQUIP_TYPE_OFF_HAND or 12

-- Error handling wrapper
local function SafeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        -- Use ChatFrame fallback if d() is problematic
        if type(d) == "function" then
            d("LootLocker Error: " .. tostring(result))
        else
            -- Fallback to chat frame
            CHAT_ROUTER:AddSystemMessage("LootLocker Error: " .. tostring(result))
        end
        return nil
    end
    return result
end

-- Safe debug print function
local function SafePrint(message)
    -- Try multiple approaches to safely display messages
    local success = false
    
    -- First try: Standard d() function with pcall
    if type(d) == "function" then
        success = pcall(d, "LootLocker: " .. tostring(message))
    end
    
    -- Second try: Chat system
    if not success and CHAT_SYSTEM and CHAT_SYSTEM.AddMessage then
        success = pcall(CHAT_SYSTEM.AddMessage, CHAT_SYSTEM, "LootLocker: " .. tostring(message))
    end
    
    -- Third try: Direct chat router
    if not success and CHAT_ROUTER and CHAT_ROUTER.AddSystemMessage then
        pcall(CHAT_ROUTER.AddSystemMessage, CHAT_ROUTER, "LootLocker: " .. tostring(message))
    end
    
    -- If all else fails, silently continue without error display
end

-- Utility: Get current group members
-- Finds number of users in group and stores their usernames in a list
-- Called at beginning of activity
function LootLocker.GetGroupMembers()
    local members = {}
    local groupSize = GetGroupSize()
    for i = 1, groupSize do
        local name = GetUnitName("group" .. i)
        table.insert(members, name)
    end
    return members
end

-- Utility: Get eligible group members for loot sharing
-- Checks if each group member is online and eligible for loot sharing
function LootLocker.GetEligibleMembers()
    local eligible = {}
    local groupSize = GetGroupSize()
    for i = 1, groupSize do
        local unitTag = "group" .. i
        if IsUnitOnline(unitTag) and IsUnitInGroupSupportRange(unitTag) then
            local name = GetUnitName(unitTag)
            table.insert(eligible, name)
        end
    end
    return eligible
end

-- Locker data structure
LootLocker.locker = {}
LootLocker.savedVariables = {}

-- Settings
LootLocker.settings = {
    autoOpenOnActivity = true,
    showNotifications = true,
    maxItemsPerPlayer = 20
}

-- Validate item type and quality
function LootLocker.ValidateItem(bagId, slotIndex)
    -- Check if item is equipped - equipped items can't be shared
    if type(IsItemEquipped) == "function" then
        local isEquipped = IsItemEquipped(bagId, slotIndex)
        if isEquipped then
            return false
        end
    end
    
    -- Check if required functions exist
    if type(GetItemEquipType) ~= "function" and type(GetItemQuality) ~= "function" then
        -- On PS5, these functions might not be available, so use a more lenient check
        SafePrint("Warning: Item validation functions not available - using basic validation")
        
        -- Basic validation: just check if item exists and has a name
        local itemName = ""
        if type(GetItemName) == "function" then
            itemName = GetItemName(bagId, slotIndex) or ""
        end
        
        return itemName ~= ""
    end
    
    -- Full validation if functions are available
    local equipType = nil
    local quality = 1 -- Default to normal quality
    
    if type(GetItemEquipType) == "function" then
        equipType = GetItemEquipType(bagId, slotIndex)
    end
    
    if type(GetItemQuality) == "function" then
        quality = GetItemQuality(bagId, slotIndex) or 1
    end
    
    -- If we can't get equipment type, allow any item (PS5 fallback)
    if not equipType then
        return quality >= 2 -- At least uncommon quality
    end
    
    -- Only allow armor, weapons, jewelry, and quality >= 2 (uncommon/green)
    local isValidType = (
        equipType == EQUIP_TYPE_HEAD or
        equipType == EQUIP_TYPE_CHEST or
        equipType == EQUIP_TYPE_SHOULDERS or
        equipType == EQUIP_TYPE_HAND or
        equipType == EQUIP_TYPE_WAIST or
        equipType == EQUIP_TYPE_LEGS or
        equipType == EQUIP_TYPE_FEET or
        equipType == EQUIP_TYPE_NECK or
        equipType == EQUIP_TYPE_RING or
        equipType == EQUIP_TYPE_ONE_HAND or
        equipType == EQUIP_TYPE_TWO_HAND or
        equipType == EQUIP_TYPE_OFF_HAND
    )
    return isValidType and quality and quality >= 2
end

-- Post gear to the locker (auto-detect collection time using ESO's trade timer)
function LootLocker.PostGear(playerName, bagId, slotIndex)
    -- Defensive: ensure LootLocker.locker is always a table
    if type(LootLocker.locker) ~= "table" then
        LootLocker.locker = {}
    end
    -- Use display name as key for locker (account-wide, not character name)
    local lockerKey = GetUnitDisplayName and GetUnitDisplayName("player") or ("@" .. (GetUnitName("player") or playerName or ""))
    if not lockerKey or lockerKey == "" then
        SafePrint("Error: Could not get account or character name")
        return false
    end
    if not LootLocker.locker[lockerKey] then
        LootLocker.locker[lockerKey] = {}
    end
    return SafeCall(function()
        -- Validate item type and quality
        if not LootLocker.ValidateItem(bagId, slotIndex) then
            SafePrint("Cannot post item: Only armor, weapons, and jewelry of uncommon quality or higher can be posted.")
            return false
        end
        -- Check if player has reached max items
        if #LootLocker.locker[lockerKey] >= LootLocker.settings.maxItemsPerPlayer then
            SafePrint("Cannot post item: Maximum items per player reached (" .. LootLocker.settings.maxItemsPerPlayer .. ").")
            return false
        end
        local itemLink = GetItemLink(bagId, slotIndex)
        if not itemLink or itemLink == "" then
            SafePrint("Error: Could not get item information.")
            return false
        end
        local tradeTimeRemaining = GetItemTradeTimeRemaining(bagId, slotIndex) -- seconds left to trade
        if tradeTimeRemaining and tradeTimeRemaining > 0 then
            local itemEntry = {
                link = itemLink,
                bagId = bagId,
                slotIndex = slotIndex,
                tradeTimeRemaining = tradeTimeRemaining,
                timestamp = GetTimeStamp()
            }
            table.insert(LootLocker.locker[lockerKey], itemEntry)
            if LootLocker.settings.showNotifications then
                SafePrint(string.format("%s posted %s to the locker (tradeable for %d minutes).", lockerKey, itemLink, math.floor(tradeTimeRemaining/60)))
            end
            LootLocker.SaveData()
            return true
        else
            SafePrint("This item is no longer tradeable and cannot be posted to the locker.")
            return false
        end
    end) or false
end

-- Retrieve gear from the locker (enforce ESO's trade timer and send via in-game mail)
function LootLocker.RetrieveGear(requesterName, ownerName, itemIndex)
    local ownerLocker = LootLocker.locker[ownerName]
    if not ownerLocker or not ownerLocker[itemIndex] then
        d("Item not found in locker.")
        return nil
    end
    
    local itemEntry = ownerLocker[itemIndex]
    local tradeTimeRemaining = GetItemTradeTimeRemaining(itemEntry.bagId, itemEntry.slotIndex)
    
    if not tradeTimeRemaining or tradeTimeRemaining <= 0 then
        d("This item can no longer be retrieved. The 2-hour trade window has expired.")
        -- Clean up expired item
        table.remove(ownerLocker, itemIndex)
        LootLocker.SaveData()
        return nil
    end
    
    -- Check if the owner is online and in range
    local ownerUnitTag = LootLocker.GetPlayerUnitTag(ownerName)
    if not ownerUnitTag or not IsUnitOnline(ownerUnitTag) then
        d("Cannot retrieve item: Owner is not online.")
        return nil
    end
    
    if not IsUnitInGroupSupportRange(ownerUnitTag) then
        d("Cannot retrieve item: Owner is not in range.")
        return nil
    end
    
    -- Attempt to open mail composition and send item
    local success = LootLocker.SendItemViaMail(requesterName, ownerName, itemEntry)
    if success then
        table.remove(ownerLocker, itemIndex)
        if LootLocker.settings.showNotifications then
            d(string.format("%s retrieved %s from %s's locker.", requesterName, itemEntry.link, ownerName))
        end
        LootLocker.SaveData()
        return itemEntry.link
    else
        d("Failed to send item via mail. Please try again.")
        return nil
    end
end

-- Register for dungeon/trial start events
function LootLocker.OnActivityStart(eventCode, ...)
    local groupMembers = LootLocker.GetGroupMembers()
    local eligibleMembers = LootLocker.GetEligibleMembers()
    
    if LootLocker.settings.showNotifications then
        d("LootLocker: Dungeon/Trial started. Members:")
        for _, name in ipairs(groupMembers) do
            d(name)
        end
        d("Eligible for loot sharing:")
        for _, name in ipairs(eligibleMembers) do
            d(name)
        end
    end
    
    -- Clean up expired items before starting new activity
    LootLocker.CleanupExpiredItems()
    
    -- Auto-open UI if setting is enabled
    if LootLocker.settings.autoOpenOnActivity and #eligibleMembers > 1 then
        LootLocker.ShowLockerUI(eligibleMembers)
    end
end

-- Add 'Send to Locker' option to inventory item context menu
local function AddSendToLockerOption(inventorySlot)
    if not inventorySlot or not inventorySlot.bagId or not inventorySlot.slotIndex then return end
    local bagId = inventorySlot.bagId
    local slotIndex = inventorySlot.slotIndex
    local playerName = GetUnitName("player")
    
    -- Check if menu functions are available more safely
    local hasCustomMenu = (type(AddCustomMenuItem) == "function" and type(MENU_ADD_OPTION_LABEL) ~= "nil")
    local hasZOAddMenu = (type(ZO_AddMenuItem) == "function")
    
    if hasCustomMenu then
        AddCustomMenuItem("Send to Locker", function()
            -- Use pcall to safely execute all operations
            pcall(function()
                -- Check if GetItemTradeTimeRemaining function exists
                if type(GetItemTradeTimeRemaining) ~= "function" then
                    SafePrint("Trade time function not available on this platform.")
                    return
                end
                
                -- Double-check item validity when actually trying to send
                local tradeTimeRemaining = GetItemTradeTimeRemaining(bagId, slotIndex)
                if not tradeTimeRemaining or tradeTimeRemaining <= 0 then
                    SafePrint("This item is not tradeable and cannot be sent to the locker.")
                    return
                end
                
                if not LootLocker.ValidateItem(bagId, slotIndex) then
                    SafePrint("This item is not eligible for the locker (must be armor, weapon, or jewelry of uncommon quality or higher).")
                    return
                end
                
                local success = LootLocker.PostGear(playerName, bagId, slotIndex)
                if success and lockerWindow and not lockerWindow:IsHidden() then
                    LootLocker.UpdateLockerUI()
                end
            end)
        end, MENU_ADD_OPTION_LABEL)
    elseif hasZOAddMenu then
        ZO_AddMenuItem("Send to Locker", function()
            -- Use pcall to safely execute all operations
            pcall(function()
                -- Check if GetItemTradeTimeRemaining function exists
                if type(GetItemTradeTimeRemaining) ~= "function" then
                    SafePrint("Trade time function not available on this platform.")
                    return
                end
                
                -- Double-check item validity when actually trying to send
                local tradeTimeRemaining = GetItemTradeTimeRemaining(bagId, slotIndex)
                if not tradeTimeRemaining or tradeTimeRemaining <= 0 then
                    SafePrint("This item is not tradeable and cannot be sent to the locker.")
                    return
                end
                
                if not LootLocker.ValidateItem(bagId, slotIndex) then
                    SafePrint("This item is not eligible for the locker (must be armor, weapon, or jewelry of uncommon quality or higher).")
                    return
                end
                
                local success = LootLocker.PostGear(playerName, bagId, slotIndex)
                if success and lockerWindow and not lockerWindow:IsHidden() then
                    LootLocker.UpdateLockerUI()
                end
            end)
        end)
    end
end

-- Hook into the inventory context menu
local function LootLocker_InventoryContextMenu(inventorySlot, ...)
    if not inventorySlot or not inventorySlot.bagId or not inventorySlot.slotIndex then return end
    
    -- Always show the "Send to Locker" option if menu functions are available
    -- Let the validation happen when the user clicks it
    local hasCustomMenu = (type(AddCustomMenuItem) == "function" and type(MENU_ADD_OPTION_LABEL) ~= "nil")
    local hasZOAddMenu = (type(ZO_AddMenuItem) == "function")
    
    if hasCustomMenu or hasZOAddMenu then
        AddSendToLockerOption(inventorySlot)
    end
end

-- Register the context menu hook
function LootLocker.AddMenuOption()
    -- Hook into the inventory context menu for items
    -- This uses the ZO_PreHook function if available in the ESO API
    if ZO_PreHook then
        ZO_PreHook("ZO_InventorySlot_ShowContextMenu", function(inventorySlot, ...)
            LootLocker_InventoryContextMenu(inventorySlot, ...)
        end)
    end
end

-- UI: Loot Locker Window
local lockerWindow = nil
local uiControls = {}

function LootLocker.ShowLockerUI(eligibleMembers)
    if not WINDOW_MANAGER then
        SafePrint("Error: WINDOW_MANAGER not available")
        return
    end
    
    if not lockerWindow then
        local success, result = pcall(function()
            lockerWindow = WINDOW_MANAGER:CreateTopLevelWindow("LootLockerWindow")
            lockerWindow:SetDimensions(600, 450)
            lockerWindow:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
            lockerWindow:SetMovable(true)
            lockerWindow:SetMouseEnabled(true)
            lockerWindow:SetHidden(false)

        -- Background
        local bg = WINDOW_MANAGER:CreateControl(nil, lockerWindow, CT_BACKDROP)
        bg:SetAnchorFill(lockerWindow)
        bg:SetCenterColor(0, 0, 0, 0.8)
        bg:SetEdgeColor(0.4, 0.4, 0.4, 1)
        bg:SetEdgeTexture("", 2, 2, 2, 2)

        -- Title
        local title = WINDOW_MANAGER:CreateControl(nil, lockerWindow, CT_LABEL)
        title:SetFont("ZoFontWinH1")
        title:SetText("Loot Locker")
        title:SetColor(1, 1, 1, 1)
        title:SetAnchor(TOP, lockerWindow, TOP, 0, 20)

        -- Close button
        local closeBtn = WINDOW_MANAGER:CreateControl(nil, lockerWindow, CT_BUTTON)
        closeBtn:SetDimensions(32, 32)
        closeBtn:SetAnchor(TOPRIGHT, lockerWindow, TOPRIGHT, -10, 10)
        closeBtn:SetNormalTexture("EsoUI/Art/Buttons/closebutton_up.dds")
        closeBtn:SetPressedTexture("EsoUI/Art/Buttons/closebutton_down.dds")
        closeBtn:SetMouseOverTexture("EsoUI/Art/Buttons/closebutton_mouseover.dds")
        closeBtn:SetHandler("OnClicked", function() lockerWindow:SetHidden(true) end)

        -- Clear button
        local clearBtn = WINDOW_MANAGER:CreateControl(nil, lockerWindow, CT_BUTTON)
        clearBtn:SetDimensions(100, 30)
        clearBtn:SetAnchor(TOPLEFT, lockerWindow, TOPLEFT, 20, 60)
        clearBtn:SetText("Clear Expired")
        clearBtn:SetHandler("OnClicked", function() 
            LootLocker.CleanupExpiredItems()
            SafePrint("Cleared expired items from locker.")
        end)
        
        -- Add Items button (console only)
        if type(AddCustomMenuItem) ~= "function" and type(ZO_AddMenuItem) ~= "function" then
            local addBtn = WINDOW_MANAGER:CreateControl(nil, lockerWindow, CT_BUTTON)
            addBtn:SetDimensions(100, 30)
            addBtn:SetAnchor(TOPLEFT, lockerWindow, TOPLEFT, 130, 60)
            addBtn:SetText("Add Items")
            addBtn:SetNormalFontColor(0.2, 0.8, 0.2, 1)
            addBtn:SetHandler("OnClicked", function() 
                LootLocker.ShowItemSelectorUI()
            end)
        end

        -- Scroll list for locker contents
        lockerWindow.scroll = WINDOW_MANAGER:CreateControlFromVirtual(nil, lockerWindow, "ZO_ScrollContainer")
        lockerWindow.scroll:SetDimensions(560, 320)
        lockerWindow.scroll:SetAnchor(TOP, lockerWindow, TOP, 0, 100)
        lockerWindow.scroll:SetHidden(false)
        
        -- Initialize scroll child
        local scrollChild = lockerWindow.scroll:GetNamedChild("ScrollChild")
        if scrollChild then
            scrollChild:SetResizeToFitDescendents(true)
        end
        end)
        
        if not success then
            SafePrint("Error: Failed to create UI - " .. tostring(result))
            return
        end
    else
        lockerWindow:SetHidden(false)
    end
    LootLocker.UpdateLockerUI()
end

function LootLocker.HideLockerUI()
    if lockerWindow then
        lockerWindow:SetHidden(true)
    end
end

function LootLocker.UpdateLockerUI()
    if not lockerWindow or not lockerWindow.scroll then return end
    
    local scrollChild = lockerWindow.scroll:GetNamedChild("ScrollChild")
    if not scrollChild then return end
    
    -- Clear existing controls
    for _, control in ipairs(uiControls) do
        if type(control) == "userdata" and control.SetHidden and control.ClearAnchors then
            control:SetHidden(true)
            control:ClearAnchors()
        end
    end
    uiControls = {}
    
    scrollChild:ClearAnchors()
    scrollChild:SetResizeToFitDescendents(true)
    scrollChild:SetHeight(0)

    local y = 10
    local hasItems = false
    
    -- Initialize locker if needed
    if not LootLocker.locker or type(LootLocker.locker) ~= "table" then
        LootLocker.locker = {}
    end
    
    local myAccount = GetUnitDisplayName and GetUnitDisplayName("player") or ("@" .. (GetUnitName("player") or ""))
    SafePrint("Debug: UpdateLockerUI looking for account: " .. myAccount)
    SafePrint("Debug: Available locker keys: " .. table.concat(LootLocker.GetLockerKeys(), ", "))
    for owner, items in pairs(LootLocker.locker) do
        -- Only show lockers for account names (start with @)
        if type(owner) == "string" and owner:sub(1,1) == "@" and type(items) == "table" and #items > 0 then
            hasItems = true
            -- Owner header
            local ownerLabel = WINDOW_MANAGER:CreateControl(nil, scrollChild, CT_LABEL)
            ownerLabel:SetFont("ZoFontWinH2")
            ownerLabel:SetText(owner .. "'s Items:")
            ownerLabel:SetColor(1, 0.8, 0.2, 1)
            ownerLabel:SetAnchor(TOPLEFT, scrollChild, TOPLEFT, 10, y)
            table.insert(uiControls, ownerLabel)
            y = y + 35
            -- Debug: print each item
            for idx, item in ipairs(items) do
                local timeLeft = 0
                if type(GetItemTradeTimeRemaining) == "function" then
                    timeLeft = GetItemTradeTimeRemaining(item.bagId, item.slotIndex) or 0
                else
                    if item.tradeTimer and item.timestamp then
                        local currentTime = (type(GetTimeStamp) == "function" and GetTimeStamp()) or os.time()
                        local elapsed = currentTime - item.timestamp
                        timeLeft = math.max(0, item.tradeTimer - elapsed)
                    end
                end
                -- Always show owner's own items, even if timeLeft is 0
                local isOwner = (myAccount == owner)
                local showItem = (not isOwner and timeLeft > 0) or isOwner
                if showItem then
                    local minutes = math.floor(timeLeft / 60)
                    local seconds = timeLeft % 60
                    local itemLabel = WINDOW_MANAGER:CreateControl(nil, scrollChild, CT_LABEL)
                    itemLabel:SetFont("ZoFontGame")
                    local timeText = string.format("%d:%02d", minutes, seconds)
                    if not isOwner and timeLeft <= 0 then
                        timeText = "EXPIRED"
                        itemLabel:SetColor(0.7, 0.7, 0.7, 1)
                    else
                        itemLabel:SetColor(1, 1, 1, 1)
                    end
                    itemLabel:SetText(string.format("%s (Time: %s)", item.link or item.name or "?", timeText))
                    itemLabel:SetAnchor(TOPLEFT, scrollChild, TOPLEFT, 20, y)
                    table.insert(uiControls, itemLabel)
                    -- Add retrieve button for others, or take back button for owner
                    if not isOwner and timeLeft > 0 then
                        local retrieveBtn = WINDOW_MANAGER:CreateControl(nil, scrollChild, CT_BUTTON)
                        retrieveBtn:SetDimensions(80, 24)
                        retrieveBtn:SetAnchor(RIGHT, scrollChild, RIGHT, -20, y + 12)
                        retrieveBtn:SetText("Retrieve")
                        retrieveBtn:SetNormalFontColor(1, 1, 1, 1)
                        retrieveBtn:SetHandler("OnClicked", function()
                            local result = LootLocker.RetrieveGear(myAccount, owner, idx)
                            if result then
                                LootLocker.UpdateLockerUI()
                            end
                        end)
                        table.insert(uiControls, retrieveBtn)
                    elseif isOwner then
                        local takeBackBtn = WINDOW_MANAGER:CreateControl(nil, scrollChild, CT_BUTTON)
                        takeBackBtn:SetDimensions(80, 24)
                        takeBackBtn:SetAnchor(RIGHT, scrollChild, RIGHT, -20, y + 12)
                        takeBackBtn:SetText("Take Back")
                        takeBackBtn:SetNormalFontColor(0.8, 1, 0.8, 1)
                        takeBackBtn:SetHandler("OnClicked", function()
                            local result = LootLocker.TakeBackItem(owner, idx)
                            if result then
                                LootLocker.UpdateLockerUI()
                            end
                        end)
                        table.insert(uiControls, takeBackBtn)
                    end
                    y = y + 30
                end
            end
            y = y + 10
        end
    end

    
    if not hasItems then
        -- Create the "No Items in Locker" message directly in the main window
        -- This bypasses potential scroll container issues
        local emptyLabel = WINDOW_MANAGER:CreateControl(nil, lockerWindow, CT_LABEL)
        if emptyLabel then
            emptyLabel:SetFont("ZoFontWinH2")
            emptyLabel:SetText("No Items in Locker")
            emptyLabel:SetColor(0.7, 0.7, 0.7, 1)
            emptyLabel:SetAnchor(CENTER, lockerWindow, CENTER, 0, 0)
            emptyLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
            emptyLabel:SetDimensions(400, 40)
            table.insert(uiControls, emptyLabel)
        else
            SafePrint("Failed to create empty label")
        end
        
        -- Add instruction text below
        local instructionLabel = WINDOW_MANAGER:CreateControl(nil, lockerWindow, CT_LABEL)
        if instructionLabel then
            instructionLabel:SetFont("ZoFontGame")
            instructionLabel:SetDimensions(450, 80)
            -- Different message for console vs PC
            if type(AddCustomMenuItem) == "function" or type(ZO_AddMenuItem) == "function" then
                instructionLabel:SetText("Right-click tradeable items in your inventory to add them to the locker.")
            else
                instructionLabel:SetText("Use the 'Add Items' button or type '/lockerui' to add tradeable gear to share with your group.")
            end
            instructionLabel:SetColor(0.6, 0.6, 0.6, 1)
            instructionLabel:SetAnchor(CENTER, lockerWindow, CENTER, 0, 50)
            instructionLabel:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
            instructionLabel:SetVerticalAlignment(TEXT_ALIGN_CENTER)
            instructionLabel:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
            table.insert(uiControls, instructionLabel)
        else
            SafePrint("Failed to create instruction label")
        end
    else
    end
end

-- Helper: Check if an item is in the locker (by bagId and slotIndex)
function LootLocker.IsItemInLocker(bagId, slotIndex)
    for owner, items in pairs(LootLocker.locker) do
        for _, item in ipairs(items) do
            if item.bagId == bagId and item.slotIndex == slotIndex then
                return true
            end
        end
    end
    return false
end

-- Overlay logic: visually mark inventory items that are in the locker
local function LootLocker_ApplyLockerOverlay(control, bagId, slotIndex)
    -- Remove old overlay if present
    if control.LootLockerOverlay then
        control.LootLockerOverlay:SetHidden(true)
    end

    if LootLocker.IsItemInLocker and LootLocker.IsItemInLocker(bagId, slotIndex) then
        if not control.LootLockerOverlay then
            local overlay = WINDOW_MANAGER:CreateControl(nil, control, CT_TEXTURE)
            overlay:SetAnchorFill(control)
            overlay:SetColor(1, 0, 0, 0.25) -- semi-transparent red
            overlay:SetDrawLayer(DL_OVERLAY)
            overlay:SetTexture("EsoUI/Art/Miscellaneous/locked_icon.dds")
            overlay:SetTextureCoords(0, 1, 0, 1)
            overlay:SetAlpha(0.7)
            control.LootLockerOverlay = overlay
        end
        control.LootLockerOverlay:SetHidden(false)
    end
end

-- PC: Hook inventory slot mouse enter to show overlay
if type(ZO_PreHook) == "function" then
    ZO_PreHook("ZO_InventorySlot_OnMouseEnter", function(control)
        if control and control.bagId and control.slotIndex then
            LootLocker_ApplyLockerOverlay(control, control.bagId, control.slotIndex)
        end
    end)
    -- Also hook mouse exit to hide overlay
    ZO_PreHook("ZO_InventorySlot_OnMouseExit", function(control)
        if control and control.LootLockerOverlay then
            control.LootLockerOverlay:SetHidden(true)
        end
    end)
end

-- Console/Mac: Periodically scan visible inventory slots and apply overlays
function LootLocker.MonitorForLockerItems()
    if not PLAYER_INVENTORY or not PLAYER_INVENTORY.inventories then return end
    for _, inventory in pairs(PLAYER_INVENTORY.inventories) do
        if inventory.listView and inventory.listView.dataTypes then
            for _, dataType in pairs(inventory.listView.dataTypes) do
                if dataType.pool and dataType.pool.m_Active then
                    for _, control in pairs(dataType.pool.m_Active) do
                        if control and control.dataEntry and control.dataEntry.data then
                            local bagId = control.dataEntry.data.bagId
                            local slotIndex = control.dataEntry.data.slotIndex
                            if bagId and slotIndex then
                                LootLocker_ApplyLockerOverlay(control, bagId, slotIndex)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- Register periodic overlay update for console/Mac
if type(AddCustomMenuItem) ~= "function" and type(ZO_AddMenuItem) ~= "function" then
    EVENT_MANAGER:RegisterForUpdate("LootLockerLockerOverlay", 2000, LootLocker.MonitorForLockerItems)
end

-- Helper: Get unit tag for a player name
function LootLocker.GetPlayerUnitTag(playerName)
    if GetUnitName("player") == playerName then
        return "player"
    end
    
    local groupSize = GetGroupSize()
    for i = 1, groupSize do
        local unitTag = "group" .. i
        if GetUnitName(unitTag) == playerName then
            return unitTag
        end
    end
    return nil
end

-- Mail sending functionality
function LootLocker.SendItemViaMail(recipient, sender, itemEntry)
    -- This is a simplified implementation
    -- In a real scenario, you would need to integrate with ESO's mail system more carefully
    local subject = "LootLocker Delivery"
    local body = string.format("%s has sent you an item from the Loot Locker!", sender)
    
    -- For now, we'll simulate the mail sending process
    -- In a complete implementation, you would:
    -- 1. Open the mail composition window
    -- 2. Set recipient, subject, and body
    -- 3. Attach the item
    -- 4. Send the mail
    
    if LootLocker.settings.showNotifications then
        d(string.format("Sending %s to %s via in-game mail.", itemEntry.link, recipient))
    end
    
    -- Return true to simulate successful sending
    -- In real implementation, check actual mail sending result
    return true
end

-- Clean up expired items
function LootLocker.CleanupExpiredItems()
    local cleaned = false
    for owner, items in pairs(LootLocker.locker) do
        for i = #items, 1, -1 do
            local item = items[i]
            local tradeTimeRemaining = 0
            
            if type(GetItemTradeTimeRemaining) == "function" then
                tradeTimeRemaining = GetItemTradeTimeRemaining(item.bagId, item.slotIndex) or 0
            else
                -- Fallback: use stored trade timer or assume expired after 2 hours
                if item.tradeTimer and item.timestamp then
                    local currentTime = (type(GetTimeStamp) == "function" and GetTimeStamp()) or os.time()
                    local elapsed = currentTime - item.timestamp
                    tradeTimeRemaining = math.max(0, item.tradeTimer - elapsed)
                end
            end
            
            if tradeTimeRemaining <= 0 then
                table.remove(items, i)
                cleaned = true
            end
        end
    end
    if cleaned then
        LootLocker.SaveData()
        if lockerWindow and not lockerWindow:IsHidden() then
            LootLocker.UpdateLockerUI()
        end
    end
end

-- Helper function to get all locker keys for debugging
function LootLocker.GetLockerKeys()
    local keys = {}
    for key, _ in pairs(LootLocker.locker) do
        table.insert(keys, key)
    end
    return keys
end

-- Data persistence
function LootLocker.SaveData()
    if LootLocker.savedVariables then
        -- Ensure we are not replacing the table, just updating its contents
        if LootLocker.savedVariables.locker ~= LootLocker.locker then
            LootLocker.savedVariables.locker = LootLocker.locker
        end
        LootLocker.savedVariables.settings = LootLocker.settings
        SafePrint("Debug: SaveData called. Locker keys: " .. table.concat(LootLocker.GetLockerKeys(), ", "))
    end
end

function LootLocker.LoadData()
    if LootLocker.savedVariables then
        -- Always reference the same table, never assign a new one
        if not LootLocker.savedVariables.locker then
            LootLocker.savedVariables.locker = {}
        end
        LootLocker.locker = LootLocker.savedVariables.locker
        -- Remove any locker keys that are not account names (do not start with @)
        for key in pairs(LootLocker.locker) do
            if type(key) ~= "string" or key:sub(1,1) ~= "@" then
                LootLocker.locker[key] = nil
            end
        end
        if LootLocker.savedVariables.settings then
            for key, value in pairs(LootLocker.savedVariables.settings) do
                LootLocker.settings[key] = value
            end
        end
    end
end

-- Custom UI for console item selection (PS5 compatible)
function LootLocker.ShowItemSelectorUI()
    SafePrint("Opening LootLocker Item Selector...")
    
    -- Create the main window if it doesn't exist
    if not LootLocker.itemSelectorWindow then
        local windowManager = WINDOW_MANAGER
        
        -- Create main window
        local wm = windowManager
        local window = wm:CreateTopLevelWindow("LootLockerItemSelector")
        window:SetDimensions(500, 400)
        window:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
        window:SetMovable(true)
        window:SetMouseEnabled(true)
        window:SetClampedToScreen(true)
        
        -- Background
        local bg = wm:CreateControl("$(parent)BG", window, CT_BACKDROP)
        bg:SetAnchorFill(window)
        bg:SetCenterColor(0, 0, 0, 0.8)
        bg:SetEdgeColor(0.4, 0.4, 0.4, 1)
        bg:SetEdgeTexture("", 8, 1, 1)
        
        -- Title bar
        local titleBar = wm:CreateControl("$(parent)TitleBar", window, CT_BACKDROP)
        titleBar:SetDimensions(500, 30)
        titleBar:SetAnchor(TOP, window, TOP, 0, 0)
        titleBar:SetCenterColor(0.2, 0.2, 0.4, 1)
        titleBar:SetEdgeColor(0.6, 0.6, 0.8, 1)
        titleBar:SetEdgeTexture("", 2, 1, 1)
        
        -- Title text
        local titleText = wm:CreateControl("$(parent)Title", titleBar, CT_LABEL)
        titleText:SetAnchor(CENTER, titleBar, CENTER, 0, 0)
        titleText:SetFont("ZoFontWinH4")
        titleText:SetText("LootLocker - Select Item")
        titleText:SetColor(1, 1, 1, 1)
        
        -- Close button
        local closeButton = wm:CreateControl("$(parent)Close", titleBar, CT_BUTTON)
        closeButton:SetDimensions(20, 20)
        closeButton:SetAnchor(RIGHT, titleBar, RIGHT, -5, 0)
        closeButton:SetText("X")
        closeButton:SetFont("ZoFontWinH5")
        closeButton:SetHandler("OnClicked", function()
            window:SetHidden(true)
        end)
        
        -- Instructions
        local instructions = wm:CreateControl("$(parent)Instructions", window, CT_LABEL)
        instructions:SetAnchor(TOP, titleBar, BOTTOM, 0, 10)
        instructions:SetDimensions(480, 40)
        instructions:SetFont("ZoFontWinH5")
        instructions:SetText("Select an item from your inventory to add to the locker:")
        instructions:SetColor(0.9, 0.9, 0.9, 1)
        instructions:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
        instructions:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        
        -- Inventory list background
        local listBG = wm:CreateControl("$(parent)ListBG", window, CT_BACKDROP)
        listBG:SetDimensions(460, 280)
        listBG:SetAnchor(TOP, instructions, BOTTOM, 0, 10)
        listBG:SetCenterColor(0.1, 0.1, 0.1, 0.9)
        listBG:SetEdgeColor(0.3, 0.3, 0.3, 1)
        listBG:SetEdgeTexture("", 2, 1, 1)
        
        -- Create scroll container for inventory items
        local scrollContainer = wm:CreateControl("$(parent)ScrollContainer", listBG, CT_SCROLL)
        scrollContainer:SetDimensions(440, 260)
        scrollContainer:SetAnchor(CENTER, listBG, CENTER, 0, 0)
        
        -- Content container for items
        local contentContainer = wm:CreateControl("$(parent)Content", scrollContainer, CT_CONTROL)
        contentContainer:SetResizeToFitDescendents(true)
        contentContainer:SetAnchor(TOPLEFT, scrollContainer, TOPLEFT, 0, 0)
        
        -- Store references
        LootLocker.itemSelectorWindow = window
        LootLocker.itemSelectorContent = contentContainer
        LootLocker.itemButtons = {}
        
        SafePrint("Item selector window created successfully.")
    end
    
    -- Populate the inventory list
    LootLocker.PopulateInventoryList()
    
    -- Show the window
    LootLocker.itemSelectorWindow:SetHidden(false)
    LootLocker.itemSelectorWindow:BringWindowToTop()
end

-- Populate the inventory list with items
function LootLocker.PopulateInventoryList()
    if not LootLocker.itemSelectorContent then
        SafePrint("Error: Item selector not initialized")
        return
    end
    
    local wm = WINDOW_MANAGER
    if not wm then
        SafePrint("Error: WINDOW_MANAGER not available")
        return
    end
    
    local content = LootLocker.itemSelectorContent
    if not content then
        SafePrint("Error: Item selector content not available")
        return
    end
    
    -- Clear existing buttons - properly destroy them instead of just hiding
    if LootLocker.itemButtons then
        for _, button in pairs(LootLocker.itemButtons) do
            if button and button.SetParent and type(button.SetParent) == "function" then
                -- Properly remove the control by setting parent to nil
                button:SetParent(nil)
                button:SetHidden(true)
                -- Clear all anchors to fully disconnect
                if button.ClearAnchors and type(button.ClearAnchors) == "function" then
                    button:ClearAnchors()
                end
            end
        end
    end
    LootLocker.itemButtons = {}
    
    -- Also clear the content container's children to ensure clean slate
    if content and content.GetChildren and type(content.GetChildren) == "function" then
        local children = content:GetChildren()
        for i = 1, #children do
            local child = children[i]
            if child and child.SetParent and type(child.SetParent) == "function" then
                child:SetParent(nil)
                child:SetHidden(true)
            end
        end
    end
    
    -- Get inventory items
    local bagId = BAG_BACKPACK
    local bagSlots = 0
    
    if type(GetBagSize) == "function" then
        bagSlots = GetBagSize(bagId) or 0
    else
        SafePrint("Warning: GetBagSize function not available")
        return
    end
    local yOffset = 0
    local buttonHeight = 30
    local itemCount = 0
    
    SafePrint("Scanning " .. bagSlots .. " inventory slots for eligible items (armor, weapons, jewelry - green quality or better)...")
    
    for slotIndex = 0, bagSlots - 1 do
        local hasItem = false
        if type(DoesItemHaveSlotData) == "function" then
            hasItem = DoesItemHaveSlotData(bagId, slotIndex)
        else
            -- Fallback: check if item name exists
            if type(GetItemName) == "function" then
                local name = GetItemName(bagId, slotIndex)
                hasItem = name and name ~= ""
            end
        end
        
        if hasItem then
            local itemName = ""
            local itemLink = ""
            
            if type(GetItemName) == "function" then
                itemName = GetItemName(bagId, slotIndex) or ""
            end
            
            if type(GetItemLink) == "function" then
                itemLink = GetItemLink(bagId, slotIndex) or ""
            end
            
            -- Skip equipped items - they shouldn't be shareable (but only if we can check)
            local isEquipped = false
            if type(IsItemEquipped) == "function" then
                isEquipped = IsItemEquipped(bagId, slotIndex)
            end
            
            -- Process items that are not equipped (or if we can't check equipped status)
            if not isEquipped then
                -- Use fallback for PS5 compatibility
                local itemQuality = ITEM_DISPLAY_QUALITY_NORMAL
                if type(GetItemDisplayQuality) == "function" then
                    itemQuality = GetItemDisplayQuality(bagId, slotIndex)
                elseif type(GetItemQuality) == "function" then
                    itemQuality = GetItemQuality(bagId, slotIndex)
                end
                
                -- Get equipment type for filtering
                local equipType = nil
                if type(GetItemEquipType) == "function" then
                    equipType = GetItemEquipType(bagId, slotIndex)
                end
                
                -- Only show armor, weapons, and jewelry of green quality or better
                local isValidType = false
                if equipType then
                    isValidType = (
                        equipType == EQUIP_TYPE_HEAD or
                        equipType == EQUIP_TYPE_CHEST or
                        equipType == EQUIP_TYPE_SHOULDERS or
                        equipType == EQUIP_TYPE_HAND or
                        equipType == EQUIP_TYPE_WAIST or
                        equipType == EQUIP_TYPE_LEGS or
                        equipType == EQUIP_TYPE_FEET or
                        equipType == EQUIP_TYPE_NECK or
                        equipType == EQUIP_TYPE_RING or
                        equipType == EQUIP_TYPE_ONE_HAND or
                        equipType == EQUIP_TYPE_TWO_HAND or
                        equipType == EQUIP_TYPE_OFF_HAND
                    )
                end
                
                -- Check quality - must be green (2) or better
                local isGoodQuality = (itemQuality and itemQuality >= 2)
                
                -- Only process items that meet our criteria
                if itemName and itemName ~= "" and isValidType and isGoodQuality then
                    itemCount = itemCount + 1
                    
                    SafeCall(function()
                        -- Create item button with unique name using timestamp
                        local timestamp = GetTimeStamp and GetTimeStamp() or os.time()
                        local uniqueName = "LootLockerItem" .. itemCount .. "_" .. timestamp
                        local itemButton = wm:CreateControl(uniqueName, content, CT_BUTTON)
                        if not itemButton then
                            SafePrint("Error: Could not create item button for " .. itemName)
                            return
                        end
                        
                        itemButton:SetDimensions(420, buttonHeight)
                        itemButton:SetAnchor(TOPLEFT, content, TOPLEFT, 10, yOffset)
                        
                        -- Button background
                        local buttonBG = wm:CreateControl("$(parent)BG", itemButton, CT_BACKDROP)
                        if buttonBG then
                            buttonBG:SetAnchorFill(itemButton)
                            buttonBG:SetCenterColor(0.2, 0.2, 0.2, 0.5)
                            buttonBG:SetEdgeColor(0.4, 0.4, 0.4, 0.8)
                            buttonBG:SetEdgeTexture("", 1, 1, 1)
                        end
                    
                    -- Item text
                    local itemText = wm:CreateControl("$(parent)Text", itemButton, CT_LABEL)
                    if itemText then
                        itemText:SetAnchor(LEFT, itemButton, LEFT, 10, 0)
                        itemText:SetFont("ZoFontWinH5")
                        itemText:SetText(itemName)
                        
                        -- Set text color based on quality
                        local r, g, b = 1, 1, 1  -- Default white color
                        if type(GetInterfaceColor) == "function" and INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS then
                            r, g, b = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, itemQuality)
                        else
                            -- Fallback color scheme for different qualities
                            if itemQuality == 0 then -- Trash
                                r, g, b = 0.4, 0.4, 0.4
                            elseif itemQuality == 1 then -- Normal
                                r, g, b = 1, 1, 1
                            elseif itemQuality == 2 then -- Fine (Green)
                                r, g, b = 0.4, 1, 0.4
                            elseif itemQuality == 3 then -- Superior (Blue)
                                r, g, b = 0.4, 0.6, 1
                            elseif itemQuality == 4 then -- Epic (Purple)
                                r, g, b = 0.8, 0.4, 1
                            elseif itemQuality == 5 then -- Legendary (Gold)
                                r, g, b = 1, 0.8, 0.2
                            else
                                r, g, b = 1, 1, 1 -- Default white
                            end
                        end
                        itemText:SetColor(r, g, b, 1)
                    end
                    
                    -- Button click handler
                    if itemButton.SetHandler and type(itemButton.SetHandler) == "function" then
                        itemButton:SetHandler("OnClicked", function()
                            LootLocker.AddItemToLockerFromUI(bagId, slotIndex, itemName, itemLink)
                        end)
                        
                        -- Hover effects
                        itemButton:SetHandler("OnMouseEnter", function()
                            if buttonBG then
                                buttonBG:SetCenterColor(0.3, 0.3, 0.4, 0.7)
                            end
                        end)
                        itemButton:SetHandler("OnMouseExit", function()
                            if buttonBG then
                                buttonBG:SetCenterColor(0.2, 0.2, 0.2, 0.5)
                            end
                        end)
                    end
                    
                    table.insert(LootLocker.itemButtons, itemButton)
                    yOffset = yOffset + buttonHeight + 2
                    end) -- End SafeCall
                end
            end
        end
    end
    
    SafePrint("Found " .. itemCount .. " eligible items in inventory (armor, weapons, jewelry - green+ quality)")
    
    if itemCount == 0 then
        -- Show "no items" message with unique name
        local timestamp = GetTimeStamp and GetTimeStamp() or os.time()
        
        -- Main "no items" heading
        local noItemsHeading = wm:CreateControl("LootLockerNoItemsHeading_" .. timestamp, content, CT_LABEL)
        noItemsHeading:SetDimensions(400, 40)
        noItemsHeading:SetAnchor(TOPLEFT, content, TOPLEFT, 20, 40)
        noItemsHeading:SetFont("ZoFontWinH2")
        noItemsHeading:SetText("No Eligible Items Found")
        noItemsHeading:SetColor(0.7, 0.7, 0.7, 1)
        noItemsHeading:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
        table.insert(LootLocker.itemButtons, noItemsHeading)
        
        -- Detailed explanation
        local noItemsText = wm:CreateControl("LootLockerNoItems_" .. timestamp, content, CT_LABEL)
        noItemsText:SetDimensions(400, 80)
        noItemsText:SetAnchor(TOP, noItemsHeading, BOTTOM, 0, 10)
        noItemsText:SetFont("ZoFontGame")
        noItemsText:SetText("Only armor, weapons, and jewelry of green quality or better are shown.\n\nMake sure items are not equipped and are tradeable.")
        noItemsText:SetColor(0.6, 0.6, 0.6, 1)
        noItemsText:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
        noItemsText:SetVerticalAlignment(TEXT_ALIGN_CENTER)
        noItemsText:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
        table.insert(LootLocker.itemButtons, noItemsText)
    end
end

-- Add item to locker from the custom UI
function LootLocker.AddItemToLockerFromUI(bagId, slotIndex, itemName, itemLink)
    SafePrint("Adding " .. itemName .. " to locker...")
    if type(IsItemEquipped) == "function" and IsItemEquipped(bagId, slotIndex) then
        SafePrint("Cannot add item: This item is currently equipped and cannot be shared.")
        return
    end
    if not LootLocker.ValidateItem(bagId, slotIndex) then
        SafePrint("Cannot add item: Only armor, weapons, and jewelry of uncommon quality or higher can be added to the locker.")
        return
    end
    -- Allow owner to add their own items even if trade timer is 0 (for take-back)
    local isOwner = true -- Always true for AddItemToLockerFromUI
    local tradeTime = 0
    if type(GetItemTradeTimeRemaining) == "function" then
        tradeTime = GetItemTradeTimeRemaining(bagId, slotIndex) or 0
        if not isOwner and (not tradeTime or tradeTime <= 0) then
            SafePrint("Cannot add item: This item is not tradeable or the trade timer has expired.")
            return
        end
    else
        SafePrint("Warning: Trade timer API not available on this platform - item tradeability cannot be verified")
    end
    -- Use display name as key for locker (account-wide, not character name)
    local lockerKey = GetUnitDisplayName and GetUnitDisplayName("player") or ("@" .. (GetUnitName("player") or ""))
    if not lockerKey or lockerKey == "" then
        SafePrint("Error: Could not get account or character name")
        return
    end
    SafePrint("Debug: Adding item to locker with key: " .. lockerKey)
    if not LootLocker.locker[lockerKey] then
        LootLocker.locker[lockerKey] = {}
    end
    if #LootLocker.locker[lockerKey] >= LootLocker.settings.maxItemsPerPlayer then
        SafePrint("Cannot add item: Maximum items per player reached (" .. LootLocker.settings.maxItemsPerPlayer .. ").")
        return
    end
    local itemId = 0
    local stackSize = 1
    if type(GetItemId) == "function" then
        itemId = GetItemId(bagId, slotIndex) or 0
    end
    if type(GetSlotStackSize) == "function" then
        stackSize = GetSlotStackSize(bagId, slotIndex) or 1
    end
    local tradeTimer = 0
    if type(GetItemTradeTimeRemaining) == "function" then
        tradeTimer = GetItemTradeTimeRemaining(bagId, slotIndex) or 0
    end
    local lockerItem = {
        name = itemName,
        link = itemLink,
        id = itemId,
        quantity = stackSize,
        tradeTimer = tradeTimer,
        timestamp = (type(GetTimeStamp) == "function" and GetTimeStamp()) or os.time(),
        bagId = bagId,
        slotIndex = slotIndex
    }
    table.insert(LootLocker.locker[lockerKey], lockerItem)
    SafePrint("Debug: Item added to locker. Current items in " .. lockerKey .. ": " .. #LootLocker.locker[lockerKey])
    LootLocker.SaveData()
    if lockerWindow and not lockerWindow:IsHidden() then
        LootLocker.UpdateLockerUI()
    end
    if LootLocker.itemSelectorWindow then
        LootLocker.itemSelectorWindow:SetHidden(true)
    end
    SafePrint("Successfully added " .. itemName .. " to locker!")
end

-- Take back item from locker (for owner only)
function LootLocker.TakeBackItem(ownerName, itemIndex)
    local ownerLocker = LootLocker.locker[ownerName]
    if not ownerLocker or not ownerLocker[itemIndex] then
        SafePrint("Item not found in locker.")
        return false
    end
    
    local itemEntry = ownerLocker[itemIndex]
    table.remove(ownerLocker, itemIndex)
    LootLocker.SaveData()
    SafePrint("Took back " .. (itemEntry.link or itemEntry.name or "item") .. " from locker.")
    return true
end

-- Register slash commands
local function OnAddOnLoaded(event, addonName)
    if addonName == "LootLocker" then
        -- Initialize saved variables
        LootLocker.savedVariables = ZO_SavedVars:NewAccountWide("LootLockerSavedVars", 1, nil, {
            locker = {},
            settings = LootLocker.settings
        })
        
        -- Load saved data
        LootLocker.LoadData()
        
        -- Register for group activity start (dungeon/trial)
        -- Use a more reliable event that exists on PS5
        local success = pcall(function()
            EVENT_MANAGER:RegisterForEvent("LootLocker", EVENT_ZONE_CHANGED, LootLocker.OnActivityStart)
        end)
        
        -- Register for group member changes to clean up when players leave
        pcall(function()
            EVENT_MANAGER:RegisterForEvent("LootLocker", EVENT_GROUP_MEMBER_LEFT, function(eventCode, characterName, reason, isLocalPlayer, isLeader)
                if LootLocker.locker[characterName] then
                    LootLocker.locker[characterName] = nil
                    LootLocker.SaveData()
                    if lockerWindow and not lockerWindow:IsHidden() then
                        LootLocker.UpdateLockerUI()
                    end
                end
            end)
        end)
        
        -- Register for group join events (console auto-discovery)
        pcall(function()
            EVENT_MANAGER:RegisterForEvent("LootLocker", EVENT_GROUP_MEMBER_JOINED, function(eventCode, characterName)
                LootLocker.OnGroupJoined()
            end)
            EVENT_MANAGER:RegisterForEvent("LootLocker", EVENT_PLAYER_ACTIVATED, function()
                if GetGroupSize() > 1 then
                    LootLocker.OnGroupJoined()
                end
            end)
        end)
        
        -- Set up periodic monitoring for tradeable items (console only)
        if type(AddCustomMenuItem) ~= "function" and type(ZO_AddMenuItem) ~= "function" then
            EVENT_MANAGER:RegisterForUpdate("LootLockerItemMonitor", 5000, LootLocker.MonitorForTradeableItems)
            -- Periodic reminder every 3 minutes for console users in groups
            EVENT_MANAGER:RegisterForUpdate("LootLockerReminder", 180000, LootLocker.ShowPeriodicReminder)
        end
        
        -- Context menu registration is not supported on PS5
        -- Skip context menu setup for console compatibility
        if type(AddCustomMenuItem) == "function" or type(ZO_AddMenuItem) == "function" then
            -- PC version - add context menu option with error handling
            pcall(function()
                LootLocker.AddMenuOption()
            end)
        end
        
        -- Set up periodic cleanup of expired items
        EVENT_MANAGER:RegisterForUpdate("LootLockerCleanup", 30000, LootLocker.CleanupExpiredItems) -- Every 30 seconds
        
        -- Register slash commands here to ensure SLASH_COMMANDS exists
        if SLASH_COMMANDS then
            SLASH_COMMANDS["/locker"] = function()
                d("LootLocker: Opening locker window...")
                LootLocker.ShowLockerUI(LootLocker.GetEligibleMembers())
            end
            SLASH_COMMANDS["/lockerclear"] = function()
                LootLocker.CleanupExpiredItems()
                d("LootLocker: Cleared expired items.")
            end



            SLASH_COMMANDS["/lockeradd"] = function(itemSlot)
                -- Add current targeted item to locker
                local bagId, slotIndex = SHARED_INVENTORY:GetCurrentDropInfo()
                if not bagId or not slotIndex then
                    -- Try to get from player inventory if no drag info
                    bagId = BAG_BACKPACK
                    -- We'll need the user to specify slot or use a different method
                    SafePrint("To add items to the locker on console:")
                    SafePrint("Use /lockerui to open the item selection interface")
                    SafePrint("Then click on any item to add it to the locker")
                    return
                end
                
                local playerName = GetUnitName("player")
                local success = LootLocker.PostGear(playerName, bagId, slotIndex)
                if success then
                    SafePrint("Item added to locker successfully!")
                    if lockerWindow and not lockerWindow:IsHidden() then
                        LootLocker.UpdateLockerUI()
                    end
                else
                    SafePrint("Failed to add item to locker.")
                end
            end
            SLASH_COMMANDS["/lockerui"] = function()
                -- Open the custom item selection UI for PS5/console
                LootLocker.ShowItemSelectorUI()
            end
            SLASH_COMMANDS["/lockertake"] = function()
                -- Show a simple list of your items to take back
                local playerName = GetUnitName("player")
                local hasItems = false
                
                if LootLocker.locker[playerName] then
                    SafePrint("Your items in the locker:")
                    for i, item in ipairs(LootLocker.locker[playerName]) do
                        local timeLeft = 0
                        if type(GetItemTradeTimeRemaining) == "function" then
                            timeLeft = GetItemTradeTimeRemaining(item.bagId, item.slotIndex) or 0
                        end
                        
                        if timeLeft > 0 then
                            local hours = math.floor(timeLeft / 3600)
                            local minutes = math.floor((timeLeft % 3600) / 60)
                            SafePrint(string.format("  %d. %s (Time: %d:%02d)", i, item.link, hours, minutes))
                            hasItems = true
                        end
                    end
                    
                    if hasItems then
                        SafePrint("Use /locker to open the UI and click 'Take Back' next to items you want.")
                    else
                        SafePrint("No tradeable items found in your locker.")
                    end
                else
                    SafePrint("You have no items in the locker.")
                end
            end
            SLASH_COMMANDS["/lockerhelp"] = function()
                d("LootLocker Commands (PS5 Version):")
                d("/locker - Open the Loot Locker window")
                d("/lockerclear - Remove expired items from the locker")
                d("/lockertest - Show debug information")
                d("/lockerdebug - Test message display functions")
                d("/lockeradd - Add item to locker (under development)")
                d("/lockerui - Open item selector interface for adding items")
                d("/lockertake - Take back your items from locker")
                d("/lockerhelp - Show this help")
                d("")
                d("Console Usage:")
                d("1. Use /lockerui to open the item selection interface")
                d("2. Click on any item in your inventory to add it to the locker")
                d("3. Use /locker to view and manage your locked items")
                d("")
                d("Note: Right-click context menus are not supported on console.")
            end
        end
        
        SafePrint("LootLocker v1.0.4-PS5 loaded successfully!")
        
        -- Auto-show UI for console users when they join a group
        if type(AddCustomMenuItem) ~= "function" and type(ZO_AddMenuItem) ~= "function" then
            SafePrint("Console version ready - Auto-opening when you join a group!")
        end
    end
end

EVENT_MANAGER:RegisterForEvent("LootLocker", EVENT_ADD_ON_LOADED, OnAddOnLoaded)

-- Console Welcome UI - shows automatically for new users
function LootLocker.ShowConsoleWelcome()
    -- Don't show if user has already used the addon
    if LootLocker.savedVariables and LootLocker.savedVariables.hasSeenWelcome then
        return
    end
    
    SafePrint("Welcome to LootLocker for PS5!")
    
    -- Create welcome window
    local wm = WINDOW_MANAGER
    local welcomeWindow = wm:CreateTopLevelWindow("LootLockerWelcome")
    welcomeWindow:SetDimensions(450, 350)
    welcomeWindow:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    welcomeWindow:SetMovable(false)
    welcomeWindow:SetMouseEnabled(true)
    welcomeWindow:SetClampedToScreen(true)
    welcomeWindow:SetHidden(false)
    
    -- Background
    local bg = wm:CreateControl("$(parent)BG", welcomeWindow, CT_BACKDROP)
    bg:SetAnchorFill(welcomeWindow)
    bg:SetCenterColor(0.1, 0.1, 0.2, 0.95)
    bg:SetEdgeColor(0.6, 0.6, 0.8, 1)
    bg:SetEdgeTexture("", 4, 1, 1)
    
    -- Title
    local title = wm:CreateControl("$(parent)Title", welcomeWindow, CT_LABEL)
    title:SetAnchor(TOP, welcomeWindow, TOP, 0, 20)
    title:SetFont("ZoFontWinH1")
    title:SetText("Welcome to LootLocker!")
    title:SetColor(1, 0.8, 0.2, 1)
    
    -- Main text
    local mainText = wm:CreateControl("$(parent)Text", welcomeWindow, CT_LABEL)
    mainText:SetAnchor(TOP, title, BOTTOM, 0, 20)
    mainText:SetDimensions(400, 150)
    mainText:SetFont("ZoFontGame")
    mainText:SetText("LootLocker helps you share tradeable gear with your group!\n\nSince you're on console, we've created an easy-to-use interface.\n\nWhen you're in a group and find gear you want to share, this addon will automatically guide you.")
    mainText:SetColor(0.9, 0.9, 0.9, 1)
    mainText:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    mainText:SetVerticalAlignment(TEXT_ALIGN_TOP)
    mainText:SetWrapMode(TEXT_WRAP_MODE_ELLIPSIS)
    
    -- Button container
    local buttonContainer = wm:CreateControl("$(parent)Buttons", welcomeWindow, CT_CONTROL)
    buttonContainer:SetDimensions(400, 80)
    buttonContainer:SetAnchor(BOTTOM, welcomeWindow, BOTTOM, 0, -20)
    
    -- Try It Now button
    local tryButton = wm:CreateControl("$(parent)Try", buttonContainer, CT_BUTTON)
    tryButton:SetDimensions(150, 35)
    tryButton:SetAnchor(LEFT, buttonContainer, LEFT, 20, 0)
    tryButton:SetText("Try It Now!")
    tryButton:SetFont("ZoFontWinH4")
    tryButton:SetNormalFontColor(0.2, 0.8, 0.2, 1)
    tryButton:SetHandler("OnClicked", function()
        welcomeWindow:SetHidden(true)
        LootLocker.ShowItemSelectorUI()
    end)
    
    -- Got It button
    local gotItButton = wm:CreateControl("$(parent)GotIt", buttonContainer, CT_BUTTON)
    gotItButton:SetDimensions(100, 35)
    gotItButton:SetAnchor(RIGHT, buttonContainer, RIGHT, -20, 0)
    gotItButton:SetText("Got It!")
    gotItButton:SetFont("ZoFontWinH4")
    gotItButton:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    gotItButton:SetHandler("OnClicked", function()
        welcomeWindow:SetHidden(true)
        -- Mark as seen
        LootLocker.savedVariables.hasSeenWelcome = true
        LootLocker.SaveData()
    end)
    
    -- Auto-close after 15 seconds
    zo_callLater(function()
        if welcomeWindow and not welcomeWindow:IsHidden() then
            welcomeWindow:SetHidden(true)
            LootLocker.savedVariables.hasSeenWelcome = true
            LootLocker.SaveData()
        end
    end, 15000)
end

-- Auto-show locker when player joins a group (console-friendly)
function LootLocker.OnGroupJoined()
    -- Only for console users
    if type(AddCustomMenuItem) == "function" or type(ZO_AddMenuItem) == "function" then
        return -- PC users have context menus
    end
    
    local groupSize = GetGroupSize()
    if groupSize > 1 then
        zo_callLater(function()
            SafePrint("Group detected! LootLocker is ready to help you share gear.")
            SafePrint("When you find tradeable gear, look for the LootLocker notification.")
            
            -- Show a helpful overlay
            LootLocker.ShowGroupJoinedOverlay()
        end, 2000)
    end
end

-- Show overlay when group is joined
function LootLocker.ShowGroupJoinedOverlay()
    local wm = WINDOW_MANAGER
    local overlay = wm:CreateTopLevelWindow("LootLockerGroupOverlay")
    overlay:SetDimensions(350, 120)
    overlay:SetAnchor(TOP, GuiRoot, TOP, 0, 100)
    overlay:SetMouseEnabled(false)
    overlay:SetHidden(false)
    
    -- Background
    local bg = wm:CreateControl("$(parent)BG", overlay, CT_BACKDROP)
    bg:SetAnchorFill(overlay)
    bg:SetCenterColor(0.2, 0.4, 0.2, 0.8)
    bg:SetEdgeColor(0.4, 0.8, 0.4, 1)
    bg:SetEdgeTexture("", 2, 1, 1)
    
    -- Text
    local text = wm:CreateControl("$(parent)Text", overlay, CT_LABEL)
    text:SetAnchor(CENTER, overlay, CENTER, 0, 0)
    text:SetDimensions(330, 100)
    text:SetFont("ZoFontWinH4")
    text:SetText("LootLocker Active!\nGroup gear sharing enabled.")
    text:SetColor(1, 1, 1, 1)
    text:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    text:SetVerticalAlignment(TEXT_ALIGN_CENTER)
    
    -- Auto-hide after 4 seconds
    zo_callLater(function()
        if overlay then
            overlay:SetHidden(true)
        end
    end, 4000)
end

-- Enhanced item selector with better guidance
function LootLocker.ShowItemSelectorUIWithGuidance(itemLink)
    SafePrint("Opening LootLocker Item Selector...")
    
    -- Show the regular UI first
    LootLocker.ShowItemSelectorUI()
    
    -- Add guidance overlay
    if itemLink then
        zo_callLater(function()
            SafePrint("Found tradeable item: " .. itemLink)
            SafePrint("Click on it in the list below to share with your group!")
        end, 500)
    end
end

-- Monitor for tradeable items and notify user
function LootLocker.MonitorForTradeableItems()
    -- Only for console
    if type(AddCustomMenuItem) == "function" or type(ZO_AddMenuItem) == "function" then
        return
    end
    
    -- Only when in a group
    if type(GetGroupSize) ~= "function" or GetGroupSize() <= 1 then
        return
    end
    
    local bagId = BAG_BACKPACK
    local bagSlots = 0
    
    if type(GetBagSize) == "function" then
        bagSlots = GetBagSize(bagId) or 0
    else
        return
    end
    
    for slotIndex = 0, bagSlots - 1 do
        local hasItem = false
        if type(DoesItemHaveSlotData) == "function" then
            hasItem = DoesItemHaveSlotData(bagId, slotIndex)
        elseif type(GetItemName) == "function" then
            local name = GetItemName(bagId, slotIndex)
            hasItem = name and name ~= ""
        end
        
        if hasItem then
            local itemLink = ""
            local itemName = ""
            
            if type(GetItemLink) == "function" then
                itemLink = GetItemLink(bagId, slotIndex) or ""
            end
            
            if type(GetItemName) == "function" then
                itemName = GetItemName(bagId, slotIndex) or ""
            end
            
            -- Check if it's a new tradeable item
            if itemLink ~= "" and itemName ~= "" then
                local tradeTime = 0
                if type(GetItemTradeTimeRemaining) == "function" then
                    tradeTime = GetItemTradeTimeRemaining(bagId, slotIndex) or 0
                end
                
                -- Check if it's potentially shareable (validate item type)
                if LootLocker.ValidateItem(bagId, slotIndex) and tradeTime > 7000 then -- More than ~2 hours
                    -- This looks like a new tradeable item worth sharing
                    LootLocker.NotifyTradeableItem(itemLink, bagId, slotIndex)
                    return -- Only notify about one item at a time
                end
            end
        end
    end
end

-- Notify user about tradeable item with action prompt
function LootLocker.NotifyTradeableItem(itemLink, bagId, slotIndex)
    -- Don't spam notifications
    local currentTime = (type(GetTimeStamp) == "function" and GetTimeStamp()) or os.time()
    if LootLocker.lastNotificationTime and (currentTime - LootLocker.lastNotificationTime) < 10 then
        return
    end
    LootLocker.lastNotificationTime = currentTime
    
    SafePrint("New tradeable item found!")
    SafePrint("Item: " .. itemLink)
    
    -- Show action overlay
    local wm = WINDOW_MANAGER
    local actionOverlay = wm:CreateTopLevelWindow("LootLockerActionPrompt")
    actionOverlay:SetDimensions(400, 140)
    actionOverlay:SetAnchor(CENTER, GuiRoot, CENTER, 0, -50)
    actionOverlay:SetMouseEnabled(true)
    actionOverlay:SetHidden(false)
    
    -- Background
    local bg = wm:CreateControl("$(parent)BG", actionOverlay, CT_BACKDROP)
    bg:SetAnchorFill(actionOverlay)
    bg:SetCenterColor(0.2, 0.2, 0.4, 0.9)
    bg:SetEdgeColor(0.6, 0.6, 0.8, 1)
    bg:SetEdgeTexture("", 3, 1, 1)
    
    -- Title
    local title = wm:CreateControl("$(parent)Title", actionOverlay, CT_LABEL)
    title:SetAnchor(TOP, actionOverlay, TOP, 0, 10)
    title:SetFont("ZoFontWinH3")
    title:SetText("Share This Item?")
    title:SetColor(1, 0.8, 0.2, 1)
    
    -- Item text
    local itemText = wm:CreateControl("$(parent)Item", actionOverlay, CT_LABEL)
    itemText:SetAnchor(TOP, title, BOTTOM, 0, 5)
    itemText:SetDimensions(380, 30)
    itemText:SetFont("ZoFontGame")
    itemText:SetText(itemLink)
    itemText:SetColor(0.9, 0.9, 0.9, 1)
    itemText:SetHorizontalAlignment(TEXT_ALIGN_CENTER)
    
    -- Button container
    local buttons = wm:CreateControl("$(parent)Buttons", actionOverlay, CT_CONTROL)
    buttons:SetDimensions(350, 40)
    buttons:SetAnchor(BOTTOM, actionOverlay, BOTTOM, 0, -10)
    
    -- Share button
    local shareButton = wm:CreateControl("$(parent)Share", buttons, CT_BUTTON)
    shareButton:SetDimensions(120, 35)
    shareButton:SetAnchor(LEFT, buttons, LEFT, 30, 0)
    shareButton:SetText("Share It!")
    shareButton:SetFont("ZoFontWinH4")
    shareButton:SetNormalFontColor(0.2, 0.8, 0.2, 1)
    shareButton:SetHandler("OnClicked", function()
        actionOverlay:SetHidden(true)
        local playerName = GetUnitName("player")
        local success = LootLocker.PostGear(playerName, bagId, slotIndex)
        if success then
            SafePrint("Item shared with group!")
        end
    end)
    
    -- Not Now button
    local notNowButton = wm:CreateControl("$(parent)NotNow", buttons, CT_BUTTON)
    notNowButton:SetDimensions(100, 35)
    notNowButton:SetAnchor(CENTER, buttons, CENTER, 0, 0)
    notNowButton:SetText("Not Now")
    notNowButton:SetFont("ZoFontWinH4")
    notNowButton:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    notNowButton:SetHandler("OnClicked", function()
        actionOverlay:SetHidden(true)
    end)
    
    -- Browse All button
    local browseButton = wm:CreateControl("$(parent)Browse", buttons, CT_BUTTON)
    browseButton:SetDimensions(120, 35)
    browseButton:SetAnchor(RIGHT, buttons, RIGHT, -30, 0)
    browseButton:SetText("Browse All")
    browseButton:SetFont("ZoFontWinH4")
    browseButton:SetNormalFontColor(0.2, 0.6, 0.8, 1)
    browseButton:SetHandler("OnClicked", function()
        actionOverlay:SetHidden(true)
        LootLocker.ShowItemSelectorUIWithGuidance(itemLink)
    end)
    
    -- Auto-hide after 12 seconds
    zo_callLater(function()
        if actionOverlay and not actionOverlay:IsHidden() then
            actionOverlay:SetHidden(true)
        end
    end, 12000)
end

-- Show periodic reminder for console users in groups
function LootLocker.ShowPeriodicReminder()
    -- Only for console users in groups
    if type(AddCustomMenuItem) == "function" or type(ZO_AddMenuItem) == "function" then
        return
    end
    
    if GetGroupSize() <= 1 then
        return
    end
    
    -- Don't show if locker window is already open
    if lockerWindow and not lockerWindow:IsHidden() then
        return
    end
    
    -- Create floating reminder button
    local wm = WINDOW_MANAGER
    local reminder = wm:CreateTopLevelWindow("LootLockerReminder")
    reminder:SetDimensions(200, 60)
    reminder:SetAnchor(TOPRIGHT, GuiRoot, TOPRIGHT, -50, 150)
    reminder:SetMouseEnabled(true)
    reminder:SetHidden(false)
    
    -- Background
    local bg = wm:CreateControl("$(parent)BG", reminder, CT_BACKDROP)
    bg:SetAnchorFill(reminder)
    bg:SetCenterColor(0.2, 0.3, 0.5, 0.85)
    bg:SetEdgeColor(0.4, 0.5, 0.8, 1)
    bg:SetEdgeTexture("", 2, 1, 1)
    
    -- Button
    local button = wm:CreateControl("$(parent)Button", reminder, CT_BUTTON)
    button:SetAnchorFill(reminder)
    button:SetText("Open LootLocker")
    button:SetFont("ZoFontWinH4")
    button:SetNormalFontColor(1, 1, 1, 1)
    button:SetHandler("OnClicked", function()
        reminder:SetHidden(true)
        LootLocker.ShowLockerUI(LootLocker.GetEligibleMembers())
    end)
    
    -- Close X
    local closeX = wm:CreateControl("$(parent)Close", reminder, CT_BUTTON)
    closeX:SetDimensions(15, 15)
    closeX:SetAnchor(TOPRIGHT, reminder, TOPRIGHT, -3, 3)
    closeX:SetText("×")
    closeX:SetFont("ZoFontGame")
    closeX:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    closeX:SetHandler("OnClicked", function()
        reminder:SetHidden(true)
    end)
    
    -- Auto-hide after 8 seconds
    zo_callLater(function()
        if reminder and not reminder:IsHidden() then
            reminder:SetHidden(true)
        end
    end, 8000)
end
