local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

-- Lua APIs
local setmetatable, string, table, tonumber = setmetatable, string, table, tonumber

-- Abstract class

local Filter = {}
RaukinGDKP.Filter = Filter

function Filter:Create(t)
  t = t or {}
  setmetatable(t, self)
  self.__index = self
  return t
end

function Filter:Evaluate(item)
  return true
end

-- ClassFilter - Simplified: Everyone sees weapons, cloaks, trinkets, rings, necks
-- For armor: each class only sees their PRIMARY armor type

-- Maps class ID to their primary armor subclass ID
-- ["Shields"] = 6,
-- ["Librams"] = 7,
-- ["Idols"] = 8,
-- ["Totems"] = 9,
-- ["Sigils"] = 10,
-- Cloth=1, Leather=2, Mail=3, Plate=4
local CLASS_PRIMARY_ARMOR = {
  [1] = {4, 6},     -- Warrior: Plate, Shields
  [2] = {4, 6, 7},  -- Paladin: Plate, Librams, Shields
  [3] = {3},        -- Hunter: Mail
  [4] = {2},        -- Rogue: Leather
  [5] = {1},        -- Priest: Cloth
  [6] = {4, 10},    -- Death Knight: Plate, Sigil
  [7] = {3, 9, 6},  -- Shaman: Mail, Shields, Totems
  [8] = {1},        -- Mage: Cloth
  [9] = {1},        -- Warlock: Cloth
  [11] = {2, 8},    -- Druid: Leather, Idols
}

local ClassFilter = Filter:Create()
function Filter:CreateForPlayerClassId(classId)
  return ClassFilter:Create({
    classId = classId
  })
end

function ClassFilter:Evaluate(item)
  -- If item data not loaded yet, show it (will re-filter when data loads)
  if not item.classId then return true end

  -- Weapons (classId 2): everyone sees all weapons
  if item.classId == 2 then return true end

  -- Non-armor, non-weapon: everyone sees (consumables, etc.)
  if item.classId ~= 4 then return true end

  -- From here on, it's armor (classId 4)

  -- Cloak: everyone sees
  if item.equipLoc == "INVTYPE_CLOAK" then return true end

  -- Miscellaneous (trinkets, rings, necks): everyone sees
  -- subclassId 0 = Miscellaneous
  if item.subclassId == 0 then return true end

  -- Safeguard against nil player class
  if not self.classId then return true end

  -- Get player's primary armor type
  local primaryArmorList = CLASS_PRIMARY_ARMOR[self.classId]
  if not primaryArmorList then return true end

  -- Only show if item matches player's primary armor type
  for _, allowedSubclass in ipairs(primaryArmorList) do
    if item.subclassId == allowedSubclass then
      return true
    end
  end
end

local NameFilter = Filter:Create()
function Filter:CreateForName()
  return NameFilter:Create({
    query = nil,
    numericQuery = nil,
  })
end

function NameFilter:SetQuery(query)
  self.query = query and string.lower(query) or nil
  self.numericQuery = tonumber(query)
end

function NameFilter:Evaluate(item)
  if not self.query or self.query == "" then return true end
  -- plain find: typing "(" or "%" must not raise a pattern error
  return self.numericQuery == item.ilvl or (item.name and string.find(string.lower(item.name), self.query, 1, true)) and true or false
end

local WatchedFilter = Filter:Create()
function Filter:CreateForWatched()
  return WatchedFilter:Create()
end

function WatchedFilter:Evaluate(item)
  return item and item:IsWatched()
end

local ActiveFilter = Filter:Create()
function Filter:CreateForActive()
  return ActiveFilter:Create()
end

function ActiveFilter:Evaluate(item)
  if not item then return false end

  -- Show only items that are PENDING or BIDDING (hide ASSIGNED items)
  local status = item:GetStatus()
  return status == RaukinGDKP.STATUS.PENDING or status == RaukinGDKP.STATUS.BIDDING
end

local CompositeFilter = Filter:Create()
function Filter:CreateComposite()
  return CompositeFilter:Create({
    filters = {}
  })
end

function CompositeFilter:AddFilter(filter)
  if not self:ContainsFilter(filter) then
    table.insert(self.filters, filter)
  end
end

function CompositeFilter:RemoveFilter(filter)
  for i = 1, #self.filters do
    if self.filters[i] == filter then
      table.remove(self.filters, i)
      return
    end
  end
end

function CompositeFilter:ContainsFilter(filter)
  for i = 1, #self.filters do
    if self.filters[i] == filter then return true end
  end
  return false
end

function CompositeFilter:Evaluate(item)
  for i = 1, #self.filters do
    if not self.filters[i]:Evaluate(item) then return false end
  end
  return true
end
