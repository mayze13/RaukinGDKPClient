--[[-----------------------------------------------------------------------------
Adapted from AceGUI-3.0 widget template
-------------------------------------------------------------------------------]]
local Type, Version = "RaukinGDKPItemRow", 11
local AceGUI = RaukinLibStub and RaukinLibStub("RaukinAceGUI-3.0", true)
local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

-- Lua APIs
local math, pairs = math, pairs

-- WoW APIs
local CreateFrame, GameTooltip, UIParent = CreateFrame, GameTooltip, UIParent

--[[-----------------------------------------------------------------------------
Methods
-------------------------------------------------------------------------------]]

local function UpdateText(self)
  if self.bidBox.isFocused then return end

  local minBid, myBid = self:GetBids()
  local item = self:GetCurrentItem()
  local pendingBid = item and item.pendingBid or nil

  -- During OS phase, minBid is already halved by StartOSPhase
  self.bidBox:SetText(pendingBid or myBid or minBid or "")

  self:SetErrorText(nil)
end

local function UpdateColors(self)
  local _, myBid, topBid = self:GetBids()
  local item = self:GetCurrentItem()
  local pendingBid = item and item.pendingBid or nil

  if self.bidBox.isFocused or pendingBid or (myBid and myBid == topBid) then
    self.bidBox:SetTextColor(1, 1, 1, 1)
  else
    -- suggested (not yet placed) bid: dimmed but readable on ElvUI backdrops (was 0.3)
    self.bidBox:SetTextColor(1, 1, 1, 0.6)
  end
end

local function UpdateWatchButton(self)
  local item = self:GetCurrentItem()
  local isWatched = item and item:IsWatched()

  if isWatched then
    self.watchButton.texture:SetTexture("Interface\\LFGFrame\\BattlenetWorking0")
  else
    self.watchButton.texture:SetTexture("Interface\\LFGFrame\\BattlenetWorking4")
  end
end

local function UpdateBackdropColor(self)
  -- Transparent background - let the window background show through
  -- The countdown bar provides color indication for bidding status
  self.frame:SetBackdropColor(0, 0, 0, 0)
end

