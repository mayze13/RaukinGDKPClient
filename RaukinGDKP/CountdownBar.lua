local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")

-- Lua APIs
local getmetatable, setmetatable, math = getmetatable, setmetatable, math

-- WoW APIs
local CreateFrame = CreateFrame
local GetServerTime = RaukinGDKPCompat.GetServerTime

local CountdownBar = {}
CountdownBar.__index = CountdownBar
RaukinGDKP.CountdownBar = CountdownBar

local TICK_INTERVAL = 0.05  -- 50ms throttle (20 updates/sec)

local function UpdateCountdownBar(self, dt)
  local item = self.item

  if not item or not self.rawValue then
    self:Hide()
    return
  end

  if item:GetStatus() ~= RaukinGDKP.STATUS.BIDDING then
    self:Hide()
    return
  end

  -- Check if session is paused
  local isPaused = item.session and item.session.isPaused
  if isPaused then
    -- Use paused remaining time, don't decrement
    if item.pausedRemaining then
      self.rawValue = item.pausedRemaining
    end
    dt = 0  -- Don't decrement while paused
  end

  local remaining = math.max(0, self.rawValue - (dt or 0))
  self.rawValue = remaining

  local duration = self.duration or 180
  local countdown = item.session and item.session.countdown or 10

  -- Calculate color based on time remaining
  local percent = duration > 0 and (remaining / duration) or 0
  local r, g, b

  -- Use grey for OS bidding, green->yellow->red for normal
  if item:IsOS() then
    r, g, b = 0.5, 0.5, 0.5  -- Grey for OS
  elseif percent > 0.5 then
    -- Green to Yellow (100% to 50%)
    r = (1 - percent) * 2
    g = 1
    b = 0
  else
    -- Yellow to Red (50% to 0%)
    r = 1
    g = percent * 2
    b = 0
  end
  self:SetStatusBarColor(r, g, b)

  -- Make bar more visible during final countdown
  if remaining < countdown then
    self:SetAlpha(0.4)
  else
    self:SetAlpha(0.25)
  end

  if remaining == 0 then
    self:Hide()
  else
    self:Show()
    self:SetValue(remaining)
  end
end

function CountdownBar:Create(parent)
  local countdownBar = CreateFrame("StatusBar", nil, parent)

  -- Add dark background so we can see the bar shrinking
  local bg = countdownBar:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetAllPoints()
  bg:SetVertexColor(0.1, 0.1, 0.1, 0.8) -- Dark gray background
  countdownBar.bg = bg

  countdownBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8", "ARTWORK")
  -- ElvUI: Primary texture (General -> Media), follows live changes; no-op without ElvUI
  if RaukinGDKPSkin then RaukinGDKPSkin:StatusBar(countdownBar) end
  countdownBar:SetOrientation("HORIZONTAL") -- Fill from left to right
  countdownBar.elapsed = 0

  -- Throttled OnUpdate - only processes every 50ms
  countdownBar:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    if self.elapsed < TICK_INTERVAL then return end

    local actualDt = self.elapsed
    self.elapsed = 0
    UpdateCountdownBar(self, actualDt)
  end)

  -- Add inheritence from CountdownBar
  local meta = getmetatable(countdownBar)
  setmetatable(countdownBar, {
    __index = function(t, k)
      return CountdownBar[k] or meta.__index[k]
    end
  })

  return countdownBar
end

function CountdownBar:CountdownItem(item, topBidder)
  self.item = item
  self.topBidder = topBidder

  local expiration = item and item:GetExpiration()
  -- Use GetServerTime() directly to stay in sync with host's expiration timestamp
  -- The custom clock (RaukinGDKP:GetTime()) can drift if the game is minimized
  local currentTime = GetServerTime()

  -- If no expiration set, hide the bar
  if not expiration or expiration == 0 then
    self.rawValue = nil
    self:Hide()
    return
  end

  self.rawValue = expiration - currentTime

  -- Use the actual countdown duration, fallback to session bidDuration
  local duration = item and item:GetCountdownDuration()
  if not duration or duration == 0 then
    duration = item and item.session and item.session.bidDuration or 180
  end
  self.duration = duration -- Store for color calculation

  -- Debug output disabled
  -- RaukinGDKP:Debug("CountdownBar: exp=" .. tostring(expiration) .. " time=" .. tostring(math.floor(currentTime)) .. " rawValue=" .. tostring(math.floor(self.rawValue)) .. " duration=" .. tostring(duration))

  -- Set bar range from 0 to full duration
  self:SetMinMaxValues(0, duration)
  -- Set initial color based on OS status (grey for OS, green for normal)
  if item:IsOS() then
    self:SetStatusBarColor(0.5, 0.5, 0.5)
  else
    self:SetStatusBarColor(0, 1, 0)
  end
  self:SetAlpha(0.25)

  UpdateCountdownBar(self)
end
