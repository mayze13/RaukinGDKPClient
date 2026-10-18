local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

-- Lua APIs
local getmetatable, setmetatable = getmetatable, setmetatable

-- WoW APIs
local CreateFrame = CreateFrame

local SearchField = {}
SearchField.__index = SearchField
RaukinGDKP.SearchField = SearchField

local function UpdateText(self)
  if self.isFocused then return end

  -- Only put the placeholder into an EMPTY box. The old version called SetText(text) with
  -- the text that was already there, from inside OnTextSet: every SetText re-fired
  -- OnTextSet (SetText -> OnTextSet -> SetText ...) and OnTextChanged, and the client
  -- window rebuilt all item rows (and their bid boxes) on each of those calls.
  local text = self:GetText()
  if (not text or text == "") and self.placeholderText and self.placeholderText ~= "" then
    self.settingPlaceholder = true
    self:SetText(self.placeholderText)
    self.settingPlaceholder = nil
  end
end

local function UpdateColors(self)
  if self.isFocused or self:GetText() ~= self.placeholderText then
    self:SetTextColor(1, 1, 1, 1)
  else
    -- placeholder: dimmed, but still readable on dark ElvUI backdrops (was 0.4)
    self:SetTextColor(1, 1, 1, 0.6)
  end
end

local function EditBox_OnTextChanged(self)
  if not self.isFocused then return end
  self.filter:SetQuery(self:GetText())
end

local function EditBox_OnTextSet(self)
  if self.isFocused or self.settingPlaceholder then return end

  UpdateText(self)
  UpdateColors(self)
end

local function EditBox_OnEditFocusGained(self)
  self.isFocused = true

  if self:GetText() == self.placeholderText then
    self:SetText("")
  else
    self:HighlightText()
  end

  UpdateColors(self)
end

local function EditBox_OnEditFocusLost(self)
  self.isFocused = false

  UpdateText(self)
  UpdateColors(self)
end

function SearchField:Create(parent)
  local searchField = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	searchField:SetAutoFocus(false)
  searchField:SetTextInsets(4, 4, 0, 0)
  searchField:SetJustifyH("LEFT")
	searchField:SetHeight(22)

  searchField:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  searchField:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  searchField:SetScript("OnEditFocusGained", function(self) EditBox_OnEditFocusGained(self) end)
  searchField:SetScript("OnTextChanged", function(self) EditBox_OnTextChanged(self) end)
  searchField:SetScript("OnTextSet", function(self) EditBox_OnTextSet(self) end)
  searchField:SetScript("OnEditFocusLost", function(self) EditBox_OnEditFocusLost(self) end)

  searchField.filter = RaukinGDKP.Filter:CreateForName()

  -- Add inheritence from SearchField
  local meta = getmetatable(searchField)
  setmetatable(searchField, {
    __index = function(t, k)
      return SearchField[k] or meta.__index[k]
    end
  })

  return searchField
end

function SearchField:GetFilter()
  return self.filter
end

function SearchField:GetPlaceholderText()
  return self.placeholderText
end

function SearchField:SetPlaceholderText(placeholderText)
  self.placeholderText = placeholderText
  UpdateText(self)
  UpdateColors(self)
end
