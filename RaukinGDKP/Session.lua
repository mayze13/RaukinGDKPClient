local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

local Session = {}
Session.__index = Session
RaukinGDKP.Session = Session

-- Lua APIs
local pairs, next, math, setmetatable = pairs, next, math, setmetatable
local string, table, tonumber = string, table, tonumber

function Session:Create(owner)
  local session = {
    owner = owner,
    items = {},
    bids = {},
    assignments = {},
    minIncrement = 100,
    bidDuration = 180,
    countdown = 10,
  }
  setmetatable(session, Session)

  RaukinGDKP:AddMessageSystem(session)

  return session
end

function Session:AllowOSForItem(item)
  -- Disallow OS for TOC trophies and items where OS already failed
  return (self.allowOS ~= false and item and item.id ~= 47242 and not item:IsOSFailed())
end

function Session:GetItemAtIndex(index)
  return self.items[index]
end

function Session:GetIndexOfItem(item)
  if not item then return nil end
  for index, it in pairs(self.items) do
    if it == item then return index end
  end
  return nil
end

function Session:GetNextIndex()
  local maxIndex = 0
  for index in pairs(self.items) do
    maxIndex = math.max(maxIndex, index)
  end
  return maxIndex + 1
end

function Session:GetItemCount(includePending)
  local count = 0
  for _, item in pairs(self.items) do
    if includePending or item:GetStatus() ~= RaukinGDKP.STATUS.PENDING then
      count = count + 1
    end
  end
  return count
end

function Session:GetPendingItemCount()
  local count = 0
  for _, item in pairs(self.items) do
    if item:GetStatus() == RaukinGDKP.STATUS.PENDING then
      count = count + 1
    end
  end
  return count
end

function Session:GetCurrentBidForItem(item)
  local bid = self.bids[item]
  if bid then
    return bid.player, bid.price
  end
end

function Session:GetPlayerBidForItem(player, item)
  if item:GetWinner() == player then return item:GetSalePrice() end

  local currentWinner, currentBid = self:GetCurrentBidForItem(item)
  if currentWinner == player then return currentBid end

  return nil
end

function Session:GetMinNextBidForItem(item)
  if item:GetWinner() then return nil end

  -- Use per-item minIncrement, fallback to session-wide
  local minIncrement = item:GetMinIncrement() or self.minIncrement

  local _, currentBid = self:GetCurrentBidForItem(item)
  if currentBid then return currentBid + minIncrement end

  return item:GetMinPrice()
end

function Session:GetBidTotal(player)
  local total = 0

  for _, bid in pairs(self.bids) do
    if not player or bid.player == player then
      total = total + (bid.price or 0)
    end
  end

  return total
end

function Session:RegisterBid(item, player, price, force)
  if not item then return end

  if item:GetStatus() ~= RaukinGDKP.STATUS.BIDDING then
    RaukinGDKP:Error("Attempted to bid on '"..item.name.."' not in bidding state")
    return false, "Bidding for this item is closed"
  end

  -- Use per-item minIncrement, fallback to session-wide
  local minIncrement = item:GetMinIncrement() or self.minIncrement

  local bid = self.bids[item] or {}
  if not force and bid and bid.price and price < bid.price + minIncrement then
    -- Reject bids lower than current + increment
    return false, "Bid must be at least "..bid.price + minIncrement
  end

  local minPrice = item:GetMinPrice()
  if not force and minPrice and price < minPrice then
    -- Reject bids lower than min price
    return false, "Bid must be at least "..minPrice
  end

  if not force and bid.player == player then
    -- Reject higher bids from current highest bidder
    return false, "Already highest bidder"
  end

  bid.player = player
  bid.price = price
  self.bids[item] = bid

  if player == RaukinGDKP.player then
    item.pendingBid = nil
  end

  if not force then
    self:FireMessage(RaukinGDKP.MESSAGE.BID_ITEM, item, player, price)
  end

  return true
end

function Session:AssignItem(item, winner, price)
  local bid = self.bids[item]
  if bid then
    bid.player = winner
    bid.price = price
  end

  if not item or (winner and self.assignments[item] == winner) then return end

  self.assignments[item] = winner
  item:SetWinner(winner, price)

  if winner and price and self.log then
    self.log:Write(item)
  end

  self:FireMessage(RaukinGDKP.MESSAGE.ASSIGN_ITEM, item, winner, price)