local methods = {

  -- Lifecycle

  ["OnAcquire"] = function(self)
    self:SetFullWidth(true)
    self:SetHeight(50)

    self.image:SetTexture(nil)
    self.linkText:SetText(nil)
    self:SetBids(nil, nil, nil)
    self:SetErrorText(nil)

    UpdateColors(self)
  end,

  ["OnRelease"] = function(self)
    self:UnregisterAllCallbacks()
  end,

  ["OnWidthSet"] = function(self, width)
    local content = self.content
    local contentwidth = math.max(0, width)
    content:SetWidth(contentwidth)
    content.width = contentwidth
  end,

  ["OnHeightSet"] = function(self, height)
    local content = self.content
    local contentheight = max(0, height)
    content:SetHeight(contentheight)
    content.height = contentheight
  end,

  -- Utility

  ["GetCurrentItem"] = function(self)
    return self:GetUserDataTable().data
  end,

  ["GetBids"] = function(self)
    local data = self:GetUserDataTable()
    return data.minBid, data.myBid, data.topBid
  end,

  -- Actions

  ["SetBidControlsEnabled"] = function(self, enabled)
    for _, control in pairs(self.bidControls) do
      -- 3.3.5a: Buttons use Enable()/Disable(), EditBoxes use EnableMouse/EnableKeyboard
      if control.Enable and control.Disable then
        if enabled then
          control:Enable()
        else
          control:Disable()
        end
      elseif control.EnableMouse then
        -- EditBox
        control:EnableMouse(enabled)
        control:EnableKeyboard(enabled)
        if not enabled then
          control:ClearFocus()
        end
      end
    end
  end,

  ["SetBidControlsVisible"] = function(self, visible)
    for _, control in pairs(self.bidControls) do
      if visible then
        control:Show()
      else
        control:Hide()
      end
    end
  end,

  ["SetBids"] = function(self, minBid, myBid, topBid, topBidder)
    local data = self:GetUserDataTable()
    data.minBid = minBid
    data.myBid = myBid
    data.topBid = topBid

    local item = self:GetCurrentItem()
    local status = item and item:GetStatus() or RaukinGDKP.STATUS.PENDING
    local isAssigned = (status == RaukinGDKP.STATUS.ASSIGNED)
    local isSold = item and item:GetSalePrice()
    local isOS = item and item:IsOS()
    local isOSFailed = item and item:IsOSFailed()

    self.countdownBar:CountdownItem(item, topBidder)

    -- Handle OS failed state - no buttons, just show NOT SOLD
    if isOSFailed then
      self:SetBidControlsVisible(false)
      self.topBidText:SetPoint("RIGHT")
      self.topBidText:SetText("NOT SOLD")
      self.topBidText:SetTextColor(0.7, 0.7, 0.7) -- Gray
      self.topBidText:Show()
      self.topBidAmountText:SetText("No bids")
      self.topBidAmountText:SetTextColor(0.7, 0.7, 0.7)
      self.linkText:SetPoint("RIGHT", self.topBidText, "LEFT", -8, 0)
      UpdateWatchButton(self)
      return
    end

    if status == RaukinGDKP.STATUS.BIDDING then
      self:SetBidControlsVisible(true)
      self.topBidText:SetPoint("RIGHT", self.minButton, "LEFT")
    else
      self:SetBidControlsVisible(false)
      self.topBidText:SetPoint("RIGHT")
    end

    if not myBid or myBid ~= topBid then
      -- Show "OS Bid" label during OS phase
      if isOS and status == RaukinGDKP.STATUS.BIDDING then
        self.enterBidText:SetText("OS Bid")
      else
        self.enterBidText:SetText("Enter Bid")
      end
      self:SetBidControlsEnabled(true)
    else
      self.enterBidText:SetText("My Bid")
      self:SetBidControlsEnabled(false)
    end

    local isPending = (status == RaukinGDKP.STATUS.PENDING)

    if topBidder then
      -- Show OS indicator if item is in OS phase
      if isOS and status == RaukinGDKP.STATUS.BIDDING then
        self.topBidText:SetText("OS Bid: "..topBidder)
        self.topBidText:SetTextColor(0.7, 0.7, 0.7) -- Gray for OS
      elseif isAssigned then
        self.topBidText:SetText("SOLD")
        self.topBidText:SetTextColor(1, 0.82, 0) -- Gold
      else
        self.topBidText:SetText("Top Bid: "..topBidder)
        self.topBidText:SetTextColor(1, 0.82, 0) -- Gold
      end
      self.topBidText:Show()
      if isAssigned then
        self.topBidAmountText:SetText(string.format("%s for %s", topBidder or "?", topBid and tostring(topBid) or "?"))
        self.topBidAmountText:SetTextColor(self.topBidText:GetTextColor())
      else
        self.topBidAmountText:SetText(topBid)
        self.topBidAmountText:SetTextColor(1, 1, 1, 1)
      end
    elseif isAssigned and not isSold then
      -- No bidder and assigned - check if intentionally assigned to none
      if item and item.assignedToNone then
        -- Intentionally assigned to None
        self.topBidText:SetText("None")
        self.topBidText:SetTextColor(0.5, 0.5, 0.5) -- Gray
        self.topBidText:Show()
        self.topBidAmountText:SetText("")
        self.topBidAmountText:SetTextColor(0.5, 0.5, 0.5)
      elseif item and item.session and item.session:AllowOSForItem(item) then
        -- OS will auto-start, show "OS BIDDING" instead of "NOT SOLD"
        self.topBidText:SetText("OS BIDDING")
        self.topBidText:SetTextColor(0.7, 0.7, 0.7) -- Gray for OS
        self.topBidText:Show()
        self.topBidAmountText:SetText("Half price")
        self.topBidAmountText:SetTextColor(0.7, 0.7, 0.7)
      else
        -- OS not allowed, show NOT SOLD
        self.topBidText:SetText("NOT SOLD")
        self.topBidText:SetTextColor(0.7, 0.7, 0.7) -- Gray
        self.topBidText:Show()
        self.topBidAmountText:SetText("No bids")
        self.topBidAmountText:SetTextColor(0.7, 0.7, 0.7)
      end
    elseif isPending then
      -- Item is pending (not yet open for bidding)
      self.topBidText:SetText("PENDING")
      self.topBidText:SetTextColor(0.5, 0.5, 1) -- Light blue
      self.topBidText:Show()
      self.topBidAmountText:SetText("Waiting for bidding to start")
      self.topBidAmountText:SetTextColor(0.5, 0.5, 1)
    elseif isOS and status == RaukinGDKP.STATUS.BIDDING then
      -- OS bidding with no bids yet
      self.topBidText:SetText("OS BIDDING")
      self.topBidText:SetTextColor(0.7, 0.7, 0.7) -- Gray for OS
      self.topBidText:Show()
      self.topBidAmountText:SetText("Half price")
      self.topBidAmountText:SetTextColor(0.7, 0.7, 0.7)
    else
      self.topBidText:SetText(nil)
      self.topBidText:Hide()
      self.topBidAmountText:SetText(nil)
      self.topBidAmountText:SetTextColor(1, 1, 1, 0.4)
    end

    -- Only show old OS button behavior if NOT in auto-OS mode
    -- Since we now auto-start OS, we don't need the manual OS button
    if isAssigned and not isSold and not isOSFailed then
      -- Item assigned with no winner - OS phase will auto-start
      -- Don't show OS button since it's automatic now
      self.bidButton:SetText(nil)
      self.bidButton:Hide()
      self.bidBox:Hide()
      self.enterBidText:SetText(nil)
      if item then item.pendingBid = nil end
    else
      self.bidButton:SetText("Bid")
    end

    if self.topBidAmountText:GetText() then
      self.linkText:SetPoint("RIGHT", self.topBidText, "LEFT", -8, 0)
    else
      -- 3.3.5a: no ClearPoint, must ClearAllPoints and re-set base points
      self.linkText:ClearAllPoints()
      self.linkText:SetPoint("TOPLEFT", self.image, "TOPRIGHT", 8, 0)
      self.linkText:SetPoint("BOTTOMLEFT", self.image, "BOTTOMRIGHT", 8, 0)
    end

    UpdateText(self)
    UpdateColors(self)
    UpdateWatchButton(self)
    UpdateBackdropColor(self)
  end,

  ["SetErrorText"] = function(self, error)
    self.errorText:SetText(error)
  end,

  ["ShowItemTooltip"] = function(self)
    local item = self:GetCurrentItem()
    if not item or not item.link then return end

    -- 3.3.5a: SetOwner needs a frame, not a texture
    GameTooltip:SetOwner(self.frame, "ANCHOR_CURSOR")
    GameTooltip:SetHyperlink(item.link)
  end,

  ["ShowWatchTooltip"] = function(self)
    local item = self:GetCurrentItem()
    if not item then return end

    GameTooltip:SetOwner(self.watchButton, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(item:IsWatched() and "Un-watch this item" or "Watch this item")
    GameTooltip:Show()
  end,

  ["HideTooltip"] = function(self)
    GameTooltip:Hide()
  end,

  ["OnTooltipClicked"] = function(self, button)
    -- An unmodified click would open the default item tooltip frame
    -- This seems unnecessary, so is disabled for now
    if not IsModifiedClick() then return end

    local item = self:GetCurrentItem()
    if not item or not item.link then return end

    -- Handles pasting link to chat frame, dressup, etc.
    SetItemRef(item.link, item.link, button)
  end,

  ["OnMinPressed"] = function(self)
    self.bidBox:ClearFocus()

    local item = self:GetCurrentItem()
    if not item then return end

    local minBid, myBid, topBid = self:GetBids()

    if myBid and myBid == topBid then
      item.pendingBid = nil
    else
      item.pendingBid = minBid
    end

    UpdateText(self)
    UpdateColors(self)
  end,

  ["OnIncrementPressed"] = function(self)
    self.bidBox:ClearFocus()

    local item = self:GetCurrentItem()
    if not item or not item.session then return end

    local minBid, myBid = self:GetBids()
    -- Use per-item minIncrement, fallback to session-wide
    local minIncrement = item:GetMinIncrement() or (item.session and item.session.minIncrement) or 100
    local baseBid = item.pendingBid or myBid or minBid or 0
    local incremented = baseBid + minIncrement
    item.pendingBid = incremented

    UpdateText(self)
    UpdateColors(self)
  end,

  ["OnBidPressed"] = function(self)
    self.bidBox:ClearFocus()

    local item = self:GetCurrentItem()
    if not item then return end

    if item.pendingBid then
      self:FireMessage(RaukinGDKP.MESSAGE.BID_ITEM, item, item.pendingBid)
    end
  end,

  ["OnWatchPressed"] = function(self)
    local item = self:GetCurrentItem()
    if not item then return end
    self:FireMessage(RaukinGDKP.MESSAGE.TOGGLE_WATCH, item)
  end,

  ["EditBox_OnEditFocusGained"] = function(self)
    self.bidBox.isFocused = true

    local _, myBid = self:GetBids()
    if not myBid and not self:GetCurrentItem().pendingBid then
      self.bidBox:SetText("")
    else
      self.bidBox:HighlightText()
    end

    UpdateColors(self)
  end,

  -- Enter in the bid box = clicking Bid: same OnBidPressed path (clears focus, which drops
  -- a 0/empty pending bid, then fires BID_ITEM -> Client:BidOnItem, whose validation sets
  -- the row's error text). Only while the Bid button itself is usable; otherwise just
  -- leave the box.
  ["EditBox_OnEnterPressed"] = function(self)
    local bidButton = self.bidButton
    if bidButton:IsShown() and bidButton:IsEnabled() then
      self:OnBidPressed()
    else
      self.bidBox:ClearFocus()
    end
  end,

  ["EditBox_OnTextChanged"] = function(self)
    if not self.bidBox.isFocused then return end

    local item, bid = self:GetCurrentItem(), self.bidBox:GetNumber()
    if item and bid > 0 then
      item.pendingBid = bid
    end
  end,

  ["EditBox_OnEditFocusLost"] = function(self)
    self.bidBox.isFocused = false

    local item, bid = self:GetCurrentItem(), self.bidBox:GetNumber()
    if item and bid == 0 then
      item.pendingBid = nil
    end

    UpdateText(self)
    UpdateColors(self)
  end,
}

local backdrop = {
  bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
  tile = true, tileSize = 16,
}

--[[-----------------------------------------------------------------------------
Constructor
-------------------------------------------------------------------------------]]
local function Constructor()
  local num  = AceGUI:GetNextWidgetNum(Type)
  -- 3.3.5a: BackdropTemplate doesn't exist, just create frame and use SetBackdrop
  local frame = CreateFrame("Frame", nil, UIParent)
  frame:SetBackdrop(backdrop)
  frame:SetBackdropColor(0, 0, 0, 0)  -- Transparent background

  local countdownBar = RaukinGDKP.CountdownBar:Create(frame)
  countdownBar:SetAllPoints()

  -- Container Support
  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT")
  content:SetPoint("BOTTOMRIGHT")

  -- lTR layout

  local watchButton = CreateFrame("Button", nil, content)
  local watchTexture = watchButton:CreateTexture()
  watchButton.texture = watchTexture;
  watchButton:SetSize(16, 16)
  watchTexture:SetTexCoord(0.1, 0.9, 0.1, 0.9);
  watchTexture:SetAllPoints(watchButton);
  watchButton:SetNormalTexture(watchTexture);
  watchButton:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight");
  watchButton:SetPoint("LEFT", 8, 0)

  local image = content:CreateTexture(nil, "OVERLAY")
  image:SetPoint("LEFT", watchButton, "RIGHT", 8, 0)
  image:SetSize(32, 32)

  local linkText = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  linkText:SetPoint("TOPLEFT", image, "TOPRIGHT", 8, 0)
  linkText:SetPoint("BOTTOMLEFT", image, "BOTTOMRIGHT", 8, 0)
  linkText:SetJustifyH("LEFT")

  local tooltipRegion = CreateFrame("Button", nil, content)
  tooltipRegion:SetPoint("TOPLEFT", image)
  tooltipRegion:SetPoint("BOTTOMRIGHT", linkText)

  -- RTL layout

  local bidButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  bidButton:SetText("Bid")
  bidButton:SetPoint("RIGHT", -8, 0)
  bidButton:SetSize(50, 32)

  local incrementButton = CreateFrame("Button", nil, content)
  incrementButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Up")
  incrementButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
  incrementButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Down")
  incrementButton:SetDisabledTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollUp-Disabled")
  incrementButton:SetPoint("RIGHT", bidButton, "LEFT", -8, 0)
  incrementButton:SetSize(25, 25)

  local bidBox = CreateFrame("EditBox", Type.."BidBox"..num, content, "InputBoxTemplate")
	bidBox:SetAutoFocus(false)
  bidBox:SetNumeric(true)
	bidBox:SetMaxLetters(7)
  bidBox:SetTextInsets(0, 13, 0, 0)
  bidBox:SetJustifyH("CENTER")
	bidBox:SetPoint("RIGHT", incrementButton, "LEFT", 2, 0)
	bidBox:SetSize(75, 25)

  local minButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
  minButton:SetText("Min")
  minButton:SetNormalFontObject("GameFontNormalSmall")
  minButton:SetHighlightFontObject("GameFontNormalSmall")
  minButton:SetPoint("RIGHT", bidBox, "LEFT", -5, 0)
  minButton:SetPushedTextOffset(0, 0)
  minButton:SetSize(32, 20)

  local enterBidText = bidBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  enterBidText:SetPoint("BOTTOMLEFT", bidBox, "TOPLEFT", -2, -3)
  enterBidText:SetJustifyH("LEFT")
  enterBidText:SetHeight(14)

  local errorText = bidBox:CreateFontString(nil, "OVERLAY", "GameFontRedSmall")
  errorText:SetPoint("TOP", bidBox, "BOTTOM", 0, 3)
  errorText:SetJustifyH("LEFT")
  errorText:SetHeight(14)

  local bidBoxGold = bidBox:CreateTexture(nil, "OVERLAY")
  bidBoxGold:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
  bidBoxGold:SetPoint("RIGHT", -6, 0)
  bidBoxGold:SetSize(13, 13)

  local topBidText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  topBidText:SetJustifyH("LEFT")
  topBidText:SetPoint("TOP", enterBidText)
  topBidText:SetPoint("LEFT", minButton, "LEFT", -130, 0)
  topBidText:SetHeight(14)

  local topBidAmountText = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  topBidAmountText:SetJustifyH("LEFT")
  topBidAmountText:SetPoint("LEFT", topBidText)
  topBidAmountText:SetPoint("RIGHT", topBidText)
  topBidAmountText:SetPoint("TOP", topBidText, "BOTTOM")
  topBidAmountText:SetHeight(22)

  local widget = {
    frame = frame,
    content = content,
    countdownBar = countdownBar,
    watchButton = watchButton,
    image = image,
    linkText = linkText,
    minButton = minButton,
    enterBidText = enterBidText,
    bidBox = bidBox,
    errorText = errorText,
    topBidText = topBidText,
    topBidAmountText = topBidAmountText,
    bidButton = bidButton,
    bidControls = { minButton, bidBox, incrementButton, bidButton },
    type = Type,
  }

  -- Methods and events
  for method, func in pairs(methods) do
    widget[method] = func
  end

  tooltipRegion:HookScript("OnEnter", function() widget:ShowItemTooltip() end)
  tooltipRegion:HookScript("OnLeave", function() widget:HideTooltip() end)
  tooltipRegion:HookScript("OnClick", function(_, button) widget:OnTooltipClicked(button) end)

  watchButton:HookScript("OnEnter", function() widget:ShowWatchTooltip() end);
  watchButton:HookScript("OnLeave", function() widget:HideTooltip() end);
  watchButton:HookScript("OnClick", function(_, button) widget:OnWatchPressed() end)

  bidBox:SetScript("OnEscapePressed", function(frame) frame:ClearFocus() end)
  bidBox:SetScript("OnEnterPressed", function(frame) widget:EditBox_OnEnterPressed() end)
  bidBox:SetScript("OnEditFocusGained", function(frame) widget:EditBox_OnEditFocusGained() end)
  bidBox:SetScript("OnTextChanged", function(frame) widget:EditBox_OnTextChanged() end)
  bidBox:SetScript("OnEditFocusLost", function(frame) widget:EditBox_OnEditFocusLost() end)

  minButton:HookScript("OnClick", function() widget:OnMinPressed() end)
  incrementButton:HookScript("OnClick", function() widget:OnIncrementPressed() end)
  bidButton:HookScript("OnClick", function() widget:OnBidPressed() end)

  RaukinGDKP:AddMessageSystem(widget)

  -- ElvUI look: row backdrop with the Secondary texture + pixel border (the row's own
  -- transparent tint from UpdateBackdropColor is kept), and the bid box skinned with its
  -- backdrop kept below the text
  local Skin = RaukinGDKPSkin
  if Skin and Skin:Engine() then
    if Skin:Engine() == "elvui" then Skin:Row(frame) end
    Skin:EditBox(bidBox)
  end

  return AceGUI:RegisterAsContainer(widget)
end

AceGUI:RegisterWidgetType(Type, Constructor, Version)
