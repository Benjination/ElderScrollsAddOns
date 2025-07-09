-- Megastore ESO Add-on
-- Community-driven guild store aggregator
-- Collects and shares guild store data to help players find items across all traders

local Megastore = {}

-- Version and metadata
Megastore.name = "Megastore"
Megastore.version = "1.0.0"

-- Database structure for storing guild store data
Megastore.database = {
    guildStores = {},     -- Store data indexed by trader location/guild
    itemIndex = {},       -- Items indexed by name for fast searching
    lastUpdate = {},      -- Timestamps for when each store was last scanned
    settings = {
        autoScan = true,          -- Automatically scan when opening guild stores
        shareData = true,         -- Share data with other addon users (future feature)
        maxAge = 86400,          -- Max age in seconds (24 hours) before data is considered stale
        debugMode = true          -- Show debug messages (temporarily enabled for troubleshooting)
    }
}

-- Saved variables reference
Megastore.savedVars = nil

-- Constants
local TRADER_INTERACTION_TYPE_GUILD_STORE = 1
local MAX_ITEMS_PER_PAGE = 100

-- Utility: Safe debug print
local function MegaPrint(message, isDebug)
    if isDebug and not Megastore.database.settings.debugMode then
        return
    end
    
    local prefix = isDebug and "[Megastore Debug] " or "[Megastore] "
    if type(d) == "function" then
        d(prefix .. tostring(message))
    end
end

-- Utility: Get current timestamp
local function GetCurrentTime()
    return GetTimeStamp and GetTimeStamp() or os.time()
end

-- Utility: Format time difference for display
local function FormatTimeDiff(timestamp)
    local diff = GetCurrentTime() - timestamp
    if diff < 60 then
        return "Just now"
    elseif diff < 3600 then
        return math.floor(diff / 60) .. " minutes ago"
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. " hours ago"
    else
        return math.floor(diff / 86400) .. " days ago"
    end
end

-- Get current guild store info (trader name, guild name, location)
function Megastore.GetCurrentStoreInfo()
    local storeInfo = {
        traderName = "",
        guildName = "",
        location = "",
        zone = ""
    }
    
    local interactionType = GetInteractionType and GetInteractionType()
    MegaPrint("Current interaction type: " .. tostring(interactionType), true)
    
    if interactionType == INTERACTION_TRADING_HOUSE then
        MegaPrint("At trading house, trying to get guild info...", true)
        
        -- Method 1: Try GetTradingHouseGuildDetails
        if type(GetTradingHouseGuildDetails) == "function" then
            local guildId, guildName = GetTradingHouseGuildDetails()
            MegaPrint("GetTradingHouseGuildDetails returned: guildId=" .. tostring(guildId) .. ", guildName=" .. tostring(guildName), true)
            if guildName and guildName ~= "" then
                storeInfo.guildName = guildName
                MegaPrint("Got guild name from GetTradingHouseGuildDetails: " .. guildName, true)
            end
        else
            MegaPrint("GetTradingHouseGuildDetails function not available", true)
        end
        
        -- Method 2: Try GetGuildStoreInfo (fallback)
        if storeInfo.guildName == "" and type(GetGuildStoreInfo) == "function" then
            local guildId, guildName = GetGuildStoreInfo()
            MegaPrint("GetGuildStoreInfo returned: guildId=" .. tostring(guildId) .. ", guildName=" .. tostring(guildName), true)
            if guildName and guildName ~= "" then
                storeInfo.guildName = guildName
                MegaPrint("Got guild name from GetGuildStoreInfo: " .. guildName, true)
            end
        else
            if storeInfo.guildName == "" then
                MegaPrint("GetGuildStoreInfo function not available", true)
            end
        end
        
        -- Method 3: If no guild name yet, create a fallback based on location
        if storeInfo.guildName == "" then
            MegaPrint("Could not determine guild name from API, creating fallback.", true)
            local location = ""
            if type(GetPlayerLocationName) == "function" then
                location = GetPlayerLocationName() or ""
            end
            if location == "" and type(GetMapName) == "function" then
                location = GetMapName() or ""
            end
            
            if location and location ~= "" then
                storeInfo.guildName = "Store at " .. location
                MegaPrint("Using location-based guild name: " .. storeInfo.guildName, true)
            else
                -- Last resort - use a timestamp-based name
                storeInfo.guildName = "Guild Store " .. GetCurrentTime()
                MegaPrint("Using timestamp-based guild name: " .. storeInfo.guildName, true)
            end
        end
        
        -- Get current location info
        if type(GetUnitZone) == "function" then
            storeInfo.zone = GetUnitZone("player") or GetZoneText and GetZoneText() or "Unknown Zone"
        end
        
        if type(GetPlayerLocationName) == "function" then
            storeInfo.location = GetPlayerLocationName() or "Unknown Location"
        elseif type(GetMapName) == "function" then
            storeInfo.location = GetMapName() or "Unknown Location"
        end
        
        -- Try to get trader name from interaction target
        if type(GetInteractionTargetName) == "function" then
            storeInfo.traderName = GetInteractionTargetName() or "Unknown Trader"
        end
        
        MegaPrint("Store info collected - Guild: " .. storeInfo.guildName .. ", Location: " .. storeInfo.location, true)
    else
        MegaPrint("Not at a trading house. Interaction type: " .. tostring(interactionType), true)
    end
    
    return storeInfo
end

-- Scan current guild store and collect all item data
function Megastore.ScanCurrentStore(numItemsToScan, callback)
    -- This function now assumes it's being called when a scan is ready to proceed.
    -- It no longer triggers searches or waits.

    local storeInfo = Megastore.GetCurrentStoreInfo()
    MegaPrint("Store info for scan: Guild='" .. tostring(storeInfo.guildName) .. "', Location='" .. tostring(storeInfo.location) .. "'", true)

    if not storeInfo.guildName or storeInfo.guildName == "" then
        MegaPrint("Scan aborted: Could not get valid store information.", true)
        if callback then callback(0) end
        return
    end

    MegaPrint("Scanning store: " .. storeInfo.guildName .. " at " .. storeInfo.location, true)

    local storeKey = storeInfo.guildName .. "|" .. storeInfo.location
    local timestamp = GetCurrentTime()

    if not Megastore.database.guildStores[storeKey] then
        Megastore.database.guildStores[storeKey] = { items = {}, info = storeInfo }
    end

    -- Always update info and clear old items for a fresh scan
    Megastore.database.guildStores[storeKey].info = storeInfo
    Megastore.database.guildStores[storeKey].items = {}
    Megastore.database.guildStores[storeKey].lastScan = timestamp

    local numItems = numItemsToScan or 0
    MegaPrint("[Megastore Debug] Starting scan of Browse tab search results for " .. numItems .. " items.", true)

    if numItems == 0 then
        MegaPrint("[Megastore Debug] No search result items to scan.", true)
        if callback then callback(0) end
        return
    end
    
    -- Collect all items
    local itemsCollected = 0
    for i = 1, numItems do
        local itemData = Megastore.GetItemDataAtIndex(i)
        if itemData then
            itemsCollected = itemsCollected + 1
            -- Add to store inventory
            table.insert(Megastore.database.guildStores[storeKey].items, itemData)
            
            -- Index by item name for searching
            local itemName = itemData.name:lower()
            if not Megastore.database.itemIndex[itemName] then
                Megastore.database.itemIndex[itemName] = {}
            end
            
            table.insert(Megastore.database.itemIndex[itemName], {
                storeKey = storeKey,
                storeInfo = storeInfo,
                itemData = itemData,
                timestamp = timestamp
            })
        end
    end

    MegaPrint("[Megastore Debug] Scan complete! Collected " .. itemsCollected .. " of " .. numItems .. " potential items.", false)
    
    -- Save data
    Megastore.SaveData()
    
    if callback then
        callback(itemsCollected)
        return
    end
    -- Show completion notification (legacy/manual scan)
    if itemsCollected > 0 then
        Megastore.ShowStatusNotification("Scan complete! Found " .. itemsCollected .. " items", false)
        MegaPrint("Megastore updated", false)
    else
        Megastore.ShowStatusNotification("Scan complete - no items found", false)
    end
end

-- Get item data at a specific trading house index
function Megastore.GetItemDataAtIndex(index)
    local itemData = {}
    
    -- Debug: Check if the API function exists (for Browse tab search results)
    if not GetTradingHouseSearchResultItemInfo then
        MegaPrint("[Megastore Debug] GetTradingHouseSearchResultItemInfo function not available", true)
        return nil
    end
    
    -- Try to get item information using search results APIs (Browse tab)
    local icon, itemName, displayQuality, stackCount, sellerName, timeRemaining, purchasePrice = GetTradingHouseSearchResultItemInfo(index)
    
    -- Debug: Log what we got
    MegaPrint("[Megastore Debug] Search Result " .. index .. ": name='" .. tostring(itemName) .. "', price=" .. tostring(purchasePrice), true)
    
    if itemName and itemName ~= "" then
        itemData.name = itemName
        itemData.icon = icon or ""
        itemData.quality = displayQuality or 1
        itemData.stackCount = stackCount or 1
        itemData.seller = sellerName or "Unknown"
        itemData.price = purchasePrice or 0
        itemData.timeRemaining = timeRemaining or 0
        
        -- Try to get item link for more detailed info (Browse tab)
        if type(GetTradingHouseSearchResultItemLink) == "function" then
            itemData.link = GetTradingHouseSearchResultItemLink(index) or ""
        end
        
        return itemData
    else
        MegaPrint("[Megastore Debug] Search Result " .. index .. " has no name or empty name", true)
    end
    
    return nil
end

-- Search for items across all cached stores
function Megastore.SearchItems(searchTerm)
    local results = {}
    local searchLower = searchTerm:lower()
    
    MegaPrint("Searching for: " .. searchTerm, true)
    
    -- Search through item index
    for itemName, locations in pairs(Megastore.database.itemIndex) do
        if itemName:find(searchLower, 1, true) then
            for _, location in ipairs(locations) do
                -- Check if data is not too old
                local age = GetCurrentTime() - location.timestamp
                if age <= Megastore.database.settings.maxAge then
                    table.insert(results, {
                        itemName = location.itemData.name,
                        link = location.itemData.link,
                        price = location.itemData.price,
                        seller = location.itemData.seller,
                        guild = location.storeInfo.guildName,
                        location = location.storeInfo.location,
                        zone = location.storeInfo.zone,
                        age = FormatTimeDiff(location.timestamp),
                        quality = location.itemData.quality,
                        equipType = location.itemData.equipType or Megastore.GetItemEquipTypeFromName(location.itemData.name)
                    })
                end
            end
        end
    end
    
    -- Sort results by price (ascending)
    table.sort(results, function(a, b) return a.price < b.price end)
    
    return results