end

function Session:GetItemsAssignedToPlayer(player)
  local items = {}

  for item, winner in pairs(self.assignments) do
    if winner == player then table.insert(items, item) end
  end

  return items
end

function Session:RemoveItem(item)
  local index = self:GetIndexOfItem(item)
  if not index then return end
  self:RemoveItemAtIndex(index)
end

function Session:RemoveItemAtIndex(index)
  local maxIndex = self:GetNextIndex() - 1
  if index < 1 or index > maxIndex then return end

  local item = self.items[index]

  if item then
    self.items[index] = nil
    self.bids[item] = nil
    self.assignments[item] = nil

    if item.session == self then
      item.session = nil
    end

    self:FireMessage(RaukinGDKP.MESSAGE.DELETE_ITEM, index, item)
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE, index)
  end
end

function Session:Clear()
  for _, item in pairs(self.items) do
    if item.session == self then
      item.session = nil
    end
  end

  self.items = {}
  self.bids = {}
  self.assignments = {}

  self:FireMessage(RaukinGDKP.MESSAGE.DELETE_ALL_ITEMS)
  self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
end

-- Per-player state that lives on the client's item objects and must survive a full re-sync
local function CarryOverLocalState(oldItem, newItem)
  if not oldItem or not newItem or oldItem.id ~= newItem.id then return end
  newItem.watched = oldItem.watched
  newItem.pendingBid = oldItem.pendingBid
  newItem.assignedToNone = oldItem.assignedToNone
end

function Session:ImportItems(encodedItems, merge)
  local oldItems = self.items
  if not merge then
    self.items = {}
    self.assignments = {}
  end

  if not encodedItems or encodedItems == "" then
    if not merge and next(oldItems) then
      self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
      return true
    end
    return false
  end

  local elements = RaukinGDKP:Split(encodedItems, RaukinGDKP.SEPARATOR.LIST_ELEMENT)
  local itemsChanged = not merge and next(oldItems) ~= nil

  if #elements >= 2 then
    for i = 1, #elements, 2 do
      local index = tonumber(elements[i])
      local itemId, info = RaukinGDKP.Item:DecodeInfo(elements[i + 1])
      local existingItem = merge and index and self.items[index]

      if index and itemId and existingItem and existingItem.id == itemId then
        -- Update the existing object in place (no throw-away Item objects / item loads)
        local wasAssigned = existingItem:GetStatus() == RaukinGDKP.STATUS.ASSIGNED
        local reopened = wasAssigned and info.status and info.status ~= RaukinGDKP.STATUS.ASSIGNED
        -- Clear stale bids when OS bidding starts (main spec bid no longer valid)
        -- or when the host re-opens an item that was already assigned
        if (info.isOS and not existingItem:IsOS()) or reopened then
          self.bids[existingItem] = nil
        end
        if reopened then
          existingItem.assignedToNone = nil
        end
        existingItem:ImportInfo(info)
      elseif index and itemId then
        local newItem = RaukinGDKP.Item:CreateForId(itemId)
        newItem.info = info
        newItem.session = self
        CarryOverLocalState(existingItem or oldItems[index], newItem)
        self.items[index] = newItem
        itemsChanged = true
      end

      local item = index and self.items[index]
      if item and item:GetStatus() ~= RaukinGDKP.STATUS.ASSIGNED then
        self.assignments[item] = nil
      elseif item and item:GetWinner() then
        self.assignments[item] = item:GetWinner()
      end
    end
  end

  if itemsChanged then
    self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
  end

  return itemsChanged
end

function Session:ImportBids(encodedBids)
  self.bids = {}

  if not encodedBids then return end
  local elements = RaukinGDKP:Split(encodedBids, RaukinGDKP.SEPARATOR.LIST_ELEMENT)

  if #elements >= 3 then
    for i = 1, #elements, 3 do
      local index = tonumber(elements[i])
      local item = self:GetItemAtIndex(index)
      self.bids[item] = { player = elements[i + 1], price = tonumber(elements[i + 2]) }
    end
  end

  self:FireMessage(RaukinGDKP.MESSAGE.ON_CHANGE)
end
