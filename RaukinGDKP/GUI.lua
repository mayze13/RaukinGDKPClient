local AceGUI = RaukinLibStub("RaukinAceGUI-3.0")
local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

local GUI = {}
GUI.__index = GUI
RaukinGDKP.GUI = GUI

local Table = {}
Table.__index = Table
GUI.Table = Table

-- Lua APIs
local _G, getmetatable, setmetatable = _G, getmetatable, setmetatable
local math, pairs, table = math, pairs, table

-- WoW APIs
local ACCEPT, DECLINE = ACCEPT, DECLINE
local GameTooltip, StaticPopupDialogs, StaticPopup_Show = GameTooltip, StaticPopupDialogs, StaticPopup_Show

-- Similar to default Fill, but with space at the top
AceGUI:RegisterLayout("RaukinGDKPWindow",
function(content, children)
  local width = content.width or content:GetWidth() or 0
  local offset = content.yOffset or 0

  if children[1] then
    local child = children[1]
    child:SetWidth(content:GetWidth() or 0)
    child:SetHeight(content:GetHeight() or 0)
    child.frame:ClearAllPoints()
    child.frame:SetPoint("TOPLEFT", content, 0, offset)
    child.frame:SetPoint("BOTTOMRIGHT", content)
    child.frame:Show()
  end

  if content.obj.LayoutFinished then
    content.obj:LayoutFinished(nil, nil)
  end
end
)

-- Window
--
-- Minimal AceGUI "Frame":
--   * no status bar strip and no bottom Close button (Escape or the X closes it)
--   * one TOPLEFT anchor, so it follows the mouse when dragged; position saved on drag stop
--   * height = chrome + min(rows, maxRows) * ROW_HEIGHT (FitToRows), the list scrolls the rest
--   * the bottom / bottom-right grip snaps to whole rows and stores the new maxRows,
--     width stays freely resizable

local ROW_HEIGHT = 50
local DEFAULT_MAX_ROWS = 8
local MAX_ROWS_LIMIT = 20
local MIN_WIDTH = 560
local CONTENT_TOP = 27     -- AceGUI Frame content TOPLEFT offset (AceGUIContainer-Frame.lua)
local CONTENT_BOTTOM = 14  -- bottom padding left for the resize grip

GUI.ROW_HEIGHT = ROW_HEIGHT
GUI.DEFAULT_MAX_ROWS = DEFAULT_MAX_ROWS
GUI.MAX_ROWS_LIMIT = MAX_ROWS_LIMIT

function GUI:GetMaxRows()
  -- one-time update: older versions stopped growing at 5 rows; the window now grows to 8
  if not RaukinGDKP:GetPref("maxRowsMigrated8", false) then
    RaukinGDKP:SetPref("maxRowsMigrated8", true)
    local saved = tonumber(RaukinGDKP:GetPref("maxRows", DEFAULT_MAX_ROWS))
    if saved and saved < DEFAULT_MAX_ROWS then RaukinGDKP:SetPref("maxRows", DEFAULT_MAX_ROWS) end
  end
  local value = tonumber(RaukinGDKP:GetPref("maxRows", DEFAULT_MAX_ROWS)) or DEFAULT_MAX_ROWS
  return math.max(1, math.min(MAX_ROWS_LIMIT, math.floor(value)))
end

function GUI:SetMaxRows(value)
  value = math.max(1, math.min(MAX_ROWS_LIMIT, math.floor(tonumber(value) or DEFAULT_MAX_ROWS)))
  RaukinGDKP:SetPref("maxRows", value)
  return value
end

local function HasPoint(frame, which)
  for i = 1, frame:GetNumPoints() do
    if frame:GetPoint(i) == which then return true end
  end
  return false
end

