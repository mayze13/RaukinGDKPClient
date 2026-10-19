-- RaukinGDKP minimap button (no library needed)
--   Left-click:  bidding window
--   Right-click: raid lead window (if RaukinGDKPHost is installed), otherwise bidding window
--   Drag:        move around the minimap
--   Hide/show:   /rgdkp minimap   (raid lead: also Host window > Settings)

local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

local math = math
local button
local dragAngle -- angle while dragging; saved on drag stop

local function GetHost()
  return RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKPHost", true)
end

-- On the minimap's edge. The radius follows the minimap's size (ElvUI resizes it), and
-- square minimaps (ElvUI, GetMinimapShape) put the button on the square's edge.
local function UpdatePosition()
  if not button then return end
  local angle = math.rad(dragAngle or RaukinGDKP:GetPref("minimapAngle", 215))
  local x, y = math.cos(angle), math.sin(angle)
  local radius = (Minimap:GetWidth() or 140) / 2 + 10
  if GetMinimapShape and GetMinimapShape() == "SQUARE" then
    radius = (Minimap:GetWidth() or 140) / 2 + 5
    local edge = math.max(math.abs(x), math.abs(y))
    if edge > 0 then x, y = x / edge, y / edge end
  end
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  dragAngle = math.deg(math.atan2(cy - my, cx - mx))
  UpdatePosition()
end

local function CreateButton()
  if button then return button end

  button = CreateFrame("Button", "RaukinGDKPMinimapButton", Minimap)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(Minimap:GetFrameLevel() + 8)   -- above ElvUI's minimap overlays
  button:SetSize(31, 31)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local background = button:CreateTexture(nil, "BACKGROUND")
  background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  background:SetSize(20, 20)
  background:SetPoint("TOPLEFT", 7, -5)

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", 7, -5)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(self, mouseButton)
    if self.dragged then return end   -- releasing a drag never toggles a window
    local host = GetHost()
    if mouseButton == "RightButton" and host and host.ToggleWindow then
      host:ToggleWindow()
    elseif RaukinGDKP.client then
      RaukinGDKP.client:Toggle()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self.dragging, self.dragged = true, true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", OnDragUpdate)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    if dragAngle then RaukinGDKP:SetPref("minimapAngle", dragAngle) end
    dragAngle = nil
    self.dragging = nil
    UpdatePosition()
  end)
  -- OnDragStop can come before OnClick: the drag flag is cleared on the next press
  button:SetScript("OnMouseDown", function(self) self.dragged = nil end)
  button:SetScript("OnEnter", function(self)
    if self.dragging then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("RaukinGDKP")
    GameTooltip:AddLine("Left-click: bidding window", 1, 1, 1)
    if GetHost() then GameTooltip:AddLine("Right-click: raid lead window", 1, 1, 1) end
    GameTooltip:AddLine("Drag: move", 0.7, 0.7, 0.7)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  UpdatePosition()
  return button
end

function RaukinGDKP:SetMinimapButtonShown(shown)
  self:SetPref("minimapHidden", not shown)
  CreateButton()
  if shown then button:Show() else button:Hide() end
end

function RaukinGDKP:ToggleMinimapButton()
  local hidden = self:GetPref("minimapHidden", false)
  self:SetMinimapButtonShown(hidden)   -- hidden -> show, shown -> hide
  self:Info(hidden and "Minimap button shown." or "Minimap button hidden. /rgdkp minimap to show it again.")
end

-- create after the saved settings are loaded
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
  CreateButton()
  if RaukinGDKP:GetPref("minimapHidden", false) then button:Hide() else button:Show() end
end)
