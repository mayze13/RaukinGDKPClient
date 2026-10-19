local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

-- Lua APIs
local setmetatable, tonumber = setmetatable, tonumber

-- WoW APIs (use namespaced RaukinItem to avoid conflicts)
local C_Item, BItem, GetItemInfo = RaukinGDKPCompat.C_Item, RaukinItem, GetItemInfo
local C_Timer = RaukinGDKPCompat.C_Timer

-- The host's Mystery box (several BoEs sold as one): sent as this item id. Shown with the
-- gift's icon but as "Mystery box", and never as a real item (no tooltip, no hyperlink).
local MYSTERY_BOX_ID = 41426
local MYSTERY_BOX_NAME = "Mystery box"
local MYSTERY_BOX_LINK = "|cffa335ee[" .. MYSTERY_BOX_NAME .. "]|r"

local Item = {}
Item.__index = Item
RaukinGDKP.Item = Item

function Item:CreateForId(itemId)
  local item = {
    id = itemId,
    isBound = false,
  }
  setmetatable(item, Item)

  RaukinGDKP:AddMessageSystem(item)

  -- GetItemInfo returns nil if the item has not yet been cached
  -- If not cached, we have to load it first before populating properties
  if itemId == MYSTERY_BOX_ID or C_Item.IsItemDataCachedByID(itemId) then
    item:PopulateStaticProperties()
  else
    BItem:CreateFromItemID(itemId):ContinueOnItemLoad(function() item:PopulateStaticProperties() end)
  end

  return item
end

-- 3.3.5a: GetItemInfo returns string types, need to convert to numeric IDs
local ITEM_CLASS_IDS = {
  ["Weapon"] = 2,
  ["Armor"] = 4,
}

local ITEM_SUBCLASS_IDS = {
  -- Weapons (classId 2)
  ["One-Handed Axes"] = 0,
  ["Two-Handed Axes"] = 1,
  ["Bows"] = 2,
  ["Guns"] = 3,
  ["One-Handed Maces"] = 4,
  ["Two-Handed Maces"] = 5,
  ["Polearms"] = 6,
  ["One-Handed Swords"] = 7,
  ["Two-Handed Swords"] = 8,
  ["Staves"] = 10,
  ["Fist Weapons"] = 13,
  ["Daggers"] = 15,
  ["Thrown"] = 16,
  ["Crossbows"] = 18,
  ["Wands"] = 19,
  -- Armor (classId 4)
  ["Miscellaneous"] = 0,
  ["Cloth"] = 1,
  ["Leather"] = 2,
  ["Mail"] = 3,
  ["Plate"] = 4,
  ["Shields"] = 6,
  ["Librams"] = 7,
  ["Idols"] = 8,
  ["Totems"] = 9,
  ["Sigils"] = 10,
}

local ITEM_LOAD_MAX_RETRIES = 5
local ITEM_LOAD_RETRY_INTERVAL = 0.5  -- seconds between retries

function Item:PopulateStaticProperties()
  local itemType, itemSubType, _
  self.name, self.link, self.quality, self.ilvl, self.minLevel, itemType, itemSubType, _, self.equipLoc, self.texture = GetItemInfo(self.id)

  -- Convert string types to numeric IDs for filter compatibility
  self.classId = ITEM_CLASS_IDS[itemType]
  self.subclassId = ITEM_SUBCLASS_IDS[itemSubType]

  if self.id == MYSTERY_BOX_ID then
    self.isMysteryBox = true
    self.name, self.link, self.quality = MYSTERY_BOX_NAME, MYSTERY_BOX_LINK, 4
    self.texture = self.texture or GetItemIcon(self.id)
  end

  if not self.name then
    -- Item data not yet available from server
    self._retryCount = (self._retryCount or 0) + 1
    if self._retryCount <= ITEM_LOAD_MAX_RETRIES then
      -- Force the client to request item data from the server via tooltip query
      GameTooltip:SetOwner(UIParent, "ANCHOR_NONE")
      GameTooltip:SetHyperlink("item:" .. self.id)
      GameTooltip:Hide()
      C_Timer.After(self._retryCount * ITEM_LOAD_RETRY_INTERVAL, function()
        self:PopulateStaticProperties()
      end)
      return
    end
    RaukinGDKP:Error("Invalid itemId", self.id)
  end

  self._retryCount = nil
  self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