function GUI:CreateWindow(name, title, defaultWidth)
  local window = _G[name] or AceGUI:Create("Frame")
  local frame = window.frame
  window:SetTitle(title)
  window:SetLayout("RaukinGDKPWindow")
  window:SetCallback("OnClose", function(w) w.table:Clear() end)

  if not defaultWidth then defaultWidth = 650 end
  local widthKey, leftKey, topKey = name.."Width", name.."Left", name.."Top"

  -- Chrome: drop the AceGUI status strip and its bottom Close button
  local statusbg = window.statustext:GetParent()
  if statusbg then statusbg:Hide() end
  for i = 1, select("#", frame:GetChildren()) do
    local child = select(i, frame:GetChildren())
    if child and child:GetObjectType() == "Button" and child.GetText and child:GetText() == CLOSE then
      child:Hide()
    end
  end
  window.content:ClearAllPoints()
  window.content:SetPoint("TOPLEFT", 17, -CONTENT_TOP)
  window.content:SetPoint("BOTTOMRIGHT", -17, CONTENT_BOTTOM)

  -- X close button (top right); ElvUI/AddOnSkins skin it through Skin:Children
  local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", -2, -2)
  closeButton:SetScript("OnClick", function() window:Hide() end)
  closeButton:SetFrameLevel(frame:GetFrameLevel() + 20)   -- always above grips / slider
  window.closeButton = closeButton

  -- Total fixed height around the item list (content.yOffset is set by the caller)
  function window:GetChromeHeight()
    return CONTENT_TOP - (self.content.yOffset or 0) + CONTENT_BOTTOM + (self.bottomBarSpace or 0)
  end

  -- Size the window to show `rowCount` rows (capped at maxRows, at least 1)
  function window:FitToRows(rowCount)
    self.lastRowCount = rowCount or self.lastRowCount or 0
    if self.frame.raukinSizing then return end
    local visible = math.max(1, math.min(self.lastRowCount, GUI:GetMaxRows()))
    local height = self:GetChromeHeight() + visible * ROW_HEIGHT
    if math.abs((self.frame:GetHeight() or 0) - height) > 0.5 then
      self:SetHeight(height)
    end
  end

  local function UpdateResizeBounds()
    local chrome = window:GetChromeHeight()
    if frame.SetResizeBounds then -- WoW 10.0
      frame:SetResizeBounds(MIN_WIDTH, chrome + ROW_HEIGHT, 2000, chrome + MAX_ROWS_LIMIT * ROW_HEIGHT)
    else
      frame:SetMinResize(MIN_WIDTH, chrome + ROW_HEIGHT)
      if frame.SetMaxResize then frame:SetMaxResize(2000, chrome + MAX_ROWS_LIMIT * ROW_HEIGHT) end
    end
  end
  window.UpdateResizeBounds = UpdateResizeBounds

  -- Status bar along the bottom edge (like the old AceGUI status bar); the list ends above it
  function window:AddBottomBar(height)
    if self.bottomBar then return self.bottomBar end
    height = height or 22
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 15, 13)
    bar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -28, 13)   -- keeps the corner grip free
    bar:SetHeight(height)
    bar:SetBackdrop({
      bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 3, right = 3, top = 5, bottom = 3 },
    })
    bar:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    bar:SetBackdropBorderColor(0.4, 0.4, 0.4)
    bar:SetFrameLevel(frame:GetFrameLevel() + 5)
    self.bottomBar = bar
    self.bottomBarSpace = height + 13 + 3 - CONTENT_BOTTOM
    self.content:ClearAllPoints()
    self.content:SetPoint("TOPLEFT", 17, -CONTENT_TOP)
    self.content:SetPoint("BOTTOMRIGHT", -17, CONTENT_BOTTOM + self.bottomBarSpace)
    UpdateResizeBounds()
    self:FitToRows()
    return bar
  end

  -- Position: a single TOPLEFT anchor. AceGUI's ApplyStatus left a CENTER anchor; the old
  -- code then added LEFT and BOTTOM on top of it (3 anchors), so StartMoving fought them.
  local function SavePosition()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    left, top = math.floor(left + 0.5), math.floor(top + 0.5)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    RaukinGDKP:SetPref(leftKey, left)
    RaukinGDKP:SetPref(topKey, top)
    RaukinGDKP:SetPref(widthKey, math.floor(frame:GetWidth() + 0.5))
  end
  window.SavePosition = SavePosition

  function window:RestorePosition()
    frame:ClearAllPoints()
    local left, top = tonumber(RaukinGDKP:GetPref(leftKey)), tonumber(RaukinGDKP:GetPref(topKey))
    if left and top then
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
      frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end
  end

  -- /rgdkp center: centred, single anchor, saved position cleared
  function window:Center()
    frame:ClearAllPoints()
    frame:SetPoint("TOP", UIParent, "CENTER", 0, (frame:GetHeight() or 0) / 2)
    RaukinGDKP:SetPref(leftKey, nil)
    RaukinGDKP:SetPref(topKey, nil)
  end

  window:SetWidth(RaukinGDKP:GetPref(widthKey) or defaultWidth)
  window:RestorePosition()

  -- Moving and resizing are done by hand: the cursor's movement since mouse-down is added to
  -- the window's start position / size and applied as a single TOPLEFT anchor every frame.
  -- No StartMoving/StartSizing, so nothing can pull the window back to an old anchor or
  -- offset the grab point from the cursor.
  local drag -- active drag: mode, which edges, cursor and window state at mouse-down
  local driver = CreateFrame("Frame")
  driver:Hide()

  local function CursorXY()
    local x, y = GetCursorPosition()
    local scale = frame:GetEffectiveScale()
    return x / scale, y / scale
  end

  local function StopDrag()
    if not drag then return end
    local mode, height = drag.mode, drag.h
    drag = nil
    driver:Hide()
    frame.raukinSizing = nil
    if mode == "size" and height then
      local rows = math.floor((frame:GetHeight() - window:GetChromeHeight()) / ROW_HEIGHT + 0.5)
      GUI:SetMaxRows(rows)
    end
    SavePosition()
    window:FitToRows()
  end

  driver:SetScript("OnUpdate", function()
    if not drag then driver:Hide() return end
    if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then StopDrag() return end

    local x, y = CursorXY()
    local dx, dy = x - drag.cx, y - drag.cy
    if drag.mode == "move" then
      -- keep the window on screen
      local width, height = frame:GetWidth(), frame:GetHeight()
      local left = math.max(0, math.min(drag.left + dx, UIParent:GetWidth() - width))
      local top = math.max(height, math.min(drag.top + dy, UIParent:GetHeight()))
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    else
      if drag.w then
        window:SetWidth(math.max(MIN_WIDTH, drag.width + dx))
      end
      if drag.h then -- height snaps to whole rows
        local chrome = window:GetChromeHeight()
        local rows = math.floor((drag.height - dy - chrome) / ROW_HEIGHT + 0.5)
        rows = math.max(1, math.min(MAX_ROWS_LIMIT, rows))
        window:SetHeight(chrome + rows * ROW_HEIGHT)
      end
    end
  end)

  local function StartDrag(mode, w, h)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local x, y = CursorXY()
    drag = {
      mode = mode, w = w, h = h, cx = x, cy = y,
      left = left, top = top, width = frame:GetWidth(), height = frame:GetHeight(),
    }
    -- pin the top-left corner so resizing only moves the right / bottom edges
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    frame.raukinSizing = (mode == "size") or nil
    driver:Show()
  end

  frame:SetMovable(false)
  frame:EnableMouse(true)
  frame:RegisterForDrag()
  frame:SetScript("OnDragStart", nil)
  frame:SetScript("OnDragStop", nil)
  frame:SetScript("OnMouseDown", function(_, button)
    AceGUI:ClearFocus()
    if button == "LeftButton" then StartDrag("move") end
  end)
  frame:SetScript("OnMouseUp", StopDrag)
  frame:HookScript("OnHide", StopDrag)

  -- Right-edge resize grip starts `y` below the window top (keeps it off top-row buttons)
  function window:SetRightGripTop(y)
    local grip = self.rightGrip
    if not grip then return end
    grip:ClearAllPoints()
    grip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, y)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 25)
  end

  -- AceGUI's title bar and resize grips use StartMoving/StartSizing: take them over.
  -- The title bar lets clicks through to the window (which moves it); the grips resize.
  for i = 1, select("#", frame:GetChildren()) do
    local child = select(i, frame:GetChildren())
    if child and child:GetObjectType() == "Frame" and child:GetScript("OnMouseUp") then
      local isCorner = child:GetNumPoints() == 1 and HasPoint(child, "BOTTOMRIGHT") -- sizer_se
      local isBottom = HasPoint(child, "BOTTOMLEFT")                                 -- sizer_s
      local isRight = not isCorner and HasPoint(child, "TOPRIGHT")                   -- sizer_e
      if isRight then
        -- AceGUI's right-edge grip (25px wide) runs up to the very top corner and swallowed
        -- clicks on the X and the top-right buttons: a thin strip below the title area instead
        -- (SetRightGripTop moves it below the caller's own top row)
        child:SetWidth(10)
        window.rightGrip = child
        window:SetRightGripTop(-38)
      elseif isBottom then
        child:SetHeight(10) -- thin strip along the bottom edge, under the bottom bar
      end
      if isCorner or isBottom or isRight then
        local w, h = isCorner or isRight, isCorner or isBottom
        child:SetScript("OnMouseDown", function(_, button)
          if button == "LeftButton" then StartDrag("size", w, h) end
        end)
        child:SetScript("OnMouseUp", StopDrag)
      else
        child:EnableMouse(false) -- title bar
      end
    end
  end

  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
  frame:SetBackdropColor(0, 0, 0, 1)

  local tableContainer = AceGUI:Create("SimpleGroup")
  tableContainer:SetLayout("Fill")
  window:AddChild(tableContainer)

  window.table = GUI:CreateTable()
  tableContainer:AddChild(window.table)

  -- Shown instead of rows when the list is empty
  local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("TOPLEFT", tableContainer.frame, "TOPLEFT", 0, 0)
  emptyText:SetPoint("BOTTOMRIGHT", tableContainer.frame, "TOPRIGHT", 0, -ROW_HEIGHT)
  emptyText:Hide()
  window.emptyText = emptyText

  UpdateResizeBounds()

  table.insert(UISpecialFrames, name)
  _G[name] = window

  return window
end

-- Table

function GUI:CreateTable()
  local table = AceGUI:Create("ScrollFrame")
  table:SetLayout("List")

  -- Add inheritence from Table
  local meta = getmetatable(table)
  setmetatable(table, {
    __index = function(t, k)
      return Table[k] or meta.__index[k]
    end
  })

  table.rows = {}

  return table
end

-- string, number, any, function(row, data)
function Table:CreateRow(className, index, data, config)
  self:DeleteRowAtIndex(index)

  local row = AceGUI:Create(className)
  if not row then
    RaukinGDKP:Error("Table failed to create row of unknown type '"..className.."'")
    return
  end

  row:SetFullWidth(true)

  local rowInfo = row:GetUserDataTable()
  rowInfo.className = className
  rowInfo.table = self
  rowInfo.config = config

  row:SetCallback("OnRelease", function()
    if rowInfo.data and rowInfo.data.UnregisterCallback then
      rowInfo.data:UnregisterCallback(RaukinGDKP.MESSAGE.ON_CHANGE)
    end
  end)

  self.rows[index] = row
  self:ReloadRowAtIndex(index, data)

  local sibling = nil
  for i, r in pairs(self.rows) do
    if i > index then
      sibling = r
      break
    end
  end

  self:AddChild(row, sibling)

  return row
end

function Table:ReloadRow(row, data)
  for index, it in pairs(self.rows) do
    if it == row then
      self:ReloadRowAtIndex(index, data)
      break
    end
  end
end

function Table:ReloadRowByData(data)
  if not data then return end
  for index, row in pairs(self.rows) do
    local rowInfo = row:GetUserDataTable()
    if rowInfo.data == data then
      self:ReloadRowAtIndex(index, data)
      return true
    end
  end
  return false
end

function Table:ReloadRowAtIndex(index, data)
  local row = self.rows[index]
  if not row then return end

  local rowInfo = row:GetUserDataTable()

  if rowInfo.data and rowInfo.data.UnregisterCallback then
    rowInfo.data:UnregisterCallback(RaukinGDKP.MESSAGE.ON_CHANGE)
  end

  rowInfo.data = data or rowInfo.data

  if rowInfo.data and rowInfo.data.RegisterCallback then
    rowInfo.data:RegisterCallback(RaukinGDKP.MESSAGE.ON_CHANGE, function()
      if rowInfo.table then rowInfo.table:ReloadRow(row) end
    end)
  end

  if rowInfo.config then
    rowInfo.config(row, rowInfo.data)
  end
end

function Table:DeleteRow(row)
  for index, it in pairs(self.rows) do
    if it == row then
      self:DeleteRowAtIndex(index)
      break
    end
  end
end

function Table:DeleteRowAtIndex(index)
  local row = self.rows[index]
  self.rows[index] = nil

  if not row then return end
  row:Release()

  for i = 1, #self.children do
    if self.children[i] == row then
      table.remove(self.children, i)
      break
    end
  end

  self:DoLayout()
end

function Table:GetRowCount()
  local count = 0
  for _ in pairs(self.rows) do
    count = count + 1
  end
  return count
end

function Table:GetMaxIndex()
  local maxIndex = 0
  for index in pairs(self.rows) do
    maxIndex = math.max(maxIndex, index)
  end
  return maxIndex
end

function Table:Clear()
  for index, row in pairs(self.rows) do
    row:Release()
    self.rows[index] = nil
  end
  self.children = {}
end
