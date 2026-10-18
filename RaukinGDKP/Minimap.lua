-- RaukinGDKP minimap button (no library needed)
--   Left-click:  bidding window
--   Right-click: raid lead window (if RaukinGDKPHost is installed), otherwise bidding window
--   Drag:        move around the minimap
--   Hide/show:   /rgdkp minimap   (raid lead: also Host window > Settings)

local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

local math = math
local RADIUS = 80
local button

local function GetHost()
  return RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKPHost", true)
end

local function UpdatePosition()
  if not button then return end
  local angle = math.rad(RaukinGDKP:GetPref("minimapAngle", 215))
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function OnDragUpdate()
  local mx, my = Minimap:GetCenter()
  local scale = Minimap:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local angle = math.deg(math.atan2(cy - my, cx - mx))
  RaukinGDKP:SetPref("minimapAngle", angle)
  UpdatePosition()
end

local function CreateButton()
  if button then return button end

  button = CreateFrame("Button", "RaukinGDKPMinimapButton", Minimap)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
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

  button:SetScript("OnClick", function(_, mouseButton)
    local host = GetHost()
    if mouseButton == "RightButton" and host and host.ToggleWindow then
      host:ToggleWindow()
    elseif RaukinGDKP.client then
      RaukinGDKP.client:Toggle()
    end
  end)
  button:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", OnDragUpdate)
  end)
  button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)
  button:SetScript("OnEnter", function(self)
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