end

-- Display search results in guild store style UI
function Megastore.DisplaySearchResults(results, searchTerm)
    Megastore.ShowMegastoreUI(results, searchTerm)
end

-- Create the main Megastore UI window (guild store style)
function Megastore.ShowMegastoreUI(results, searchTerm)
    if not WINDOW_MANAGER then
        MegaPrint("Error: WINDOW_MANAGER not available")
        return
    end
    
    -- Create main window if it doesn't exist
    if not Megastore.ui or not Megastore.ui.window then
        Megastore.CreateMainUI()
    end
    
    -- Update the results display
    if results then
        Megastore.UpdateResultsList(results, searchTerm)
    end
    
    -- Show the window
    Megastore.ui.window:SetHidden(false)
    Megastore.ui.window:BringWindowToTop()
end

-- Create the main UI elements (guild store style)
function Megastore.CreateMainUI()
    local wm = WINDOW_MANAGER
    
    -- Initialize UI table
    Megastore.ui = {
        controls = {},
        currentResults = {},
        currentPage = 1,
        itemsPerPage = 20
    }
    
    -- Main window
    local window = wm:CreateTopLevelWindow("MegastoreWindow")
    window:SetDimensions(1000, 700)
    window:SetAnchor(CENTER, GuiRoot, CENTER, 0, 0)
    window:SetMovable(true)
    window:SetMouseEnabled(true)
    window:SetClampedToScreen(true)
    window:SetHidden(true)
    Megastore.ui.window = window
    
    -- Background
    local bg = wm:CreateControl("$(parent)BG", window, CT_BACKDROP)
    bg:SetAnchorFill(window)
    bg:SetCenterColor(0.05, 0.05, 0.05, 0.95)
    bg:SetEdgeColor(0.3, 0.3, 0.3, 1)
    bg:SetEdgeTexture("", 8, 1, 1)
    
    -- Title bar
    local titleBar = wm:CreateControl("$(parent)TitleBar", window, CT_BACKDROP)
    titleBar:SetDimensions(1000, 40)
    titleBar:SetAnchor(TOP, window, TOP, 0, 0)
    titleBar:SetCenterColor(0.1, 0.1, 0.15, 1)
    titleBar:SetEdgeColor(0.4, 0.4, 0.5, 1)
    titleBar:SetEdgeTexture("", 2, 1, 1)
    
    -- Title text
    local title = wm:CreateControl("$(parent)Title", titleBar, CT_LABEL)
    title:SetAnchor(LEFT, titleBar, LEFT, 20, 0)
    title:SetFont("ZoFontWinH1")
    title:SetText("MEGASTORE")
    title:SetColor(1, 0.8, 0.2, 1)
    
    -- Browse button (top right)
    local browseBtn = wm:CreateControl("$(parent)Browse", titleBar, CT_BUTTON)
    browseBtn:SetDimensions(80, 30)
    browseBtn:SetAnchor(RIGHT, titleBar, RIGHT, -90, 5)
    browseBtn:SetText("BROWSE")
    browseBtn:SetFont("ZoFontWinH4")
    browseBtn:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    
    -- Close button
    local closeBtn = wm:CreateControl("$(parent)Close", titleBar, CT_BUTTON)
    closeBtn:SetDimensions(30, 30)
    closeBtn:SetAnchor(RIGHT, titleBar, RIGHT, -5, 5)
    closeBtn:SetText("X")
    closeBtn:SetFont("ZoFontWinH3")
    closeBtn:SetNormalFontColor(0.8, 0.4, 0.4, 1)
    closeBtn:SetHandler("OnClicked", function()
        window:SetHidden(true)
    end)
    
    -- Search box area
    local searchArea = wm:CreateControl("$(parent)SearchArea", window, CT_BACKDROP)
    searchArea:SetDimensions(400, 35)
    searchArea:SetAnchor(TOPRIGHT, window, TOPRIGHT, -20, 60)
    searchArea:SetCenterColor(0.1, 0.1, 0.1, 0.8)
    searchArea:SetEdgeColor(0.4, 0.4, 0.4, 1)
    searchArea:SetEdgeTexture("", 2, 1, 1)
    
    -- Search input (functional edit box)
    local searchInput = wm:CreateControlFromVirtual("$(parent)SearchInput", searchArea, "ZO_DefaultEditForBackdrop")
    searchInput:SetAnchor(TOPLEFT, searchArea, TOPLEFT, 10, 5)
    searchInput:SetDimensions(300, 25)
    searchInput:SetFont("ZoFontGame")
    searchInput:SetText("")
    
    -- Set placeholder text
    local searchLabel = wm:CreateControl("$(parent)SearchLabel", searchArea, CT_LABEL)
    searchLabel:SetAnchor(LEFT, searchInput, LEFT, 5, 0)
    searchLabel:SetFont("ZoFontGame")
    searchLabel:SetText("Search items... (2+ chars)")
    searchLabel:SetColor(0.6, 0.6, 0.6, 1)
    
    -- Hide placeholder when typing
    searchInput:SetHandler("OnTextChanged", function()
        local text = searchInput:GetText()
        if text and text ~= "" then
            searchLabel:SetHidden(true)
        else
            searchLabel:SetHidden(false)
        end
        
        -- Auto-search when typing (with small delay to avoid excessive searches)
        if Megastore.searchTimer then
            EVENT_MANAGER:UnregisterForUpdate("MegastoreSearch")
        end
        EVENT_MANAGER:RegisterForUpdate("MegastoreSearch", 800, function()
            EVENT_MANAGER:UnregisterForUpdate("MegastoreSearch")
            if text and text:len() >= 2 then
                Megastore.PerformSearch(text)
            elseif text == "" then
                Megastore.ShowAllItems()
            end
        end)
    end)
    
    -- Search on Enter key
    searchInput:SetHandler("OnEnter", function()
        local text = searchInput:GetText()
        if text and text ~= "" then
            Megastore.PerformSearch(text)
        end
    end)
    
    -- Clear on Escape key
    searchInput:SetHandler("OnEscape", function()
        searchInput:SetText("")
        searchLabel:SetHidden(false)
        Megastore.ShowAllItems()
    end)
    
    -- Search button
    local searchBtn = wm:CreateControl("$(parent)SearchBtn", searchArea, CT_BUTTON)
    searchBtn:SetDimensions(50, 25)
    searchBtn:SetAnchor(RIGHT, searchArea, RIGHT, -70, 5)
    searchBtn:SetText("Search")
    searchBtn:SetFont("ZoFontGame")
    searchBtn:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    searchBtn:SetHandler("OnClicked", function()
        local text = searchInput:GetText()
        if text and text ~= "" then
            Megastore.PerformSearch(text)
        end
    end)
    
    -- Clear button
    local clearBtn = wm:CreateControl("$(parent)ClearBtn", searchArea, CT_BUTTON)
    clearBtn:SetDimensions(50, 25)
    clearBtn:SetAnchor(RIGHT, searchArea, RIGHT, -10, 5)
    clearBtn:SetText("Clear")
    clearBtn:SetFont("ZoFontGame")
    clearBtn:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    clearBtn:SetHandler("OnClicked", function()
        searchInput:SetText("")
        searchLabel:SetHidden(false)
        Megastore.ShowAllItems()
    end)
    
    Megastore.ui.searchInput = searchInput
    Megastore.ui.searchLabel = searchLabel
    Megastore.ui.searchBtn = searchBtn
    Megastore.ui.clearBtn = clearBtn
    
    -- Left panel for categories
    local leftPanel = wm:CreateControl("$(parent)LeftPanel", window, CT_BACKDROP)
    leftPanel:SetDimensions(300, 580)
    leftPanel:SetAnchor(TOPLEFT, window, TOPLEFT, 20, 110)
    leftPanel:SetCenterColor(0.08, 0.08, 0.1, 0.9)
    leftPanel:SetEdgeColor(0.3, 0.3, 0.3, 1)
    leftPanel:SetEdgeTexture("", 2, 1, 1)
    
    -- Category buttons
    local categories = {
        {icon = "👑", text = "ALL ITEMS", filter = "all"},
        {icon = "⚔️", text = "WEAPONS", filter = "weapons"},
        {icon = "🛡️", text = "APPAREL", filter = "apparel"},
        {icon = "💍", text = "JEWELRY", filter = "jewelry"},
        {icon = "🍎", text = "CONSUMABLES", filter = "consumables"},
        {icon = "🔨", text = "MATERIALS", filter = "materials"},
        {icon = "📜", text = "GLYPHS", filter = "glyphs"},
        {icon = "🏠", text = "FURNISHINGS", filter = "furnishings"},
        {icon = "🎭", text = "MISCELLANEOUS", filter = "misc"}
    }
    
    for i, category in ipairs(categories) do
        local categoryBtn = wm:CreateControl("$(parent)Category" .. i, leftPanel, CT_BUTTON)
        categoryBtn:SetDimensions(280, 35)
        categoryBtn:SetAnchor(TOPLEFT, leftPanel, TOPLEFT, 10, 10 + (i-1) * 40)
        categoryBtn:SetText(category.icon .. " " .. category.text)
        categoryBtn:SetFont("ZoFontWinH4")
        categoryBtn:SetHorizontalAlignment(TEXT_ALIGN_LEFT)
        categoryBtn:SetNormalFontColor(0.8, 0.8, 0.8, 1)
        categoryBtn:SetMouseOverFontColor(1, 1, 0.6, 1)
        
        -- Category button background
        local categoryBG = wm:CreateControl("$(parent)BG", categoryBtn, CT_BACKDROP)
        categoryBG:SetAnchorFill(categoryBtn)
        categoryBG:SetCenterColor(0, 0, 0, 0)
        categoryBG:SetEdgeTexture("", 1, 1, 1)
        
        -- Track selected category
        categoryBtn.isSelected = (category.filter == "all")
        categoryBtn.filter = category.filter
        
        -- Update appearance for selected category
        local function updateCategoryAppearance()
            if categoryBtn.isSelected then
                categoryBG:SetCenterColor(0.2, 0.2, 0.3, 0.9)
                categoryBtn:SetNormalFontColor(1, 1, 0.6, 1)
            else
                categoryBG:SetCenterColor(0, 0, 0, 0)
                categoryBtn:SetNormalFontColor(0.8, 0.8, 0.8, 1)
            end
        end
        
        updateCategoryAppearance()
        
        categoryBtn:SetHandler("OnMouseEnter", function()
            if not categoryBtn.isSelected then
                categoryBG:SetCenterColor(0.15, 0.15, 0.2, 0.8)
            end
        end)
        categoryBtn:SetHandler("OnMouseExit", function()
            updateCategoryAppearance()
        end)
        categoryBtn:SetHandler("OnClicked", function()
            Megastore.SelectCategory(category.filter, categoryBtn)
        end)
        
        -- Store reference to category buttons
        if not Megastore.ui.categoryButtons then
            Megastore.ui.categoryButtons = {}
        end
        Megastore.ui.categoryButtons[category.filter] = categoryBtn
    end
    
    -- Quality filter (bottom left)
    local qualityArea = wm:CreateControl("$(parent)QualityArea", leftPanel, CT_BACKDROP)
    qualityArea:SetDimensions(280, 60)
    qualityArea:SetAnchor(BOTTOMLEFT, leftPanel, BOTTOMLEFT, 10, -10)
    qualityArea:SetCenterColor(0.1, 0.1, 0.1, 0.8)
    qualityArea:SetEdgeColor(0.4, 0.4, 0.4, 1)
    qualityArea:SetEdgeTexture("", 2, 1, 1)
    
    local qualityLabel = wm:CreateControl("$(parent)QualityLabel", qualityArea, CT_LABEL)
    qualityLabel:SetAnchor(LEFT, qualityArea, LEFT, 10, -10)
    qualityLabel:SetFont("ZoFontGame")
    qualityLabel:SetText("Any Quality")
    qualityLabel:SetColor(0.8, 0.8, 0.8, 1)
    
    -- Category status label
    local categoryStatus = wm:CreateControl("$(parent)CategoryStatus", qualityArea, CT_LABEL)
    categoryStatus:SetAnchor(LEFT, qualityArea, LEFT, 10, 10)
    categoryStatus:SetFont("ZoFontGame")
    categoryStatus:SetText("Filter: All Items")
    categoryStatus:SetColor(0.6, 0.9, 0.6, 1)
    Megastore.ui.categoryStatus = categoryStatus
    
    -- Main results area
    local resultsArea = wm:CreateControl("$(parent)ResultsArea", window, CT_BACKDROP)
    resultsArea:SetDimensions(650, 520)
    resultsArea:SetAnchor(TOPLEFT, leftPanel, TOPRIGHT, 20, 0)
    resultsArea:SetCenterColor(0.05, 0.05, 0.05, 0.9)
    resultsArea:SetEdgeColor(0.3, 0.3, 0.3, 1)
    resultsArea:SetEdgeTexture("", 2, 1, 1)
    Megastore.ui.resultsArea = resultsArea
    
    -- Column headers
    local headerArea = wm:CreateControl("$(parent)Headers", resultsArea, CT_BACKDROP)
    headerArea:SetDimensions(630, 30)
    headerArea:SetAnchor(TOP, resultsArea, TOP, 0, 10)
    headerArea:SetCenterColor(0.1, 0.1, 0.15, 1)
    headerArea:SetEdgeColor(0.4, 0.4, 0.5, 1)
    headerArea:SetEdgeTexture("", 1, 1, 1)
    
    -- Header labels
    local headers = {
        {text = "ITEM", x = 20, width = 300},
        {text = "LOCATION", x = 330, width = 120},
        {text = "GUILD", x = 460, width = 100},
        {text = "PRICE", x = 570, width = 60}
    }
    
    for _, header in ipairs(headers) do
        local headerLabel = wm:CreateControl(nil, headerArea, CT_LABEL)
        headerLabel:SetAnchor(LEFT, headerArea, LEFT, header.x, 0)
        headerLabel:SetFont("ZoFontWinH5")
        headerLabel:SetText(header.text)
        headerLabel:SetColor(0.9, 0.9, 0.9, 1)
    end
    
    -- Results scroll area
    local scrollArea = wm:CreateControl("$(parent)ScrollArea", resultsArea, CT_SCROLL)
    scrollArea:SetDimensions(630, 420)
    scrollArea:SetAnchor(TOP, headerArea, BOTTOM, 0, 10)
    Megastore.ui.scrollArea = scrollArea
    
    -- Scroll content
    local scrollContent = wm:CreateControl("$(parent)Content", scrollArea, CT_CONTROL)
    scrollContent:SetResizeToFitDescendents(true)
    scrollContent:SetAnchor(TOPLEFT, scrollArea, TOPLEFT, 0, 0)
    Megastore.ui.scrollContent = scrollContent
    
    -- Pagination area
    local paginationArea = wm:CreateControl("$(parent)Pagination", resultsArea, CT_BACKDROP)
    paginationArea:SetDimensions(630, 40)
    paginationArea:SetAnchor(BOTTOM, resultsArea, BOTTOM, 0, -10)
    paginationArea:SetCenterColor(0.1, 0.1, 0.15, 1)
    paginationArea:SetEdgeColor(0.4, 0.4, 0.5, 1)
    paginationArea:SetEdgeTexture("", 1, 1, 1)
    
    -- Pagination controls
    local prevBtn = wm:CreateControl("$(parent)Prev", paginationArea, CT_BUTTON)
    prevBtn:SetDimensions(80, 25)
    prevBtn:SetAnchor(LEFT, paginationArea, LEFT, 20, 0)
    prevBtn:SetText("Previous")
    prevBtn:SetFont("ZoFontGame")
    prevBtn:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    
    local nextBtn = wm:CreateControl("$(parent)Next", paginationArea, CT_BUTTON)
    nextBtn:SetDimensions(80, 25)
    nextBtn:SetAnchor(RIGHT, paginationArea, RIGHT, -20, 0)
    nextBtn:SetText("Next")
    nextBtn:SetFont("ZoFontGame")
    nextBtn:SetNormalFontColor(0.8, 0.8, 0.8, 1)
    
    local pageInfo = wm:CreateControl("$(parent)PageInfo", paginationArea, CT_LABEL)
    pageInfo:SetAnchor(CENTER, paginationArea, CENTER, 0, 0)
    pageInfo:SetFont("ZoFontGame")
    pageInfo:SetText("Items On Page: 0")
    pageInfo:SetColor(0.8, 0.8, 0.8, 1)
    Megastore.ui.pageInfo = pageInfo
    
    -- Store references
    Megastore.ui.prevBtn = prevBtn
    Megastore.ui.nextBtn = nextBtn
    
    MegaPrint("Megastore UI created successfully!")
