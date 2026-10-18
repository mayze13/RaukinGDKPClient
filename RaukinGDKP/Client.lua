local AceGUI = RaukinLibStub("RaukinAceGUI-3.0")
local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

local Client = {}
Client.__index = Client
RaukinGDKP.Client = Client

-- Lua APIs
local pairs, next, setmetatable, tonumber = pairs, next, setmetatable, tonumber
local sort, math = table.sort, math

-- WoW APIs
local C_Timer = RaukinGDKPCompat.C_Timer
local GetServerTime = RaukinGDKPCompat.GetServerTime
local SendSystemMessage = RaukinGDKPCompat.SendSystemMessage

-- Lifecycle

function Client:Create()
  local client = {
    sessions = {},
    activeSession = nil,
    filter = RaukinGDKP.Filter:CreateComposite(),
    classFilter = RaukinGDKP.Filter:CreateForPlayerClassId(RaukinGDKP.playerClass),
    watchedFilter = RaukinGDKP.Filter:CreateForWatched(),
    activeFilter = RaukinGDKP.Filter:CreateForActive()
  }
  setmetatable(client, Client)

  -- Remote messages
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.OPEN_BIDS, function(_, _, sender, encodedItems, minIncrement, bidDuration, countdown, sessionName, allowOS, splitPercent, raidSize, mode, expTime)
    -- "mode" (old GDKP/PVE host mode) is still sent by hosts; it is ignored (always GDKP)
    client:OnOpenBids(sender, encodedItems, tonumber(minIncrement), tonumber(bidDuration), tonumber(countdown), sessionName, tonumber(allowOS), tonumber(splitPercent), tonumber(raidSize), mode, tonumber(expTime))
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.START_BIDDING, function(_, _, sender, itemIndices, expTime)
    client:OnStartBidding(sender, itemIndices, tonumber(expTime))
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.BID_ITEM_ACCEPTED, function(_, _, sender, batchedData)
    -- Handle batched bid format: index1,bidder1,amount1:index2,bidder2,amount2:...
    if not batchedData then return end
    local bidEntries = RaukinGDKP:Split(batchedData, RaukinGDKP.SEPARATOR.LIST_ELEMENT)
    for _, entry in ipairs(bidEntries) do
      local parts = RaukinGDKP:Split(entry, RaukinGDKP.SEPARATOR.ELEMENT)
      local index = tonumber(parts[1])
      local bidder = parts[2]
      local bid = tonumber(parts[3])
      if index and bidder and bid then
        client:OnBidItemRemote(sender, index, bidder, bid)
      end
    end
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.COUNTDOWN_ITEM, function(_, _, sender, index, exp, duration)
    client:OnCountdownItem(sender, tonumber(index), tonumber(exp), tonumber(duration))
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.ASSIGN_ITEM, function(_, _, sender, index, winner, price)
    -- Convert placeholder "_" or empty string to nil for "NOT SOLD" items
    if winner == "" or winner == "_" then winner = nil end
    local priceNum = tonumber(price)  -- tonumber("_") returns nil
    client:OnAssignItem(sender, tonumber(index), winner, priceNum)
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.GOLD_DUE, function(_, _, sender, amount)
    client:OnGoldDue(sender, tonumber(amount))
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.DELETE_ITEM, function(_, _, sender, index)
    client:OnDeleteItem(sender, tonumber(index))
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.DELETE_ALL_ITEMS, function(_, _, sender)
    client:OnDeleteAllItems(sender)
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.SYNC_RESPONSE, function(_, _, sender, encodedItems, encodedBids, minIncrement, bidDuration, countdown, sessionName, allowOS, splitPercent, raidSize, mode, encodedVotes)
    client:OnSyncResponse(sender, encodedItems, encodedBids, tonumber(minIncrement), tonumber(bidDuration), tonumber(countdown), sessionName, tonumber(allowOS), tonumber(splitPercent), tonumber(raidSize), mode, encodedVotes)
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.PAUSE_SESSION, function(_, _, sender, paused)
    client:OnPauseSession(sender, tonumber(paused) == 1)
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.VERSION_CHECK, function(_, _, sender)
    client:OnVersionCheck(sender)
  end)
  RaukinGDKP:RegisterCallback(RaukinGDKP.MESSAGE.TOP_SPENDER, function(_, _, sender, spender, amount, pot, cut, split, divisor)
    client:OnTopSpender(sender, spender, tonumber(amount), tonumber(pot), tonumber(cut), tonumber(split), tonumber(divisor))
  end)
  -- HOST_MODE and VOTE_UPDATE are still sent by hosts (GDKP, or PVE from old hosts).
  -- The client is GDKP only, so they have no handler: CallbackHandler drops them silently.

  -- Local events
  RaukinGDKP:RegisterEvent("TRADE_SHOW", function()
    client:OnTradeShow()
  end)
  RaukinGDKP:RegisterEvent("TRADE_CLOSED", function()
    client:OnTradeClosed()
  end)

  return client