end

function Item:GetStatus()
  return self.info and self.info.status or RaukinGDKP.STATUS.NONE
end

function Item:SetStatus(status)
  local info = self.info or {}
  if status ~= info.status then
    info.status = status
    self.info = info
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end
end

function Item:GetMinPrice()
  return self.info and self.info.minPrice or nil
end

function Item:GetMinIncrement()
  return self.info and self.info.minIncrement or nil
end

function Item:SetMinPrice(price)
  local info = self.info or {}
  if price ~= info.minPrice then
    info.minPrice = price
    self.info = info
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end
end

function Item:GetExpiration()
  return self.info and self.info.exp or nil
end

function Item:SetExpiration(exp)
  local info = self.info or {}
  if exp ~= info.exp then
    info.exp = exp
    self.info = info
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end
end

function Item:GetCountdownDuration()
  return self.info and self.info.countdownDuration or nil
end

function Item:SetCountdownDuration(duration)
  local info = self.info or {}
  if duration ~= info.countdownDuration then
    info.countdownDuration = duration
    self.info = info
  end
end

function Item:GetSalePrice()
  return self.info and self.info.salePrice or nil
end

function Item:IsOS()
  return self.info and self.info.isOS or false
end

function Item:SetOS(isOS)
  local info = self.info or {}
  if isOS ~= info.isOS then
    info.isOS = isOS
    self.info = info
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end
end

function Item:IsOSFailed()
  return self.info and self.info.osFailed or false
end

function Item:SetOSFailed(failed)
  local info = self.info or {}
  if failed ~= info.osFailed then
    info.osFailed = failed
    self.info = info
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end
end

function Item:GetWinner()
  return self.info and self.info.winner or nil
end

function Item:SetWinner(winner, price)
  local info = self.info or {}
  if winner ~= info.winner or price ~= info.salePrice or info.status ~= RaukinGDKP.STATUS.ASSIGNED then
    info.winner = winner
    info.salePrice = price
    info.status = RaukinGDKP.STATUS.ASSIGNED
    self.info = info
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end
end

function Item:IsWatched()
  return (self.watched or false) or (self.session and self.session:GetPlayerBidForItem(RaukinGDKP.player, self))
end

function Item:SetWatched(watched)
  if watched ~= self.watched then
    self.watched = watched
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end
end

function Item:ImportInfo(info)
  -- Merge new info with existing, preserving fields not provided in new data
  -- This prevents OPEN_BIDS (which doesn't include exp) from wiping out
  -- expiration set by COUNTDOWN_ITEM
  local existing = self.info or {}
  for key, value in pairs(info) do
    existing[key] = value
  end
  -- pairs() skips nil values, so a cleared winner/price would otherwise survive the merge.
  -- If the host says the item is no longer assigned (re-opened / OS phase), drop the old sale.
  if info.status and info.status ~= RaukinGDKP.STATUS.ASSIGNED then
    existing.winner = nil
    existing.salePrice = nil
  end
  self.info = existing
  self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
end

-- Parses one encoded item without creating an Item object.
-- Returns itemId, info  (itemId is nil if the data is malformed)
function Item:DecodeInfo(encodedStr)
  if not encodedStr or encodedStr == "" then return nil end
  local elements = RaukinGDKP:Split(encodedStr, RaukinGDKP.SEPARATOR.ELEMENT)

  local itemId = tonumber(elements[1])
  local winner = elements[6]
  if winner == "" then winner = nil end

  local info = {
    status = tonumber(elements[2]),
    minPrice = tonumber(elements[3]),
    minIncrement = tonumber(elements[4]),  -- Per-item minIncrement
    exp = tonumber(elements[5]),
    winner = winner,
    salePrice = tonumber(elements[7]),
    isOS = tonumber(elements[8]) == 1,
    osFailed = tonumber(elements[9]) == 1,
  }

  return itemId, info
end

function Item:Decode(encodedStr)
  local itemId, info = self:DecodeInfo(encodedStr)
  if not itemId then return nil end

  local item = self:CreateForId(itemId)
  item.info = info
  return item
end