end

-- Update the results list display
function Megastore.UpdateResultsList(results, searchTerm)
    if not Megastore.ui or not Megastore.ui.scrollContent then
        return
    end
    
    -- Generate unique ID for this update
    if not Megastore.ui.updateCounter then
        Megastore.ui.updateCounter = 0
    end
    Megastore.ui.updateCounter = Megastore.ui.updateCounter + 1
    local updateId = Megastore.ui.updateCounter
    
    -- Clear existing results
    if Megastore.ui.resultControls then
        for _, control in ipairs(Megastore.ui.resultControls) do
            if control and control.SetParent then
                control:SetParent(nil)
                control:SetHidden(true)
                -- Clear anchors to fully disconnect
                if control.ClearAnchors then
                    control:ClearAnchors()
                end
            end
        end
    end
    Megastore.ui.resultControls = {}
    
    local wm = WINDOW_MANAGER
    local scrollContent = Megastore.ui.scrollContent
    
    if #results == 0 then
        -- Show "no results" message with unique name
        local noResults = wm:CreateControl("MegastoreNoResults_" .. updateId, scrollContent, CT_LABEL)
        noResults:SetAnchor(CENTER, scrollContent, CENTER, 0, 50)
        noResults:SetFont("ZoFontWinH2")
        noResults:SetText("No results found" .. (searchTerm and (" for: " .. searchTerm) or ""))
        noResults:SetColor(0.7, 0.7, 0.7, 1)
        table.insert(Megastore.ui.resultControls, noResults)
        
        -- Update page info
        Megastore.ui.pageInfo:SetText("Items On Page: 0")
        return
    end
    
    -- Calculate pagination
    local itemsPerPage = Megastore.ui.itemsPerPage
    local totalPages = math.ceil(#results / itemsPerPage)
    local currentPage = math.min(Megastore.ui.currentPage, totalPages)
    local startIndex = (currentPage - 1) * itemsPerPage + 1
    local endIndex = math.min(startIndex + itemsPerPage - 1, #results)
    
    -- Create result rows
    for i = startIndex, endIndex do
        local result = results[i]
        local yOffset = (i - startIndex) * 35
        
        -- Row background with unique name
        local rowBG = wm:CreateControl("MegastoreRow_" .. updateId .. "_" .. i, scrollContent, CT_BACKDROP)
        rowBG:SetDimensions(620, 30)
        rowBG:SetAnchor(TOPLEFT, scrollContent, TOPLEFT, 5, yOffset)
        rowBG:SetCenterColor(0, 0, 0, 0)
        rowBG:SetEdgeTexture("", 1, 1, 1)
        table.insert(Megastore.ui.resultControls, rowBG)
        
        -- Item name
        local itemLabel = wm:CreateControl("$(parent)Item", rowBG, CT_LABEL)
        itemLabel:SetAnchor(LEFT, rowBG, LEFT, 15, 0)
        itemLabel:SetFont("ZoFontGame")
        itemLabel:SetText(result.itemName or "Unknown Item")
        itemLabel:SetColor(Megastore.GetQualityColor(result.quality))
        
        -- Location
        local locationLabel = wm:CreateControl("$(parent)Location", rowBG, CT_LABEL)
        locationLabel:SetAnchor(LEFT, rowBG, LEFT, 325, 0)
        locationLabel:SetFont("ZoFontGame")
        locationLabel:SetText(result.location or "Unknown")
        locationLabel:SetColor(0.8, 0.8, 0.8, 1)
        
        -- Guild name
        local guildLabel = wm:CreateControl("$(parent)Guild", rowBG, CT_LABEL)
        guildLabel:SetAnchor(LEFT, rowBG, LEFT, 455, 0)
        guildLabel:SetFont("ZoFontGame")
        guildLabel:SetText(result.guild or "Unknown Guild")
        guildLabel:SetColor(0.7, 0.9, 0.7, 1)
        
        -- Price
        local priceLabel = wm:CreateControl("$(parent)Price", rowBG, CT_LABEL)
        priceLabel:SetAnchor(LEFT, rowBG, LEFT, 565, 0)
        priceLabel:SetFont("ZoFontGame")
        local priceText = result.price > 0 and (result.price .. "g") or "Free"
        priceLabel:SetText(priceText)
        priceLabel:SetColor(1, 0.8, 0.2, 1)
        
        -- Row hover effect
        rowBG:SetMouseEnabled(true)
        rowBG:SetHandler("OnMouseEnter", function()
            rowBG:SetCenterColor(0.15, 0.15, 0.2, 0.8)
        end)
        rowBG:SetHandler("OnMouseExit", function()
            rowBG:SetCenterColor(0, 0, 0, 0)
        end)
        
        -- Click handler for more info
        rowBG:SetHandler("OnClicked", function()
            Megastore.ShowItemDetails(result)
        end)
    end
    
    -- Update pagination
    local itemsShown = endIndex - startIndex + 1
    Megastore.ui.pageInfo:SetText("Items On Page: " .. itemsShown .. " | Page " .. currentPage .. " of " .. totalPages)
    
    -- Update pagination buttons
    Megastore.ui.prevBtn:SetHandler("OnClicked", function()
        if currentPage > 1 then
            Megastore.ui.currentPage = currentPage - 1
            Megastore.UpdateResultsList(results, searchTerm)
        end
    end)
    
    Megastore.ui.nextBtn:SetHandler("OnClicked", function()
        if currentPage < totalPages then
            Megastore.ui.currentPage = currentPage + 1
            Megastore.UpdateResultsList(results, searchTerm)
        end
    end)
end

-- Get quality color for item display
function Megastore.GetQualityColor(quality)
    local colors = {
        [0] = {0.5, 0.5, 0.5, 1},   -- Trash (gray)
        [1] = {1, 1, 1, 1},         -- Normal (white)
        [2] = {0.2, 1, 0.2, 1},     -- Fine (green)
        [3] = {0.2, 0.6, 1, 1},     -- Superior (blue)
        [4] = {0.6, 0.2, 1, 1},     -- Epic (purple)
        [5] = {1, 0.8, 0.2, 1}      -- Legendary (gold)
    }
    
    local color = colors[quality] or colors[1]
    return color[1], color[2], color[3], color[4]
end

-- Show detailed item information
function Megastore.ShowItemDetails(result)
    MegaPrint("=== ITEM DETAILS ===")
    MegaPrint("Item: " .. (result.itemName or "Unknown"))
    MegaPrint("Guild: " .. (result.guild or "Unknown Guild"))
    MegaPrint("Location: " .. (result.location or "Unknown Location"))
    MegaPrint("Zone: " .. (result.zone or "Unknown Zone"))
    MegaPrint("Price: " .. (result.price > 0 and (result.price .. " gold") or "Free"))
    MegaPrint("Seller: " .. (result.seller or "Unknown"))
    MegaPrint("Last seen: " .. (result.age or "Unknown"))
    MegaPrint("==================")
end

-- Perform search with current filters
function Megastore.PerformSearch(searchTerm)
    if not Megastore.ui or not Megastore.ui.window then
        return
    end
    
    -- Trim and validate search term
    searchTerm = searchTerm:gsub("^%s+", ""):gsub("%s+$", "")
    if searchTerm == "" then
        Megastore.ShowAllItems()
        return
    end
    
    -- Show searching indicator temporarily
    if Megastore.ui.searchBtn then
        Megastore.ui.searchBtn:SetText("...")
        zo_callLater(function()
            if Megastore.ui.searchBtn then
                Megastore.ui.searchBtn:SetText("Search")
            end
        end, 500)
    end
    
    local results = Megastore.SearchItems(searchTerm)
    
    -- Apply category filter if not "all"
    if Megastore.ui.currentFilter and Megastore.ui.currentFilter ~= "all" then
        results = Megastore.FilterResultsByCategory(results, Megastore.ui.currentFilter)
    end
    
    Megastore.UpdateResultsList(results, searchTerm)
    
    -- Provide feedback about search results
    local categoryText = Megastore.ui.currentFilter and Megastore.ui.currentFilter ~= "all" and (" in " .. Megastore.ui.currentFilter) or ""
    MegaPrint("Search completed: " .. #results .. " results for '" .. searchTerm .. "'" .. categoryText)
end

-- Show all items (no search filter)
function Megastore.ShowAllItems()
    if not Megastore.ui or not Megastore.ui.window then
        return
    end
    
    local allResults = {}
    
    -- Get all items from all stores
    for storeKey, storeData in pairs(Megastore.database.guildStores) do
        for _, itemData in ipairs(storeData.items) do
            -- Check if data is not too old
            local age = GetCurrentTime() - storeData.lastScan
            if age <= Megastore.database.settings.maxAge then
                table.insert(allResults, {
                    itemName = itemData.name,
                    link = itemData.link,
                    price = itemData.price,
                    seller = itemData.seller,
                    guild = storeData.info.guildName,
                    location = storeData.info.location,
                    zone = storeData.info.zone,
                    age = FormatTimeDiff(storeData.lastScan),
                    quality = itemData.quality,
                    equipType = itemData.equipType or "unknown"
                })
            end
        end
    end
    
    -- Apply category filter if not "all"
    if Megastore.ui.currentFilter and Megastore.ui.currentFilter ~= "all" then
        allResults = Megastore.FilterResultsByCategory(allResults, Megastore.ui.currentFilter)
    end
    
    -- Sort by price
    table.sort(allResults, function(a, b) return a.price < b.price end)
    
    Megastore.UpdateResultsList(allResults, "")
end

-- Select a category and update UI
function Megastore.SelectCategory(filter, selectedButton)
    -- Update all category buttons to unselected state
    if Megastore.ui.categoryButtons then
        for filterType, button in pairs(Megastore.ui.categoryButtons) do
            button.isSelected = false
            local bg = button:GetNamedChild("BG")
            if bg then
                bg:SetCenterColor(0, 0, 0, 0)
            end
            button:SetNormalFontColor(0.8, 0.8, 0.8, 1)
        end
    end
    
    -- Mark selected button as active
    selectedButton.isSelected = true
    local selectedBG = selectedButton:GetNamedChild("BG")
    if selectedBG then
        selectedBG:SetCenterColor(0.2, 0.2, 0.3, 0.9)
    end
    selectedButton:SetNormalFontColor(1, 1, 0.6, 1)
    
    -- Store current filter
    Megastore.ui.currentFilter = filter
    
    -- Update category status label
    if Megastore.ui.categoryStatus then
        local filterNames = {
            all = "All Items",
            weapons = "Weapons",
            apparel = "Apparel",
            jewelry = "Jewelry",
            consumables = "Consumables",
            materials = "Materials",
            glyphs = "Glyphs",
            furnishings = "Furnishings",
            misc = "Miscellaneous"
        }
        Megastore.ui.categoryStatus:SetText("Filter: " .. (filterNames[filter] or filter))
    end
    
    -- Apply filter to current results
    local searchText = Megastore.ui.searchInput:GetText()
    if searchText and searchText ~= "" then
        Megastore.PerformSearch(searchText)
    else
        Megastore.ShowAllItems()
    end
    
    MegaPrint("Category filter applied: " .. filter)
end

-- Filter results by category
function Megastore.FilterResultsByCategory(results, filter)
    if filter == "all" then
        return results
    end
    
    local filtered = {}
    
    for _, result in ipairs(results) do
        local includeItem = false
        local equipType = result.equipType or Megastore.GetItemEquipTypeFromName(result.itemName)
        
        if filter == "weapons" then
            includeItem = Megastore.IsWeapon(equipType)
        elseif filter == "apparel" then
            includeItem = Megastore.IsApparel(equipType)
        elseif filter == "jewelry" then
            includeItem = Megastore.IsJewelry(equipType)
        elseif filter == "consumables" then
            includeItem = Megastore.IsConsumable(result.itemName)
        elseif filter == "materials" then
            includeItem = Megastore.IsMaterial(result.itemName)
        elseif filter == "glyphs" then
            includeItem = Megastore.IsGlyph(result.itemName)
        elseif filter == "furnishings" then
            includeItem = Megastore.IsFurnishing(result.itemName)
        elseif filter == "misc" then
            includeItem = Megastore.IsMiscellaneous(equipType, result.itemName)
        end
        
        if includeItem then
            table.insert(filtered, result)
        end
    end
    
    return filtered
end

-- Equipment type checking functions
function Megastore.IsWeapon(equipType)
    return equipType == EQUIP_TYPE_ONE_HAND or 
           equipType == EQUIP_TYPE_TWO_HAND or 
           equipType == EQUIP_TYPE_OFF_HAND or
           equipType == "weapon"
end

function Megastore.IsApparel(equipType)
    return equipType == EQUIP_TYPE_HEAD or
           equipType == EQUIP_TYPE_CHEST or
           equipType == EQUIP_TYPE_SHOULDERS or
           equipType == EQUIP_TYPE_HAND or
           equipType == EQUIP_TYPE_WAIST or
           equipType == EQUIP_TYPE_LEGS or
           equipType == EQUIP_TYPE_FEET or
           equipType == "apparel"
end

function Megastore.IsJewelry(equipType)
    return equipType == EQUIP_TYPE_NECK or
           equipType == EQUIP_TYPE_RING or
           equipType == "jewelry"
end

function Megastore.IsConsumable(itemName)
    local lowerName = itemName:lower()
    return lowerName:find("potion") or 
           lowerName:find("food") or 
           lowerName:find("drink") or
           lowerName:find("elixir") or
           lowerName:find("tonic") or
           lowerName:find("brew") or
           lowerName:find("recipe") or
           lowerName:find("formula") or
           lowerName:find("scroll") or
           lowerName:find("poison") or
           lowerName:find("tea") or
           lowerName:find("wine") or
           lowerName:find("ale") or
           lowerName:find("mead") or
           lowerName:find("soup") or
           lowerName:find("stew") or
           lowerName:find("pie") or
           lowerName:find("cake") or
           lowerName:find("bread")
end

function Megastore.IsMaterial(itemName)
    local lowerName = itemName:lower()
    return lowerName:find("ore") or 
           lowerName:find("ingot") or 
           lowerName:find("wood") or
           lowerName:find("leather") or
           lowerName:find("cloth") or
           lowerName:find("stone") or
           lowerName:find("resin") or
           lowerName:find("silk") or
           lowerName:find("thread") or
           lowerName:find("fiber") or
           lowerName:find("hide") or
           lowerName:find("pelt") or
           lowerName:find("lumber") or
           lowerName:find("plank") or
           lowerName:find("dust") or
           lowerName:find("sanded") or
           lowerName:find("raw") or
           lowerName:find("refined") or
           lowerName:find("hemming") or
           lowerName:find("embroidery") or
           lowerName:find("elegant") or
           lowerName:find("dreugh") or
           lowerName:find("ancestor") or
           lowerName:find("dwemer") or
           lowerName:find("trait")
end

function Megastore.IsGlyph(itemName)
    local lowerName = itemName:lower()
    return lowerName:find("glyph") or 
           lowerName:find("rune") or
           lowerName:find("aspect") or
           lowerName:find("essence") or
           lowerName:find("potency") or
           lowerName:find("ta ") or
           lowerName:find("jejota") or
           lowerName:find("makko") or
           lowerName:find("oko") or
           lowerName:find("kuoko") or
           lowerName:find("pora") or
           lowerName:find("denata") or
           lowerName:find("rekura") or
           lowerName:find("kura") or
           lowerName:find("kude")
end

function Megastore.IsFurnishing(itemName)
    local lowerName = itemName:lower()
    return lowerName:find("furnishing") or 
           lowerName:find("furniture") or
           lowerName:find("blueprint") or
           lowerName:find("pattern") or
           lowerName:find("design") or
           lowerName:find("plan") or
           lowerName:find("diagram") or
           lowerName:find("praxis") or
           lowerName:find("sketch") or
           lowerName:find("chair") or
           lowerName:find("table") or
           lowerName:find("bed") or
           lowerName:find("lamp") or
           lowerName:find("painting") or
           lowerName:find("rug") or
           lowerName:find("tapestry") or
           lowerName:find("statue") or
           lowerName:find("banner") or
           lowerName:find("bookshelf") or
           lowerName:find("candle") or
           lowerName:find("vase") or
           lowerName:find("plant") or
           lowerName:find("tree")
end

function Megastore.IsMiscellaneous(equipType, itemName)
    -- Items that don't fit other categories
    return not (Megastore.IsWeapon(equipType) or 
                Megastore.IsApparel(equipType) or 
                Megastore.IsJewelry(equipType) or
                Megastore.IsConsumable(itemName) or
                Megastore.IsMaterial(itemName) or
                Megastore.IsGlyph(itemName) or
                Megastore.IsFurnishing(itemName))
end

-- Try to determine equipment type from item name (fallback)
function Megastore.GetItemEquipTypeFromName(itemName)
    local lowerName = itemName:lower()
    
    -- Weapons (comprehensive list)
    if lowerName:find("sword") or lowerName:find("axe") or lowerName:find("mace") or 
       lowerName:find("dagger") or lowerName:find("bow") or lowerName:find("staff") or
       lowerName:find("greatsword") or lowerName:find("battleaxe") or lowerName:find("maul") or
       lowerName:find("katana") or lowerName:find("claymore") or lowerName:find("warhammer") or
       lowerName:find("shield") or lowerName:find("blade") or lowerName:find("saber") or
       lowerName:find("crossbow") or lowerName:find("longbow") or lowerName:find("shortbow") then
        return "weapon"
    end
    
    -- Apparel (comprehensive list)
    if lowerName:find("helmet") or lowerName:find("hat") or lowerName:find("cuirass") or
       lowerName:find("robe") or lowerName:find("gloves") or lowerName:find("boots") or
       lowerName:find("greaves") or lowerName:find("pauldron") or lowerName:find("girdle") or
       lowerName:find("armor") or lowerName:find("vest") or lowerName:find("gauntlets") or
       lowerName:find("bracers") or lowerName:find("sabatons") or lowerName:find("jerkin") or
       lowerName:find("doublet") or lowerName:find("breeches") or lowerName:find("shoes") or
       lowerName:find("cap") or lowerName:find("hood") or lowerName:find("mask") or
       lowerName:find("belt") or lowerName:find("sash") or lowerName:find("epaulets") then
        return "apparel"
    end
    
    -- Jewelry
    if lowerName:find("ring") or lowerName:find("necklace") or lowerName:find("amulet") or
       lowerName:find("choker") or lowerName:find("pendant") or lowerName:find("band") or
       lowerName:find("circlet") or lowerName:find("earring") then
        return "jewelry"
    end
    
    return "unknown"
end

-- Clean up old data
function Megastore.CleanupOldData()
    local currentTime = GetCurrentTime()
    local maxAge = Megastore.database.settings.maxAge
    local removedStores = 0
    
    -- Clean up old store data
    for storeKey, storeData in pairs(Megastore.database.guildStores) do
        if currentTime - storeData.lastScan > maxAge then
            Megastore.database.guildStores[storeKey] = nil
            removedStores = removedStores + 1
        end
    end
    
    -- Rebuild item index (remove references to deleted stores)
    Megastore.database.itemIndex = {}
    for storeKey, storeData in pairs(Megastore.database.guildStores) do
        for _, itemData in ipairs(storeData.items) do
            local itemName = itemData.name:lower()
            if not Megastore.database.itemIndex[itemName] then
                Megastore.database.itemIndex[itemName] = {}
            end
            
            table.insert(Megastore.database.itemIndex[itemName], {
                storeKey = storeKey,
                storeInfo = storeData.info,
                itemData = itemData,
                timestamp = storeData.lastScan
            })
        end
    end
    
    if removedStores > 0 then
        MegaPrint("Cleaned up " .. removedStores .. " old store entries", true)
    end
end

-- Data persistence
function Megastore.SaveData()
    if Megastore.savedVars then
        Megastore.savedVars.database = Megastore.database
    end
end

function Megastore.LoadData()
    if Megastore.savedVars and Megastore.savedVars.database then
        -- Merge saved data with defaults
        for key, value in pairs(Megastore.savedVars.database) do
            Megastore.database[key] = value
        end
    end
end

-- Create status notification popup for guild store
function Megastore.CreateStatusNotification()
    if Megastore.statusNotification then
        return -- Already exists
    end
    
    local wm = WINDOW_MANAGER
    
    -- Main notification window (larger to fit buttons)
    local notification = wm:CreateTopLevelWindow("MegastoreStatusNotification")
    notification:SetDimensions(400, 140)
    notification:SetAnchor(TOP, GuiRoot, TOP, 0, 80)
    notification:SetMouseEnabled(true)
    notification:SetMovable(true)
    notification:SetHidden(true)
    
    -- Background
    local bg = wm:CreateControl("$(parent)BG", notification, CT_BACKDROP)
    bg:SetAnchorFill(notification)
    bg:SetCenterColor(0.1, 0.1, 0.2, 0.95)
    bg:SetEdgeColor(0.4, 0.6, 0.8, 1)
    bg:SetEdgeTexture("", 2, 1, 1)
    
    -- Title bar
    local titleBar = wm:CreateControl("$(parent)TitleBar", notification, CT_BACKDROP)
    titleBar:SetDimensions(400, 25)
    titleBar:SetAnchor(TOP, notification, TOP, 0, 0)
    titleBar:SetCenterColor(0.15, 0.15, 0.25, 1)
    titleBar:SetEdgeColor(0.5, 0.5, 0.6, 1)
    titleBar:SetEdgeTexture("", 1, 1, 1)
    
    -- Status text (title)
    local statusText = wm:CreateControl("$(parent)StatusText", titleBar, CT_LABEL)
    statusText:SetAnchor(LEFT, titleBar, LEFT, 10, 0)
    statusText:SetFont("ZoFontWinH4")
    statusText:SetText("MEGASTORE")
    statusText:SetColor(1, 0.8, 0.2, 1)
    
    -- Close button
    local closeBtn = wm:CreateControl("$(parent)Close", titleBar, CT_BUTTON)
    closeBtn:SetDimensions(20, 20)
    closeBtn:SetAnchor(RIGHT, titleBar, RIGHT, -5, 2)
    closeBtn:SetText("X")
    closeBtn:SetFont("ZoFontGame")
    closeBtn:SetNormalFontColor(0.8, 0.4, 0.4, 1)
    closeBtn:SetHandler("OnClicked", function()
        notification:SetHidden(true)
        Megastore.statusNotification.isVisible = false
    end)
    
    -- Progress text
    local progressText = wm:CreateControl("$(parent)ProgressText", notification, CT_LABEL)
    progressText:SetAnchor(CENTER, notification, CENTER, 0, -15)
    progressText:SetFont("ZoFontGame")
    progressText:SetText("Preparing to scan...")
    progressText:SetColor(0.7, 0.8, 0.9, 1)
    
    -- Status info text
    local infoText = wm:CreateControl("$(parent)InfoText", notification, CT_LABEL)
    infoText:SetAnchor(CENTER, notification, CENTER, 0, 5)
    infoText:SetFont("ZoFontGameSmall")
    infoText:SetText("Items found: 0 | Attempts: 0")
    infoText:SetColor(0.6, 0.7, 0.8, 1)
    
    -- Button area
    local buttonArea = wm:CreateControl("$(parent)ButtonArea", notification, CT_CONTROL)
    buttonArea:SetDimensions(380, 30)
    buttonArea:SetAnchor(BOTTOM, notification, BOTTOM, 0, -10)
    
    -- Manual Scan button
    local manualBtn = wm:CreateControl("$(parent)Manual", buttonArea, CT_BUTTON)
    manualBtn:SetDimensions(80, 25)
    manualBtn:SetAnchor(LEFT, buttonArea, LEFT, 20, 0)
    manualBtn:SetText("Manual")
    manualBtn:SetFont("ZoFontGame")
    manualBtn:SetNormalFontColor(0.8, 0.9, 1, 1)
    manualBtn:SetMouseOverFontColor(1, 1, 0.6, 1)
    
    -- Manual button background
    local manualBG = wm:CreateControl("$(parent)BG", manualBtn, CT_BACKDROP)
    manualBG:SetAnchorFill(manualBtn)
    manualBG:SetCenterColor(0.2, 0.3, 0.4, 0.8)
    manualBG:SetEdgeColor(0.4, 0.5, 0.6, 1)
    manualBG:SetEdgeTexture("", 1, 1, 1)
    
    manualBtn:SetHandler("OnClicked", function()
        Megastore.ManualScanFromPopup()
    end)
    
    -- Force button
    local forceBtn = wm:CreateControl("$(parent)Force", buttonArea, CT_BUTTON)
    forceBtn:SetDimensions(80, 25)
    forceBtn:SetAnchor(LEFT, buttonArea, LEFT, 110, 0)
    forceBtn:SetText("Force")
    forceBtn:SetFont("ZoFontGame")
    forceBtn:SetNormalFontColor(1, 0.8, 0.6, 1)
    forceBtn:SetMouseOverFontColor(1, 1, 0.6, 1)
    
    -- Force button background
    local forceBG = wm:CreateControl("$(parent)BG", forceBtn, CT_BACKDROP)
    forceBG:SetAnchorFill(forceBtn)
    forceBG:SetCenterColor(0.4, 0.3, 0.2, 0.8)
    forceBG:SetEdgeColor(0.6, 0.5, 0.4, 1)
    forceBG:SetEdgeTexture("", 1, 1, 1)
    
    forceBtn:SetHandler("OnClicked", function()
        Megastore.ForceScanFromPopup()
    end)
    
    -- Test button
    local testBtn = wm:CreateControl("$(parent)Test", buttonArea, CT_BUTTON)
    testBtn:SetDimensions(80, 25)
    testBtn:SetAnchor(LEFT, buttonArea, LEFT, 200, 0)
    testBtn:SetText("Test")
    testBtn:SetFont("ZoFontGame")
    testBtn:SetNormalFontColor(0.8, 1, 0.8, 1)
    testBtn:SetMouseOverFontColor(1, 1, 0.6, 1)
    
    -- Test button background
    local testBG = wm:CreateControl("$(parent)BG", testBtn, CT_BACKDROP)
    testBG:SetAnchorFill(testBtn)
    testBG:SetCenterColor(0.2, 0.4, 0.2, 0.8)
    testBG:SetEdgeColor(0.4, 0.6, 0.4, 1)
    testBG:SetEdgeTexture("", 1, 1, 1)
    
    testBtn:SetHandler("OnClicked", function()
        Megastore.TestFromPopup()
    end)
    
    -- Disable Auto button
    local disableBtn = wm:CreateControl("$(parent)Disable", buttonArea, CT_BUTTON)
    disableBtn:SetDimensions(80, 25)
    disableBtn:SetAnchor(LEFT, buttonArea, LEFT, 290, 0)
    disableBtn:SetText("Disable")
    disableBtn:SetFont("ZoFontGame")
    disableBtn:SetNormalFontColor(0.8, 0.6, 0.6, 1)
    disableBtn:SetMouseOverFontColor(1, 1, 0.6, 1)
    
    -- Disable button background
    local disableBG = wm:CreateControl("$(parent)BG", disableBtn, CT_BACKDROP)
    disableBG:SetAnchorFill(disableBtn)
    disableBG:SetCenterColor(0.3, 0.2, 0.2, 0.8)
    disableBG:SetEdgeColor(0.5, 0.4, 0.4, 1)
    disableBG:SetEdgeTexture("", 1, 1, 1)
    
    disableBtn:SetHandler("OnClicked", function()
        Megastore.database.settings.autoScan = false
        MegaPrint("Auto-scan disabled. Use /megastore debug to re-enable.", false)
        notification:SetHidden(true)
        Megastore.statusNotification.isVisible = false
    end)
    
    Megastore.statusNotification = {
        window = notification,
        statusText = statusText,
        progressText = progressText,
        infoText = infoText,
        isVisible = false
    }
end

-- Show status notification with message
function Megastore.ShowStatusNotification(message, isScanning)
    if not Megastore.statusNotification then
        Megastore.CreateStatusNotification()
    end
    
    local notification = Megastore.statusNotification
    notification.progressText:SetText(message or "Working...")
    notification.window:SetHidden(false)
    notification.isVisible = true
    
    -- Update info text if available
    if notification.infoText and Megastore.scanData then
        local infoString = "Items found: " .. (Megastore.scanData.lastNumItems or 0) .. " | Attempts: " .. (Megastore.scanData.attempts or 0)
        notification.infoText:SetText(infoString)
    elseif notification.infoText then
        notification.infoText:SetText("Items found: 0 | Attempts: 0")
    end
    
    -- Add a subtle pulsing effect for scanning
    if isScanning then
        notification.window:SetAlpha(1.0)
        -- Create a gentle pulsing animation
        if not notification.pulseTimeline then
            notification.pulseTimeline = ANIMATION_MANAGER:CreateTimeline()
            local pulseAnim = notification.pulseTimeline:InsertAnimation(ANIMATION_ALPHA, notification.window)
            pulseAnim:SetAlphaValues(1.0, 0.6)
            pulseAnim:SetDuration(1000)
            pulseAnim:SetEasingFunction(ZO_EaseInOutQuadratic)
            notification.pulseTimeline:SetPlaybackType(ANIMATION_PLAYBACK_PING_PONG, LOOP_INDEFINITELY)
        end
        notification.pulseTimeline:PlayFromStart()
    else
        -- Stop pulsing for completion messages
        if notification.pulseTimeline then
            notification.pulseTimeline:Stop()
        end
        notification.window:SetAlpha(1.0)
    end
end

-- Hide status notification (only when explicitly called)
function Megastore.HideStatusNotification(delay)
    if not Megastore.statusNotification or not Megastore.statusNotification.isVisible then
        return
    end
    
    local notification = Megastore.statusNotification
    
    local function hide()
        if notification.pulseTimeline then
            notification.pulseTimeline:Stop()
        end
        notification.window:SetHidden(true)
        notification.isVisible = false
    end
    
    -- Only hide with delay if explicitly requested (for backwards compatibility)
    -- Most calls should now use the close button or guild store close event
    if delay and delay > 0 then
        MegaPrint("Auto-hiding popup in " .. delay .. "ms (legacy behavior)", true)
        zo_callLater(hide, delay)
    else
        hide()
    end
end

-- Trigger an "All Items" search to populate the trading house
function Megastore.TriggerAllItemsSearch()
    MegaPrint("Triggering 'All Items' search to populate trading house data...", true)
    local success = false

    -- Try 'r' key simulation first (most reliable method) - multiple attempts
    if type(zo_sendKey) == "function" then
        MegaPrint("Simulating 'r' keypress to trigger All Items search", true)
        
        -- First attempt
        zo_sendKey("r", KEY_DOWN)
        zo_callLater(function() zo_sendKey("r", KEY_UP) end, 50)
        
        -- Second attempt with delay
        zo_callLater(function()
            zo_sendKey("r", KEY_DOWN)
            zo_callLater(function() zo_sendKey("r", KEY_UP) end, 50)
        end, 500)
        
        -- Third attempt with longer delay
        zo_callLater(function()
            zo_sendKey("r", KEY_DOWN)
            zo_callLater(function() zo_sendKey("r", KEY_UP) end, 50)
        end, 1500)
        
        success = true
    end

    -- Try ExecuteTradingHouseSearch as backup with multiple attempts
    if type(ExecuteTradingHouseSearch) == "function" then
        for i = 1, 3 do
            zo_callLater(function()
                pcall(function()
                    ExecuteTradingHouseSearch(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)
                    MegaPrint("ExecuteTradingHouseSearch triggered (attempt " .. i .. ")", true)
                end)
            end, i * 200)
        end
    end

    -- Try StartTradingHouseSearch with multiple attempts
    if type(StartTradingHouseSearch) == "function" then
        for i = 1, 3 do
            zo_callLater(function()
                pcall(function()
                    StartTradingHouseSearch()
                    MegaPrint("StartTradingHouseSearch triggered (attempt " .. i .. ")", true)
                end)
            end, i * 300 + 600)
        end
    end

    -- Try RequestTradingHouseListings with multiple attempts
    if type(RequestTradingHouseListings) == "function" then
        for i = 1, 3 do
            zo_callLater(function()
                pcall(function()
                    RequestTradingHouseListings(1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, false)
                    MegaPrint("RequestTradingHouseListings triggered (attempt " .. i .. ")", true)
                end)
            end, i * 400 + 1200)
        end
    end

    -- Try TRADING_HOUSE.searchAllItems
    if TRADING_HOUSE and type(TRADING_HOUSE.searchAllItems) == "function" then
        for i = 1, 2 do
            zo_callLater(function()
                pcall(function()
                    TRADING_HOUSE.searchAllItems()
                    MegaPrint("TRADING_HOUSE.searchAllItems triggered (attempt " .. i .. ")", true)
                end)
            end, i * 500 + 1800)
        end
    end

    -- Try KEYBIND_STRIP:TriggerKeybind
    if KEYBIND_STRIP and KEYBIND_STRIP.HasKeybindButton and KEYBIND_STRIP:HasKeybindButton("TRADING_HOUSE_SEARCH") then
        zo_callLater(function()
            pcall(function()
                KEYBIND_STRIP:TriggerKeybind("TRADING_HOUSE_SEARCH")
                MegaPrint("KEYBIND_STRIP search triggered", true)
            end)
        end, 2500)
    end

    if not success then
        MegaPrint("Unable to trigger All Items search. Please press 'r' manually.", true)
    end
end

-- Trigger a full scan when opening the guild store and after search results
function Megastore.OnGuildStoreOpened()
    if not Megastore.database.settings.autoScan then return end
    
    -- Reset scanning state
    Megastore.scanData = {
        attempts = 0,
        lastNumItems = 0,
        stableCount = 0,
        scanStarted = false,
        searchTriggered = false,
        waitingForResults = false
    }
    
    Megastore.ShowStatusNotification("Connecting to guild store...", false)
    
    -- Wait for UI to stabilize, then try to trigger search
    zo_callLater(function()
        MegaPrint("[Megastore Debug] Starting search sequence", true)
        
        -- Check if items are already available (some guild stores load immediately)
        local numItems = GetTradingHouseSearchResultNumItems and GetTradingHouseSearchResultNumItems() or 0
        if numItems > 0 then
            MegaPrint("[Megastore Debug] Items already available: " .. numItems, true)
            Megastore.UpdatePopupStatus("Found " .. numItems .. " items!", "Scanning immediately", numItems, 0)
            zo_callLater(function()
                Megastore.ScanCurrentStore(numItems, function(found)
                    Megastore.UpdatePopupStatus("Quick scan complete!", "Found " .. found .. " items", found, 1)
                end)
            end, 500)
            return
        end
        
        -- No items available, trigger search
        Megastore.TriggerAllItemsSearch()
        Megastore.scanData.searchTriggered = true
        Megastore.scanData.waitingForResults = true
        Megastore.ShowStatusNotification("Searching for items...", true)
        
        -- Start polling after a delay to allow search to process
        zo_callLater(function()
            Megastore.StartPollingForItems()
        end, 2000) -- Longer delay to allow search to complete
    end, 1000)
end

-- Start polling for items after search
function Megastore.StartPollingForItems()
    if not Megastore.scanData then return end
    
    local function pollForItems()
        if not Megastore.scanData then return end
        
        Megastore.scanData.attempts = Megastore.scanData.attempts + 1
        local numItems = GetTradingHouseSearchResultNumItems and GetTradingHouseSearchResultNumItems() or 0
        
        MegaPrint("[Megastore Debug] Poll attempt " .. Megastore.scanData.attempts .. ": numItems=" .. tostring(numItems), true)
        
        -- Check if we have items
        if numItems > 0 then
            if not Megastore.scanData.scanStarted then
                -- Check for stable item count
                if numItems == Megastore.scanData.lastNumItems then
                    Megastore.scanData.stableCount = Megastore.scanData.stableCount + 1
                else
                    Megastore.scanData.stableCount = 1
                    Megastore.scanData.lastNumItems = numItems
                end
                
                -- Start scan when count is stable (reduced requirement for faster scanning)
                if Megastore.scanData.stableCount >= 1 then
                    Megastore.scanData.scanStarted = true
                    Megastore.UpdatePopupStatus("Found " .. numItems .. " items!", "Starting scan...", numItems, Megastore.scanData.attempts)
                    
                    zo_callLater(function()
                        Megastore.ScanCurrentStore(numItems, function(found)
                            Megastore.UpdatePopupStatus("Auto-scan complete!", "Found " .. found .. " items", found, Megastore.scanData.attempts)
                            Megastore.scanData = nil -- Clean up
                        end)
                    end, 200)
                    return -- Stop polling
                end
            end
        else
            -- No items found yet
            if Megastore.scanData.attempts == 5 then
                -- Try search again earlier
                MegaPrint("[Megastore Debug] Early retry of search trigger", true)
                Megastore.TriggerAllItemsSearch()
                Megastore.UpdatePopupStatus("Retrying search...", "No items found yet - attempt " .. Megastore.scanData.attempts, 0, Megastore.scanData.attempts)
            elseif Megastore.scanData.attempts >= 10 and Megastore.scanData.attempts % 5 == 0 then
                -- Retry search every 5 attempts after the 10th
                MegaPrint("[Megastore Debug] Retrying search trigger (attempt " .. Megastore.scanData.attempts .. ")", true)
                Megastore.TriggerAllItemsSearch()
                Megastore.UpdatePopupStatus("Still searching...", "Retry " .. math.floor(Megastore.scanData.attempts/5) .. " - use buttons if needed", 0, Megastore.scanData.attempts)
            elseif Megastore.scanData.attempts >= 25 then
                -- Give up after more attempts
                MegaPrint("[Megastore Debug] No items found after " .. Megastore.scanData.attempts .. " attempts. The guild store may be empty.", true)
                Megastore.UpdatePopupStatus("Auto-scan failed", "No items found - try Force button", 0, Megastore.scanData.attempts)
                Megastore.scanData = nil
                return
            end
        end
        
        -- Update popup with current status
        Megastore.UpdatePopupStatus("Searching for items...", "Attempt " .. Megastore.scanData.attempts .. " - found " .. numItems .. " items", numItems, Megastore.scanData.attempts)
        
        -- Continue polling with shorter intervals
        zo_callLater(pollForItems, 1000) -- Reduced polling interval for faster detection
    end
    
    pollForItems()
end
function Megastore.OnGuildStoreClosed() 
    MegaPrint("Guild store closed", true)    -- Try all available API and UI methods in sequence, always falling back to key simulation
    -- Hide notification when closing guild store
    Megastore.HideStatusNotification()
end

-- Initialize addon
function Megastore.Initialize()
    -- Initialize saved variables
    Megastore.savedVars = ZO_SavedVars:NewAccountWide("MegastoreSavedVars", 1, nil, {
        database = Megastore.database
    })
    
    -- Load saved data
    Megastore.LoadData()
    
    -- Register event handlers
    EVENT_MANAGER:RegisterForEvent(Megastore.name, EVENT_OPEN_TRADING_HOUSE, Megastore.OnGuildStoreOpened)
    EVENT_MANAGER:RegisterForEvent(Megastore.name, EVENT_CLOSE_TRADING_HOUSE, Megastore.OnGuildStoreClosed)
    
    -- Register for trading house search result events to detect when items are loaded
    if EVENT_TRADING_HOUSE_RESPONSE_RECEIVED then
        EVENT_MANAGER:RegisterForEvent(Megastore.name, EVENT_TRADING_HOUSE_RESPONSE_RECEIVED, function(event, responseType, result)
            MegaPrint("Trading house search response received: " .. tostring(responseType) .. ", result: " .. tostring(result), true)
            
            -- If scan is in progress and we got a successful response, accelerate polling
            if Megastore.scanData and Megastore.scanData.waitingForResults then
                MegaPrint("[Megastore Debug] Search completed, checking for items...", true)
                Megastore.scanData.waitingForResults = false
                
                -- Check items immediately
                zo_callLater(function()
                    local numItems = GetTradingHouseSearchResultNumItems and GetTradingHouseSearchResultNumItems() or 0
                    if numItems > 0 then
                        MegaPrint("[Megastore Debug] Items now available: " .. numItems, true)
                        Megastore.ShowStatusNotification("Found " .. numItems .. " items!", false)
                    end
                end, 500)
            end
        end)
    end
    
    -- Also register for any trading house list update events
    if EVENT_TRADING_HOUSE_LISTINGS_RECEIVED then
        EVENT_MANAGER:RegisterForEvent(Megastore.name, EVENT_TRADING_HOUSE_LISTINGS_RECEIVED, function()
            MegaPrint("Trading house listings received event", true)
        end)
    end
    
    -- Register slash commands
    SLASH_COMMANDS["/megastore"] = function(args)
        if args == "" then
            Megastore.ShowMegastoreUI()
        elseif args == "ui" then
            Megastore.ShowMegastoreUI()
        elseif args:match("^search%s+(.+)") then
            local searchTerm = args:match("^search%s+(.+)")
            local results = Megastore.SearchItems(searchTerm)
            Megastore.DisplaySearchResults(results, searchTerm)
        elseif args == "stats" then
            local storeCount = 0
            local itemCount = 0
            for _, store in pairs(Megastore.database.guildStores) do
                storeCount = storeCount + 1
                itemCount = itemCount + #store.items
            end
            MegaPrint("Database Statistics:")
            MegaPrint("Stores cached: " .. storeCount)
            MegaPrint("Items tracked: " .. itemCount)
        elseif args == "cleanup" then
            Megastore.CleanupOldData()
            MegaPrint("Data cleanup complete")
        elseif args == "debug" then
            Megastore.database.settings.debugMode = not Megastore.database.settings.debugMode
            MegaPrint("Debug mode: " .. (Megastore.database.settings.debugMode and "ON" or "OFF"))
        elseif args == "info" then
            -- Debug command to show current store info
            MegaPrint("=== CURRENT STATUS ===")
            MegaPrint("Interaction Type: " .. tostring(GetInteractionType()))
            MegaPrint("INTERACTION_TRADING_HOUSE constant: " .. tostring(INTERACTION_TRADING_HOUSE))
            local storeInfo = Megastore.GetCurrentStoreInfo()
            MegaPrint("Guild Name: " .. storeInfo.guildName)
            MegaPrint("Location: " .. storeInfo.location)
            MegaPrint("Zone: " .. storeInfo.zone)
            MegaPrint("Trader: " .. storeInfo.traderName)
            if type(GetTradingHouseSearchResultNumItems) == "function" then
                MegaPrint("Number of search result items: " .. tostring(GetTradingHouseSearchResultNumItems()))
            else
                MegaPrint("GetTradingHouseSearchResultNumItems not available")
            end
            MegaPrint("Auto-scan enabled: " .. tostring(Megastore.database.settings.autoScan))
            MegaPrint("====================")
        elseif args == "scan" then
            -- Manual scan command
            if GetInteractionType() == INTERACTION_TRADING_HOUSE then
                Megastore.ShowStatusNotification("Manual scan initiated...", true)
                zo_callLater(function()
                    -- Temporarily enable auto-scan for this manual scan
                    local wasAutoScan = Megastore.database.settings.autoScan
                    Megastore.database.settings.autoScan = true
                    Megastore.OnGuildStoreOpened() -- Re-trigger the opening logic for a manual scan
                    Megastore.database.settings.autoScan = wasAutoScan
                end, 500)
            else
                MegaPrint("You must be at a guild store to use this command")
                MegaPrint("Current interaction type: " .. tostring(GetInteractionType()))
            end
        elseif args == "test" then
            -- Test API functions for debugging
            MegaPrint("=== API FUNCTION TESTS ===")
            MegaPrint("GetTradingHouseSearchResultNumItems: " .. tostring(type(GetTradingHouseSearchResultNumItems)))
            if GetTradingHouseSearchResultNumItems then
                local numItems = GetTradingHouseSearchResultNumItems()
                MegaPrint("Number of search result items: " .. tostring(numItems))
            end
            MegaPrint("GetTradingHouseSearchResultItemInfo: " .. tostring(type(GetTradingHouseSearchResultItemInfo)))
            MegaPrint("GetTradingHouseSearchResultItemLink: " .. tostring(type(GetTradingHouseSearchResultItemLink)))
            MegaPrint("ExecuteTradingHouseSearch: " .. tostring(type(ExecuteTradingHouseSearch)))
            MegaPrint("StartTradingHouseSearch: " .. tostring(type(StartTradingHouseSearch)))
            MegaPrint("RequestTradingHouseListings: " .. tostring(type(RequestTradingHouseListings)))
            MegaPrint("TRADING_HOUSE object: " .. tostring(type(TRADING_HOUSE)))
            if TRADING_HOUSE and TRADING_HOUSE.searchAllItems then
                MegaPrint("TRADING_HOUSE.searchAllItems: " .. tostring(type(TRADING_HOUSE.searchAllItems)))
            end
            MegaPrint("Current interaction: " .. tostring(GetInteractionType()))
            MegaPrint("INTERACTION_TRADING_HOUSE: " .. tostring(INTERACTION_TRADING_HOUSE))
            
            -- Test getting a few items if available
            if GetTradingHouseSearchResultNumItems then
                local numItems = GetTradingHouseSearchResultNumItems()
                if numItems > 0 then
                    MegaPrint("Testing first few search result items:")
                    for i = 1, math.min(3, numItems) do
                        local itemData = Megastore.GetItemDataAtIndex(i)
                        if itemData then
                            MegaPrint("Search Result " .. i .. ": " .. itemData.name .. " - " .. itemData.price .. "g")
                        else
                            MegaPrint("Search Result " .. i .. ": Failed to get data")
                        end
                    end
                else
                    MegaPrint("No items available for testing")
                end
            end
            MegaPrint("========================")
        elseif args == "force" then
            -- Force a search with all methods
            if GetInteractionType() == INTERACTION_TRADING_HOUSE then
                MegaPrint("=== FORCING SEARCH WITH ALL METHODS ===")
                Megastore.ShowStatusNotification("Force triggering search...", true)
                
                -- Try all search methods aggressively
                Megastore.TriggerAllItemsSearch()
                
                -- Also try manual 'r' key multiple times
                for i = 1, 3 do
                    zo_callLater(function()
                        if type(zo_sendKey) == "function" then
                            MegaPrint("Force 'r' keypress attempt " .. i, true)
                            zo_sendKey("r", KEY_DOWN)
                            zo_callLater(function() zo_sendKey("r", KEY_UP) end, 100)
                        end
                    end, i * 500)
                end
                
                -- Check for results after a delay
                zo_callLater(function()
                    local numItems = GetTradingHouseSearchResultNumItems and GetTradingHouseSearchResultNumItems() or 0
                    MegaPrint("Search result items found after force search: " .. numItems, false)
                    if numItems > 0 then
                        Megastore.ShowStatusNotification("Force search found " .. numItems .. " items!", false)
                        -- Start manual scan
                        zo_callLater(function()
                            Megastore.ScanCurrentStore(numItems, function(found)
                                Megastore.ShowStatusNotification("Force scan complete! Found " .. found .. " items", false)
                                Megastore.HideStatusNotification(4000)
                            end)
                        end, 500)
                    else
                        Megastore.ShowStatusNotification("Force search found no items", false)
                        Megastore.HideStatusNotification(3000)
                    end
                end, 4000)
            else
                MegaPrint("You must be at a guild store to use this command")
            end
        else
            MegaPrint("Megastore Commands:")
            MegaPrint("/megastore - Open Megastore UI")
            MegaPrint("/megastore search <item> - Search for an item")
            MegaPrint("/megastore ui - Open Megastore UI")
            MegaPrint("/megastore scan - Manually scan current guild store")
            MegaPrint("/megastore force - Force search with all methods (if scan fails)")
            MegaPrint("/megastore test - Test API functions (debug)")
            MegaPrint("/megastore info - Show current store info (debug)")
            MegaPrint("/megastore stats - Show database statistics")
            MegaPrint("/megastore cleanup - Clean up old data")
            MegaPrint("/megastore debug - Toggle debug mode")
        end
    end
    
    -- Periodic cleanup (every 30 minutes)
    EVENT_MANAGER:RegisterForUpdate(Megastore.name .. "Cleanup", 1800000, Megastore.CleanupOldData)
    
    MegaPrint("Megastore v" .. Megastore.version .. " loaded! Use /megastore for commands.")
end

-- Register for addon loaded event
local function OnAddOnLoaded(event, addonName)
    if addonName == Megastore.name then
        Megastore.Initialize()
    end
end

EVENT_MANAGER:RegisterForEvent(Megastore.name, EVENT_ADD_ON_LOADED, OnAddOnLoaded)

-- Functions called by popup buttons

-- Manual scan from popup
function Megastore.ManualScanFromPopup()
    if GetInteractionType() ~= INTERACTION_TRADING_HOUSE then
        Megastore.UpdatePopupStatus("Not at a guild store!", "Manual scan failed", 0, 0)
        return
    end
    
    Megastore.UpdatePopupStatus("Manual scan started...", "Checking for items", 0, 0)
    
    -- Cancel any existing scan
    if Megastore.scanData then
        Megastore.scanData = nil
    end
    
    -- Check for items immediately
    local numItems = GetTradingHouseSearchResultNumItems and GetTradingHouseSearchResultNumItems() or 0
    if numItems > 0 then
        Megastore.UpdatePopupStatus("Found " .. numItems .. " items!", "Scanning now", numItems, 1)
        zo_callLater(function()
            Megastore.ScanCurrentStore(numItems, function(found)
                Megastore.UpdatePopupStatus("Manual scan complete", "Found " .. found .. " items", found, 1)
            end)
        end, 500)
    else
        Megastore.UpdatePopupStatus("No items available", "Try Force button if store has items", 0, 1)
    end
end

-- Force scan from popup (aggressive search)
function Megastore.ForceScanFromPopup()
    if GetInteractionType() ~= INTERACTION_TRADING_HOUSE then
        Megastore.UpdatePopupStatus("Not at a guild store!", "Force scan failed", 0, 0)
        return
    end
    
    Megastore.UpdatePopupStatus("Force scan initiated...", "Trying all search methods", 0, 0)
    
    -- Cancel any existing scan
    if Megastore.scanData then
        Megastore.scanData = nil
    end
    
    -- Try all search methods aggressively
    Megastore.TriggerAllItemsSearch()
    
    -- Also try manual 'r' key multiple times
    for i = 1, 5 do
        zo_callLater(function()
            if type(zo_sendKey) == "function" then
                MegaPrint("Force 'r' keypress attempt " .. i, true)
                zo_sendKey("r", KEY_DOWN)
                zo_callLater(function() zo_sendKey("r", KEY_UP) end, 100)
            end
        end, i * 300)
    end
    
    -- Start aggressive polling
    local attemptCount = 0
    local function forcePolling()
        attemptCount = attemptCount + 1
        local numItems = GetTradingHouseSearchResultNumItems and GetTradingHouseSearchResultNumItems() or 0
        
        Megastore.UpdatePopupStatus("Force searching...", "Attempt " .. attemptCount .. " - found " .. numItems .. " items", numItems, attemptCount)
        
        if numItems > 0 then
            Megastore.UpdatePopupStatus("Force scan found items!", "Scanning " .. numItems .. " items", numItems, attemptCount)
            zo_callLater(function()
                Megastore.ScanCurrentStore(numItems, function(found)
                    Megastore.UpdatePopupStatus("Force scan complete", "Found " .. found .. " items", found, attemptCount)
                end)
            end, 500)
            return
        end
        
        if attemptCount < 15 then
            -- Retry search every few attempts
            if attemptCount % 3 == 0 then
                Megastore.TriggerAllItemsSearch()
            end
            zo_callLater(forcePolling, 800)
        else
            Megastore.UpdatePopupStatus("Force scan failed", "No items found after " .. attemptCount .. " attempts", 0, attemptCount)
        end
    end
    
    zo_callLater(forcePolling, 2000)
end

-- Test from popup
function Megastore.TestFromPopup()
    Megastore.UpdatePopupStatus("Running API tests...", "Checking trading house functions", 0, 0)
    
    local testResults = {}
    
    -- Test API functions
    table.insert(testResults, "GetTradingHouseSearchResultNumItems: " .. tostring(type(GetTradingHouseSearchResultNumItems)))
    if GetTradingHouseSearchResultNumItems then
        local numItems = GetTradingHouseSearchResultNumItems()
        table.insert(testResults, "Current search result items: " .. tostring(numItems))
    end
    
    table.insert(testResults, "GetTradingHouseSearchResultItemInfo: " .. tostring(type(GetTradingHouseSearchResultItemInfo)))
    table.insert(testResults, "ExecuteTradingHouseSearch: " .. tostring(type(ExecuteTradingHouseSearch)))
    table.insert(testResults, "StartTradingHouseSearch: " .. tostring(type(StartTradingHouseSearch)))
    table.insert(testResults, "RequestTradingHouseListings: " .. tostring(type(RequestTradingHouseListings)))
    table.insert(testResults, "Current interaction: " .. tostring(GetInteractionType()))
    table.insert(testResults, "INTERACTION_TRADING_HOUSE: " .. tostring(INTERACTION_TRADING_HOUSE))
    
    -- Print all results
    MegaPrint("=== POPUP API TEST RESULTS ===", false)
    for _, result in ipairs(testResults) do
        MegaPrint(result, false)
    end
    MegaPrint("==============================", false)
    
    local numItems = GetTradingHouseSearchResultNumItems and GetTradingHouseSearchResultNumItems() or 0
    Megastore.UpdatePopupStatus("API test complete", "Check chat for details - " .. numItems .. " search results", numItems, 1)
end

-- Update popup status (unified function)
function Megastore.UpdatePopupStatus(mainText, subText, numItems, attempts)
    if not Megastore.statusNotification then
        return
    end
    
    local notification = Megastore.statusNotification
    notification.progressText:SetText(mainText or "Working...")
    
    if notification.infoText then
        local infoString = "Items found: " .. (numItems or 0)
        if attempts and attempts > 0 then
            infoString = infoString .. " | Attempts: " .. attempts
        end
        notification.infoText:SetText(infoString)
    end
    
    -- Make sure popup is visible
    if not notification.isVisible then
        notification.window:SetHidden(false)
        notification.isVisible = true
    end
end

--[[
IMPORTANT API NOTES:
- GetTradingHouseSearchResultNumItems() / GetTradingHouseSearchResultItemInfo() = Browse tab (items for sale by others)
- GetTradingHouseNumItems() / GetTradingHouseListingItemInfo() = Listings tab (your own items you're selling)

We need to use the Search Result APIs to scan items in the Browse tab where users are looking for items to buy.
]]--

-- Megastore - ESO Guild Store Scanner
-- Enhanced addon to scan and store trading house data across multiple guild stores