end

-- Layout of the top of the window (the item list starts below the search row)
local SEARCH_ROW_Y = -32
local LIST_Y_OFFSET = -33   -- relative to the AceGUI content top (27px below the frame top)

function Client:CreateWindow()
  local window = RaukinGDKP.GUI:CreateWindow("RaukinGDKPClient", nil)
  window.content.yOffset = LIST_Y_OFFSET
  if window.UpdateResizeBounds then window.UpdateResizeBounds() end

  -- No Sessions dropdown any more: the active session is picked automatically
  -- (FindBestSession: the raid/party leader's session, else the most recently active one).

  -- Row 1: Search field (left) and filter buttons (right)
  local searchField = RaukinGDKP.SearchField:Create(window.frame)
  searchField:SetPlaceholderText("Search items")
  searchField:ClearAllPoints()
  searchField:SetPoint("TOPLEFT", window.frame, "TOPLEFT", 20, SEARCH_ROW_Y)
  searchField:SetWidth(200)
  searchField:HookScript("OnTextChanged", function()
    -- Only rebuild the list when the query really changed. Placeholder SetText calls
    -- (focus lost, UpdateText) used to rebuild every row as well.
    local query = searchField:GetFilter().query
    if query == window.lastSearchQuery then return end
    window.lastSearchQuery = query
    self:ReloadTable()
    self:UpdateSessionInfo()
  end)
  self.filter:AddFilter(searchField:GetFilter())
  window.searchField = searchField

  local usableFilterButton = CreateFrame("Button", nil, window.frame, "UIPanelButtonTemplate")
  usableFilterButton:SetNormalFontObject("GameFontNormalSmall")
  usableFilterButton:SetHighlightFontObject("GameFontHighlightSmall")
  usableFilterButton:ClearAllPoints()
  usableFilterButton:SetPoint("TOPRIGHT", window.frame, "TOPRIGHT", -16, SEARCH_ROW_Y)
  usableFilterButton:SetSize(100, 22)
  usableFilterButton:SetScript("OnClick", function() self:ToggleClassFilter(true) end)
  window.usableFilterButton = usableFilterButton

  local watchedFilterButton = CreateFrame("Button", nil, window.frame, "UIPanelButtonTemplate")
  watchedFilterButton:SetText("Watched")
  watchedFilterButton:SetNormalFontObject("GameFontNormalSmall")
  watchedFilterButton:SetHighlightFontObject("GameFontHighlightSmall")
  watchedFilterButton:ClearAllPoints()
  watchedFilterButton:SetPoint("RIGHT", usableFilterButton, "LEFT", -6, 0)
  watchedFilterButton:SetSize(80, 22)
  watchedFilterButton:SetScript("OnClick", function() self:ToggleWatchedFilter(true) end)
  window.watchedFilterButton = watchedFilterButton

  local activeFilterButton = CreateFrame("Button", nil, window.frame, "UIPanelButtonTemplate")
  activeFilterButton:SetText("Active")
  activeFilterButton:SetNormalFontObject("GameFontNormalSmall")
  activeFilterButton:SetHighlightFontObject("GameFontHighlightSmall")
  activeFilterButton:ClearAllPoints()
  activeFilterButton:SetPoint("RIGHT", watchedFilterButton, "LEFT", -6, 0)
  activeFilterButton:SetSize(70, 22)
  activeFilterButton:SetScript("OnClick", function() self:ToggleActiveFilter(true) end)
  activeFilterButton:SetScript("OnEnter", function(btn)
    GameTooltip:SetOwner(btn, "ANCHOR_TOP")
    GameTooltip:AddLine("Active Filter")
    GameTooltip:AddLine("Shows only active", 1, 1, 1, true)
    GameTooltip:AddLine("(pending/bidding) items", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  activeFilterButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)
  window.activeFilterButton = activeFilterButton

  -- Biggest Spender display (top left, in the title row)
  local topSpenderText = window.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  topSpenderText:SetPoint("TOPLEFT", window.frame, "TOPLEFT", 18, -12)
  topSpenderText:SetJustifyH("LEFT")
  topSpenderText:SetTextColor(1, 0.84, 0) -- Gold color
  topSpenderText:SetText("")
  window.topSpenderText = topSpenderText

  -- Bottom bar: total pot (left) and cut per raider (right), where it used to be
  local bar = window:AddBottomBar(22)
  bar:EnableMouse(true)
  local potText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  potText:SetPoint("LEFT", 9, 0)
  potText:SetJustifyH("LEFT")
  potText:SetTextColor(1, 0.84, 0)
  local cutText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cutText:SetPoint("RIGHT", -9, 0)
  cutText:SetJustifyH("RIGHT")
  cutText:SetTextColor(0.2, 0.8, 0.2)
  bar:SetScript("OnEnter", function(f)
    local session = self.activeSession
    if not session then return end
    local pot, cut, split, divisor = self:GetPotAndCut(session)
    GameTooltip:SetOwner(f, "ANCHOR_TOP")
    GameTooltip:AddLine("Total pot: " .. RaukinGDKP.FormatGold(pot))
    GameTooltip:AddLine("All items sold so far.", 1, 1, 1, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Cut per raider: " .. RaukinGDKP.FormatGold(cut))
    GameTooltip:AddLine(string.format("Pot x %d%% / %d", split, divisor), 1, 1, 1, true)
    GameTooltip:AddLine("Grows with every item that is sold.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  bar:SetScript("OnLeave", function() GameTooltip:Hide() end)
  window.potText, window.cutText = potText, cutText

  window:DoLayout()

  -- ElvUI / AddOnSkins look + opacity slider (top right, left of the X button)
  if RaukinGDKPSkin then
    RaukinGDKPSkin:Window(window.frame, { sliderPoint = { "TOPRIGHT", -34, -10 }, strip = true })
    RaukinGDKPSkin:Panel(window.bottomBar)   -- ElvUI / AddOnSkins look for the bottom bar
    RaukinGDKPSkin:EditBox(searchField)
  end

  window:FitToRows(0)

  return window
end

function Client:OnOpenBids(sender, encodedItems, minIncrement, bidDuration, countdown, sessionName, allowOS, splitPercent, raidSize, mode, expTime)
  local session = self.sessions[sender] or self:CreateSession(sender, true)
  session.minIncrement = minIncrement
  session.bidDuration = bidDuration
  session.countdown = countdown
  session.name = sessionName

  -- Backwards compatibility
  if allowOS ~= nil then
    session.allowOS = allowOS
  else
    session.allowOS = true
  end

  -- Store split percent (default 80 if not provided)
  session.splitPercent = splitPercent or 80

  -- Store raid size (default 25 if not provided, used for split calculation)
  session.raidSize = raidSize or 25

  -- Parse indices from this message BEFORE importing, so we know which items to update
  local importedIndices = {}
  if encodedItems and encodedItems ~= "" then
    local elements = RaukinGDKP:Split(encodedItems, RaukinGDKP.SEPARATOR.LIST_ELEMENT)
    for i = 1, #elements, 2 do
      local index = tonumber(elements[i])
      if index then
        importedIndices[index] = true
      end
    end
  end

  session:ImportItems(encodedItems, true)

  -- Only set expiration on items that were imported in THIS message, not all items
  local hasBiddingItems = false
  for index, item in pairs(session.items) do
    if item:GetStatus() == RaukinGDKP.STATUS.BIDDING then
      hasBiddingItems = true
      -- Only set expiration on items that were in this message
      if importedIndices[index] and expTime and expTime > 0 then
        item:SetExpiration(expTime)
        -- Calculate duration from expTime for countdown bar
        local duration = expTime - GetServerTime()
        if duration > 0 then
          item:SetCountdownDuration(duration)
        end
      end
    end
  end

  -- Always auto-switch to the latest session when a host sends items
  -- This ensures clients automatically join when a host starts a session
  self:SetActiveSession(session)

  -- Only auto-open window when bidding starts (not for pending items)
  -- Open by itself only when bidding runs - new items alone don't open it (/rgdkp autoopen turns it off)
  if hasBiddingItems and not RaukinGDKP:GetPref("autoOpenDisabled", false) then
    self:Show()
  elseif self.window and self.window:IsShown() then
    -- If window is already open, just refresh it
    self:ReloadTable()
    self:UpdateSessionInfo()
  end
end

-- Handle lightweight START_BIDDING message
-- Clients already have items from AddItem broadcasts, just need to update status and set expiration
function Client:OnStartBidding(sender, itemIndices, expTime)
  local session = self.sessions[sender]
  if not session then
    return
  end

  -- Parse item indices (comma-separated)
  local indices = RaukinGDKP:Split(itemIndices, RaukinGDKP.SEPARATOR.ELEMENT)

  for _, indexStr in ipairs(indices) do
    local index = tonumber(indexStr)
    if index then
      local item = session.items[index]
      if item then
        -- Update status to BIDDING
        item:SetStatus(RaukinGDKP.STATUS.BIDDING)

        -- Set expiration if provided
        if expTime and expTime > 0 then
          item:SetExpiration(expTime)
          local duration = expTime - GetServerTime()
          if duration > 0 then
            item:SetCountdownDuration(duration)
          end
        end
      end
    end
  end

  -- Auto-switch to this session and open window (unless /rgdkp autoopen turned it off)
  self:SetActiveSession(session)
  if not RaukinGDKP:GetPref("autoOpenDisabled", false) then
    self:Show()
  elseif self.window and self.window:IsShown() then
    self:ReloadTable()
    self:UpdateSessionInfo()
  end
end

function Client:Show()
  if not self.window then
    self.window = self:CreateWindow()

    -- Apply saved usable filter setting
    local enabled = RaukinGDKP:GetPref("usableFilterEnabled", false)

    if enabled then
      self.filter:AddFilter(self.classFilter)
      self.window.usableFilterButton:SetText("Usable: On")
    else
      self.window.usableFilterButton:SetText("Usable: Off")
    end
  end

  -- No Sessions dropdown: make sure the best session is selected
  if not self.activeSession then
    local best = self:FindBestSession()
    if best then self.activeSession = best end
  end

  self.window:Show()
  self:ReloadTable()
  self:UpdateSessionInfo(true)
end

function Client:Toggle()
  if self.window and self.window:IsShown() then
    self:Hide()
  else
    self:Show()
  end
end

function Client:Hide()
  if self.window then self.window:Hide() end
end

function Client:Reset()
  self:Hide()
  self.sessions = {}
  self.activeSession = nil
end

-- GUI

-- Title, Top Spender and the empty-list text. The status strip with Total Items /
-- filtered / Bid Total / My Total / Est. Cut and the Sessions dropdown were removed.
-- (The argument is kept for older call sites and ignored.)
function Client:UpdateSessionInfo()
  local window = self.window
  if not window or not window:IsShown() then return end

  local activeSession = self.activeSession
  local sessionName = activeSession and activeSession.name or nil

  -- Active filter: shows only PENDING/BIDDING items
  if window.activeFilterButton then
    window.activeFilterButton:Enable()
  end

  local titleName = sessionName or (activeSession and activeSession.owner and string.format("%s's Session", activeSession.owner)) or "RaukinGDKP"
  window:SetTitle(string.format("%s - v%s", titleName, RaukinGDKP.version))

  -- Top spender
  if window.topSpenderText then
    if activeSession and activeSession.topSpender then
      window.topSpenderText:SetText("Top Spender: " .. activeSession.topSpender .. " (" .. tostring(activeSession.topSpenderAmount or 0) .. "g)")
    else
      window.topSpenderText:SetText("")
    end
  end

  -- Pot and cut
  if window.potText then
    if activeSession then
      local pot, cut = self:GetPotAndCut(activeSession)
      window.potText:SetText("Total Pot: " .. RaukinGDKP.FormatGold(pot))
      window.cutText:SetText("Cut per raider: " .. RaukinGDKP.FormatGold(cut))
    else
      window.potText:SetText("")
      window.cutText:SetText("")
    end
  end

  -- Empty list text
  if window.emptyText then
    local rowCount = window.table:GetRowCount()
    if rowCount > 0 then
      window.emptyText:Hide()
    else
      if not activeSession then
        window.emptyText:SetText("No active session")
      elseif activeSession:GetItemCount(true) > 0 then
        window.emptyText:SetText("No items match the filters")
      else
        window.emptyText:SetText("No items yet")
      end
      window.emptyText:Show()
    end
  end
end

function Client:ReloadTable()
  if not self.window or not self.window:IsShown() then return end

  local table = self.window.table
  local savedScroll = (table.status or table.localstatus).scrollvalue

  table:Clear()

  if not self.activeSession then
    self.window:FitToRows(0)
    return
  end

  -- Collect and sort items: BIDDING first, PENDING second, ASSIGNED last
  local sortedIndices = {}
  for index, item in pairs(self.activeSession.items) do
    if self.filter:Evaluate(item) then
      tinsert(sortedIndices, index)
    end
  end

  -- Sort by index only for stable positioning
  -- Items stay in their original order and don't jump around when bidding
  sort(sortedIndices)

  for displayPos, index in ipairs(sortedIndices) do
    local item = self.activeSession.items[index]
    -- Use displayPos (1, 2, 3...) for row ordering, not item index
    table:CreateRow("RaukinGDKPItemRow", displayPos, item, function(r, i)
      self:ConfigureItemRow(r, i)
    end)
  end

  -- Grow/shrink to the number of rows (capped at maxRows; the list scrolls the rest)
  self.window:FitToRows(#sortedIndices)

  table:SetScroll(savedScroll)

  -- new rows: give them the ElvUI / AddOnSkins look as well
  -- (also re-levels pooled bid-box backdrops after the rows were re-parented)
  if RaukinGDKPSkin then RaukinGDKPSkin:Children(self.window.frame) end
end

function Client:ConfigureItemRow(row, item)
  row.image:SetTexture(item.texture)
  row.linkText:SetText(item.link)

  local session = self.activeSession
  local winner, price = item:GetWinner(), item:GetSalePrice()
  local topBidder, topBid = session:GetCurrentBidForItem(item)
  local minBid, myBid = session:GetMinNextBidForItem(item), session:GetPlayerBidForItem(RaukinGDKP.player, item)

  row:SetBids(minBid, myBid, price or topBid, winner or topBidder)

  row:RegisterCallback(RaukinGDKP.MESSAGE.BID_ITEM, function(_, row, item, bid)
    self:BidOnItem(item, bid, row)
  end)

  row:RegisterCallback(RaukinGDKP.MESSAGE.TOGGLE_WATCH, function(_, _, item)
    item:SetWatched(not item:IsWatched())
    if self.filter:ContainsFilter(self.watchedFilter) then
      self:ReloadTable()
      self:UpdateSessionInfo()
    end
  end)
end

-- Actions

function Client:GetSession(owner)
  return self.sessions[owner]
end

function Client:CreateSession(owner, notify)
  if self.sessions[owner] then
    RaukinGDKP:Error("Attempted to create a new session for", owner, "but one already exists!")
    return
  end

  local session = RaukinGDKP.Session:Create(owner)
  session:RegisterCallback(RaukinGDKP.MESSAGE.BID_ITEM, function(_, ...)
    self:OnBidItemLocal(...)
  end)
  session:RegisterCallback(RaukinGDKP.MESSAGE.ON_CHANGE, function(_, session, index)
    self:OnSessionChanged(session, false, index)
  end)

  self.sessions[owner] = session

  if not self.activeSession then
    self:SetActiveSession(session)
  else
    self:UpdateSessionInfo(true)
  end

  if notify then
    local notifyText = owner == RaukinGDKP.player and "You started a session" or string.format("%s started a loot session", owner)
    RaukinGDKP:NotifyLocal(notifyText)
  end

  return session
end

function Client:SetActiveSession(session)
  if session then session.lastActivity = GetTime() end
  if session ~= self.activeSession then
    self.activeSession = session
    self:OnSessionChanged(session, true)
  end
end

-- Name of the raid leader (or party leader), used to prefer the raid host's session
local function GetGroupLeaderName()
  local numRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
  if numRaid > 0 then
    for i = 1, numRaid do
      local name, rank = GetRaidRosterInfo(i)
      if rank == 2 then return name end
    end
    return nil
  end
  local numParty = GetNumPartyMembers and GetNumPartyMembers() or 0
  if numParty > 0 and GetPartyLeaderIndex then
    local index = GetPartyLeaderIndex()
    if index == 0 then return RaukinGDKP.player end
    return UnitName("party" .. index)
  end
  return nil
end

-- Session to show when nothing (or a removed session) is selected:
-- the raid/party leader's session, else the most recently active one.
-- Sessions are keyed by owner (the host's name, the addon message sender).
function Client:FindBestSession()
  local leader = GetGroupLeaderName()
  if leader and self.sessions[leader] then
    return self.sessions[leader]
  end

  local best, bestTime
  for _, session in pairs(self.sessions) do
    local t = session.lastActivity or 0
    if not best or t > bestTime then
      best, bestTime = session, t
    end
  end
  return best
end

function Client:ToggleClassFilter(reload)
  local currentlyEnabled = self.filter:ContainsFilter(self.classFilter)

  if currentlyEnabled then
    self.filter:RemoveFilter(self.classFilter)
    RaukinGDKP:SetPref("usableFilterEnabled", false)
    self.window.usableFilterButton:SetText("Usable: Off")
  else
    self.filter:AddFilter(self.classFilter)
    RaukinGDKP:SetPref("usableFilterEnabled", true)
    self.window.usableFilterButton:SetText("Usable: On")
  end

  if reload then
    self:ReloadTable()
    self:UpdateSessionInfo()
  end
end

function Client:ToggleWatchedFilter(reload)
  if self.filter:ContainsFilter(self.watchedFilter) then
    self.filter:RemoveFilter(self.watchedFilter)
    if self.window and self.window.watchedFilterButton then
      self.window.watchedFilterButton:SetText("Watched")
    end
  else
    self.filter:AddFilter(self.watchedFilter)
    if self.window and self.window.watchedFilterButton then
      self.window.watchedFilterButton:SetText("All")
    end
  end

  if reload then
    self:ReloadTable()
    self:UpdateSessionInfo()
  end
end

function Client:ToggleActiveFilter(reload)
  if self.filter:ContainsFilter(self.activeFilter) then
    self.filter:RemoveFilter(self.activeFilter)
    if self.window and self.window.activeFilterButton then
      self.window.activeFilterButton:SetText("Active")
    end
  else
    self.filter:AddFilter(self.activeFilter)
    if self.window and self.window.activeFilterButton then
      self.window.activeFilterButton:SetText("All")
    end
  end

  if reload then
    self:ReloadTable()
    self:UpdateSessionInfo()
  end
end

function Client:BidOnItem(item, bid, row)
  if not self.activeSession then return end

  item:SetWatched(true)
  local accepted, error = self.activeSession:RegisterBid(item, RaukinGDKP.player, bid)

  if row then
    if accepted then
      row:SetBidControlsEnabled(false)
    else
      row:SetErrorText(error)
    end
  end
end

-- Events

function Client:OnBidItemLocal(session, item, bidder, bid)
  if bidder ~= RaukinGDKP.player then return end

  local index = session:GetIndexOfItem(item)
  if not index then return end

  RaukinGDKP:Whisper(RaukinGDKP.MESSAGE.BID_ITEM, { index, bid }, session.owner)
end

function Client:OnBidItemRemote(sender, index, bidder, bid)
  local session = self.sessions[sender]
  if not session then
    RaukinGDKP:Debug("Received", RaukinGDKP.MESSAGE.BID_ITEM, "for untracked session", sender)
    return
  end

  local item = session:GetItemAtIndex(index)
  if not item then return end

  local previousBidder = session:GetCurrentBidForItem(item)
  session:RegisterBid(item, bidder, bid, true)

  if previousBidder == RaukinGDKP.player and bidder ~= previousBidder then
    RaukinGDKP:NotifyLocal(string.format("Outbid on %s!", item.link))
  end

  if session == self.activeSession and self.window and self.window:IsShown() then
    self.window.table:ReloadRowByData(item)
    self:UpdateSessionInfo(false)
  end
end

function Client:OnCountdownItem(sender, index, exp, duration)
  local session = self.sessions[sender]
  if not session then return end

  local item = session:GetItemAtIndex(index)
  if not item then return end

  item:SetExpiration(exp)
  item:SetCountdownDuration(duration)

  -- Refresh the row to update the countdown bar display
  if session == self.activeSession and self.window and self.window:IsShown() then
    self.window.table:ReloadRowByData(item)
  end
end

function Client:OnAssignItem(sender, index, winner, price)
  local session = self.sessions[sender]
  if not session then
    RaukinGDKP:Debug("Received", RaukinGDKP.MESSAGE.ASSIGN_ITEM, "for untracked session", sender)
    return
  end

  local item = session:GetItemAtIndex(index)
  if not item then
    return
  end

  -- Handle "NONE" marker - intentionally assigned to nobody
  local assignedToNone = (winner == "NONE")
  if assignedToNone then
    winner = nil
    item.assignedToNone = true
  else
    item.assignedToNone = false
  end

  -- If this is an OS phase ending with no winner, mark as OS failed
  -- (host will also send OPEN_BIDS with osFailed flag shortly after)
  if item:IsOS() and not winner and not assignedToNone then
    item:SetOSFailed(true)
  end

  session:AssignItem(item, winner, price)

  if session.owner and item.link and winner then
    if session.owner ~= RaukinGDKP.player then
      SendSystemMessage(price and string.format("%s won %s for %dg", winner, item.link, price) or string.format("%s won %s", winner, item.link))
    end

    if winner == RaukinGDKP.player then
      RaukinGDKP:NotifyLocal(price and string.format("You won %s for %dg", item.link, price) or string.format("You won %s", item.link))
    end
  end

  -- Reload table to update the row display
  if session == self.activeSession and self.window and self.window:IsShown() then
    self.window.table:ReloadRowByData(item)
    self:UpdateSessionInfo()
  end

  -- Reload table if active filter is enabled (to hide newly assigned items)
  if session == self.activeSession and self.filter:ContainsFilter(self.activeFilter) then
    self:ReloadTable()
    self:UpdateSessionInfo()
  end

  -- Host will automatically start OS bidding if no winner - client just waits
end

function Client:OnDeleteItem(sender, index)
  local session = self.sessions[sender]

  if not session then
    RaukinGDKP:Debug("Received", RaukinGDKP.MESSAGE.DELETE_ITEM, "for untracked session", sender)
    return
  end

  session:RemoveItemAtIndex(index)

  if session == self.activeSession and self.window and self.window:IsShown() then
    self:ReloadTable()
    self:UpdateSessionInfo()
  end
end

function Client:OnDeleteAllItems(sender)
  local session = self.sessions[sender]
  if session then
    session:Clear()

    -- Remove the session entirely so next items create a fresh session
    self.sessions[sender] = nil

    -- Clear active session if it was this one; fall back to another session if there is one
    if self.activeSession == session then
      self.activeSession = nil
      local nextSession = self:FindBestSession()
      if nextSession then
        self:SetActiveSession(nextSession)
      elseif self.window and self.window:IsShown() then
        -- Update UI to reflect no active session
        self:ReloadTable()
        self:UpdateSessionInfo(true)
      end
    end
  end

  if self.filter:ContainsFilter(self.watchedFilter) then
    self:ToggleWatchedFilter(false)
  end
end

function Client:OnSyncResponse(sender, encodedItems, encodedBids, minIncrement, bidDuration, countdown, sessionName, allowOS, splitPercent, raidSize, mode, encodedVotes)
  local session = self.sessions[sender] or self:CreateSession(sender, false)
  session.minIncrement = minIncrement
  session.bidDuration = bidDuration
  session.countdown = countdown
  session.name = sessionName
  session.allowOS = allowOS
  if splitPercent then session.splitPercent = splitPercent end
  if raidSize then session.raidSize = raidSize end
  -- mode / encodedVotes: still sent by hosts (old GDKP/PVE mode and PVE votes); ignored

  local hostHasItems = encodedItems and encodedItems ~= ""
  if not hostHasItems and next(session.items) then
    -- The host answered with an EMPTY item list while we still have the session.
    -- That happens right after the raid lead reloaded / crashed, before their data is back.
    -- Keep our copy instead of wiping it; a real "end session" arrives as DELETE_ALL_ITEMS.
    RaukinGDKP:Debug("Empty sync from", sender, "- keeping local session copy")
  else
    session:ImportItems(encodedItems, false)
    session:ImportBids(encodedBids)
  end

  -- Auto-switch to this session
  self:SetActiveSession(session)

  -- Reload the table to show items
  if self.window and self.window:IsShown() then
    self:ReloadTable()
    self:UpdateSessionInfo(true)
  end
end

function Client:OnSessionChanged(session, reloadDropdown, index)
  if session ~= self.activeSession then return end

  -- If index is present then it's a change local to 1 item
  -- This will have already beed handled in the item-specific message
  if not index then
    self:ReloadTable()
  end

  -- UpdateSessionInfo relies on the table row count, so call after ReloadTable
  self:UpdateSessionInfo(reloadDropdown)
end

-- Trade "You Owe" (raider side)
-- The host whispers GOLD_DUE when the trade opens (it now sends it twice, at 0.5s and 1.5s).
-- The whisper can arrive before our TradeFrame is shown, so the last value is cached for a
-- few seconds and shown on our own TRADE_SHOW as well. Duplicates simply re-show the text.
local GOLD_DUE_CACHE_SECONDS = 10

local function StripRealm(name)
  if not name then return nil end
  return (name:match("^([^%-]+)") or name):lower()
end

local function GetTradePartnerName()
  local name = UnitName("NPC")   -- 3.3.5: the trade target unit is "NPC"
  if not name and TradeFrameRecipientNameText then
    name = TradeFrameRecipientNameText:GetText()
  end
  return name
end

function Client:GetGoldDueText()
  local dueText = TradeFrame.RaukinGDKPDueText
  if not dueText then
    dueText = TradeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    -- Player's (left) column: just above the top-left corner of the trade window.
    -- The old TOP+20,-50 anchor sat on the recipient column, under ElvUI's recipient
    -- money frame. ElvUI's trade skin moves the visible border to TradeFrame.backdrop
    -- (TOPLEFT 11,-12), so anchor to that when it exists.
    local anchor = TradeFrame.backdrop or TradeFrame
    dueText:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 2, 4)
    dueText:SetJustifyH("LEFT")
    if RaukinGDKPSkin then RaukinGDKPSkin:FontString(dueText, 16, "OUTLINE") end
    TradeFrame.RaukinGDKPDueText = dueText
  end
  return dueText
end

function Client:ShowGoldDue(amount)
  if not TradeFrame or not TradeFrame:IsShown() then return end
  local dueText = self:GetGoldDueText()
  if amount and amount > 0 then
    dueText:SetText("|cFFFFD700You Owe: " .. amount .. "g|r")
    dueText:Show()
  else
    dueText:Hide()
  end
end

function Client:OnGoldDue(sender, amount)
  local now = GetTime()
  local last = self.lastGoldDue
  local duplicate = last and last.sender == sender and last.amount == amount and (now - last.time) < GOLD_DUE_CACHE_SECONDS
  if not duplicate then
    RaukinGDKP:Info("Received gold due: " .. tostring(amount) .. "g from " .. tostring(sender))
  end
  self.lastGoldDue = { sender = sender, amount = amount, time = now }

  -- Trade frame not open yet: OnTradeShow shows the cached value
  self:ShowGoldDue(amount)
end

function Client:OnTradeShow()
  local due = self.lastGoldDue
  if not due or (GetTime() - due.time) > GOLD_DUE_CACHE_SECONDS then return end

  -- Only for a trade with the host who sent it (when the partner name is known)
  local partner = GetTradePartnerName()
  if partner and due.sender and StripRealm(partner) ~= StripRealm(due.sender) then return end

  if TradeFrame:IsShown() then
    self:ShowGoldDue(due.amount)
  else
    -- TRADE_SHOW can reach us before Blizzard shows the frame
    C_Timer.After(0.2, function() self:ShowGoldDue(due.amount) end)
  end
end

-- 12345 -> "12,345g"
function RaukinGDKP.FormatGold(value)
  local text = tostring(math.floor((tonumber(value) or 0) + 0.5))
  local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  formatted = formatted:gsub("^(%-?),", "%1")
  return formatted .. "g"
end

-- Pot = all sold items (same rule as the host); cut = pot x split% / divisor.
-- The host sends its own numbers (with its split divisor and a fixed cut after payout);
-- they are used while they still match the items we know about.
function Client:GetPotAndCut(session)
  local pot = 0
  for _, item in pairs(session.items or {}) do
    if item.GetStatus and item:GetStatus() == RaukinGDKP.STATUS.ASSIGNED and item:GetWinner() and item:GetSalePrice() then
      pot = pot + item:GetSalePrice()
    end
  end
  local split = session.splitPercent or session.hostSplit or 80
  local divisor = session.cutDivisor or ((session.raidSize == 10) and 10 or 25)
  if divisor < 1 then divisor = 1 end
  if session.hostPot == pot and session.hostCut then
    return pot, session.hostCut, split, divisor
  end
  return pot, math.floor(pot * split / 100 / divisor + 0.5), split, divisor
end

function Client:OnTopSpender(sender, spender, amount, pot, cut, split, divisor)
  local session = self.sessions[sender]
  if not session then return end

  -- pot / cut info (hosts from 3.3.0e on; older hosts send only spender + amount)
  if pot then
    session.hostPot, session.hostCut = pot, cut
    if split then session.hostSplit = split end
    if divisor and divisor >= 1 then session.cutDivisor = divisor end
  end
  if session == self.activeSession then self:UpdateSessionInfo() end

  -- Handle reset (nil or empty spender)
  if not spender or spender == "" or spender == "_" then
    session.topSpender = nil
    session.topSpenderAmount = nil
    if session == self.activeSession and self.window and self.window.topSpenderText then
      self.window.topSpenderText:SetText("")
    end
    return
  end

  -- Store on session so it persists
  session.topSpender = spender
  session.topSpenderAmount = amount

  -- Update display if this is the active session
  if session == self.activeSession and self.window and self.window.topSpenderText then
    self.window.topSpenderText:SetText("Top Spender: " .. spender .. " (" .. tostring(amount or 0) .. "g)")
  end
end

function Client:OnTradeClosed()
  local dueText = TradeFrame.RaukinGDKPDueText
  if dueText then
    dueText:Hide()
  end
end

function Client:OnPauseSession(sender, paused)
  local session = self.sessions[sender]
  if not session then return end

  session.isPaused = paused

  -- Store/restore remaining time for each item
  -- Use GetServerTime() to stay in sync with host's expiration timestamps
  local serverTime = GetServerTime()
  for _, item in pairs(session.items) do
    if item:GetStatus() == RaukinGDKP.STATUS.BIDDING then
      if paused then
        -- Store remaining time
        local exp = item:GetExpiration()
        if exp then
          item.pausedRemaining = exp - serverTime
          if item.pausedRemaining < 0 then item.pausedRemaining = 0 end
        end
      else
        -- Restore timer with remaining time
        if item.pausedRemaining then
          local newExp = serverTime + item.pausedRemaining
          item:SetExpiration(newExp)
          item.pausedRemaining = nil
        end
      end
    end
  end

  if paused then
    RaukinGDKP:NotifyLocal("Session PAUSED")
  else
    RaukinGDKP:NotifyLocal("Session RESUMED")
  end

  -- Refresh display
  if session == self.activeSession and self.window and self.window:IsShown() then
    self:ReloadTable()
  end
end

function Client:OnVersionCheck(sender)
  RaukinGDKP:Whisper(RaukinGDKP.MESSAGE.VERSION_CHECK_RESPONSE, { RaukinGDKP.version }, sender)
end

-- Compatibility stub: RaukinGDKPHost still calls this directly when it broadcasts its mode.
-- The client is GDKP only, so the mode is ignored.
function Client:OnHostMode(sender, mode)
end
