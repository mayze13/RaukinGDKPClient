-- RaukinGDKP: "is there a newer release?"
--   WoW 3.3.5 cannot reach the internet, so the addon can't ask GitHub directly. Instead every
--   copy tells the others which version it runs, on a hidden addon channel (guild + group).
--   When someone has a newer release, a small window opens with the GitHub link to copy.
--   * the newest version seen is remembered, so the reminder also comes at the next login
--   * the window waits until combat is over
--   * RaukinGDKPHost registers itself here as well ("host"), so hosts hear about both addons;
--     raiders without the host addon never get host reminders
--   /rgdkp version shows what you run and the newest version seen.

local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")
local C_Timer = RaukinGDKPCompat.C_Timer

local VersionCheck = {}
RaukinGDKPVersionCheck = VersionCheck

local PREFIX = "RGDKPVer"            -- separate prefix: older versions simply ignore it
local PROTOCOL = 1
local SEND_COOLDOWN = 30             -- seconds between announcements on the same channel
local REPLY_COOLDOWN = 300           -- seconds before the same outdated player gets another reply

local components = {}                -- [key] = { key, title, version, url, newest, notified }
local order = {}                     -- keys in the order they were registered
local lastSent, lastReply = {}, {}
local pendingWindow = false

local function Print(msg)
  print("|cFFFF6900[RaukinGDKP]|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Versions: "3.4" < "3.4.1" < "3.5", and "3.3.0g" < "3.3.0i" (a letter counts after the number)
-- ---------------------------------------------------------------------------

local function ParseVersion(version)
  local parts = {}
  for chunk in tostring(version or ""):gmatch("[^%.]+") do
    local number, letter = chunk:match("^(%d*)(%a?)")
    parts[#parts + 1] = (tonumber(number) or 0) * 100 + (letter ~= "" and (letter:lower():byte() - 96) or 0)
  end
  return parts
end

-- -1 if a is older than b, 1 if a is newer, 0 if they are the same
function VersionCheck.Compare(a, b)
  local pa, pb = ParseVersion(a), ParseVersion(b)
  for i = 1, math.max(#pa, #pb) do
    local x, y = pa[i] or 0, pb[i] or 0
    if x ~= y then return x < y and -1 or 1 end
  end
  return 0
end
local Compare = VersionCheck.Compare

local function IsValidVersion(version)
  return type(version) == "string" and #version <= 16 and version:match("^%d+[%w%.]*$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Remembered "newest seen" (survives a relog)
-- ---------------------------------------------------------------------------

local function GetSaved()
  local saved = RaukinGDKP:GetPref("newerVersions", nil)
  if type(saved) ~= "table" then saved = {} end
  return saved
end

local function SaveNewest(key, version)
  local saved = GetSaved()
  saved[key] = version
  RaukinGDKP:SetPref("newerVersions", saved)
end

-- ---------------------------------------------------------------------------
-- Window with the links
-- ---------------------------------------------------------------------------

local window
local ROW_HEIGHT = 58

local function CreateRow(index)
  local row = {}
  local top = -44 - (index - 1) * ROW_HEIGHT

  row.text = window:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.text:SetPoint("TOPLEFT", 22, top)
  row.text:SetWidth(396)
  row.text:SetJustifyH("LEFT")

  -- Read-only link box: typing puts the link back, a click selects all of it
  local box = CreateFrame("EditBox", "RaukinGDKPUpdateLink" .. index, window, "InputBoxTemplate")
  box:SetSize(390, 20)
  box:SetPoint("TOPLEFT", 28, top - 20)
  box:SetAutoFocus(false)
  box:SetScript("OnTextChanged", function(self)
    if self.url and self:GetText() ~= self.url then
      self:SetText(self.url)
      self:HighlightText()
    end
  end)
  box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
  box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  row.box = box

  return row
end

local function CreateWindow()
  window = CreateFrame("Frame", "RaukinGDKPUpdateWindow", UIParent)
  window:SetWidth(440)
  window:SetPoint("TOP", 0, -140)
  window:SetFrameStrata("FULLSCREEN_DIALOG")   -- same strata as the host windows, above WeakAuras
  window:SetToplevel(true)
  window:SetMovable(true)
  window:EnableMouse(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", window.StartMoving)
  window:SetScript("OnDragStop", window.StopMovingOrSizing)
  window:SetClampedToScreen(true)
  window:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 8, right = 8, top = 8, bottom = 8 }
  })
  window:SetBackdropColor(0, 0, 0, 0.9)

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -16)
  title:SetText("Raukin GDKP - update available")

  local closeBtn = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  closeBtn:SetPoint("TOPRIGHT", -5, -5)

  window.hint = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  window.hint:SetWidth(396)
  window.hint:SetJustifyH("LEFT")
  window.hint:SetTextColor(0.7, 0.7, 0.7)
  window.hint:SetText("Click a link, press Ctrl+C to copy it and paste it into your browser. Replace the addon folder, then /reload.")

  window.rows = {}
  table.insert(UISpecialFrames, "RaukinGDKPUpdateWindow")
  window:Hide()

  if RaukinGDKPSkin then RaukinGDKPSkin:Window(window, { slider = false }) end
end

local function ShowWindow()
  local outdated = {}
  for _, key in ipairs(order) do
    local c = components[key]
    if c.newest and Compare(c.newest, c.version) > 0 then outdated[#outdated + 1] = c end
  end
  if #outdated == 0 then return end

  if not window then CreateWindow() end
  for i, c in ipairs(outdated) do
    local row = window.rows[i] or CreateRow(i)
    window.rows[i] = row
    row.text:SetText(string.format("%s |cFF00FF00%s|r is out (you have |cFFFF5555%s|r):", c.title, c.newest, c.version))
    row.box.url = c.url
    row.box:SetText(c.url)
    row.box:SetCursorPosition(0)
    row.text:Show()
    row.box:Show()
  end
  for i = #outdated + 1, #window.rows do
    window.rows[i].text:Hide()
    window.rows[i].box:Hide()
  end

  window.hint:ClearAllPoints()
  window.hint:SetPoint("TOPLEFT", 22, -44 - #outdated * ROW_HEIGHT)
  window:SetHeight(44 + #outdated * ROW_HEIGHT + 48)
  window:Show()
  if RaukinGDKPSkin then RaukinGDKPSkin:Children(window) end
end

-- Opens the window (after combat) when a newer version came up that we did not mention yet
local function Notify()
  local fresh = false
  for _, key in ipairs(order) do
    local c = components[key]
    if c.newest and c.notified ~= c.newest and Compare(c.newest, c.version) > 0 then
      c.notified = c.newest
      fresh = true
      Print(string.format("%s %s is available (you have %s): %s", c.title, c.newest, c.version, c.url))
    end
  end
  if not fresh then return end
  if InCombatLockdown() then
    pendingWindow = true
  else
    ShowWindow()
  end
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

-- key: short id sent to the others ("client", "host"); title: name shown in the window
function VersionCheck:Register(key, title, version, url)
  if not key or not version or components[key] then return end
  components[key] = { key = key, title = title, version = version, url = url }
  order[#order + 1] = key
end

-- Somebody runs `version` of `key`
function VersionCheck:Seen(key, version)
  local c = components[key]
  if not c or not IsValidVersion(version) then return end
  if Compare(version, c.version) <= 0 then return end
  if c.newest and Compare(version, c.newest) <= 0 then return end
  c.newest = version
  SaveNewest(key, version)
  Notify()
end

function VersionCheck:PrintStatus()
  for _, key in ipairs(order) do
    local c = components[key]
    if c.newest and Compare(c.newest, c.version) > 0 then
      Print(string.format("%s %s - |cFFFF5555%s is out|r: %s", c.title, c.version, c.newest, c.url))
    else
      Print(string.format("%s %s - up to date as far as your guild and group know.", c.title, c.version))
    end
  end
  ShowWindow()
end

-- ---------------------------------------------------------------------------
-- Addon channel: "V1;client=3.4;host=3.4"
-- ---------------------------------------------------------------------------

local function BuildMessage()
  local parts = { "V" .. PROTOCOL }
  for _, key in ipairs(order) do
    parts[#parts + 1] = key .. "=" .. components[key].version
  end
  return table.concat(parts, ";")
end

local function Send(channel, target)
  local text = BuildMessage()
  if ChatThrottleLib then
    ChatThrottleLib:SendAddonMessage("BULK", PREFIX, text, channel, target)
  else
    SendAddonMessage(PREFIX, text, channel, target)
  end
end

local function Announce(channel)
  local now = GetTime()
  if lastSent[channel] and now - lastSent[channel] < SEND_COOLDOWN then return end
  lastSent[channel] = now
  Send(channel)
end

local function GroupChannel()
  if GetNumRaidMembers() > 0 then return "RAID" end
  if GetNumPartyMembers() > 0 then return "PARTY" end
end

local function OnMessage(message, channel, sender)
  if not sender or sender == UnitName("player") then return end
  local rest = message:match("^V%d+;(.*)$")
  if not rest then return end

  local senderIsBehind = false
  for key, version in rest:gmatch("(%w+)=([^;]+)") do
    local c = components[key]
    if c and IsValidVersion(version) then
      local cmp = Compare(version, c.version)
      if cmp > 0 then
        VersionCheck:Seen(key, version)
      elseif cmp < 0 then
        senderIsBehind = true
      end
    end
  end

  -- Tell an outdated sender what we run, so the window opens on their side.
  -- Never answer a whisper (no ping-pong), and the same player only every few minutes.
  if senderIsBehind and channel ~= "WHISPER" then
    local now = GetTime()
    if not lastReply[sender] or now - lastReply[sender] > REPLY_COOLDOWN then
      lastReply[sender] = now
      -- a small random delay spreads the answers of a whole raid
      C_Timer.After(1 + math.random() * 4, function() Send("WHISPER", sender) end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local ready = false        -- roster events before the first announcement are ignored
local wasInGroup = false
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("RAID_ROSTER_UPDATE")
events:RegisterEvent("PARTY_MEMBERS_CHANGED")
events:RegisterEvent("CHAT_MSG_ADDON")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4)
  if event == "CHAT_MSG_ADDON" then
    if arg1 == PREFIX then OnMessage(arg2, arg3, arg4) end

  elseif event == "PLAYER_ENTERING_WORLD" then
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    -- addon messages are unreliable right after login: wait a bit (like RaukinGDKP.lua does)
    C_Timer.After(10, function()
      -- a newer version seen in an earlier session
      local saved = GetSaved()
      for key, version in pairs(saved) do
        local c = components[key]
        if c and IsValidVersion(version) and Compare(version, c.version) > 0 then
          if not c.newest or Compare(version, c.newest) > 0 then c.newest = version end
        else
          saved[key] = nil   -- updated meanwhile (or no longer installed)
        end
      end
      RaukinGDKP:SetPref("newerVersions", saved)
      Notify()

      if IsInGuild() then Announce("GUILD") end
      local channel = GroupChannel()
      wasInGroup = channel ~= nil
      if channel then Announce(channel) end
      ready = true
    end)

  elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
    if not ready then return end
    -- joining a group: tell it our version once (the people already there answer if we are behind)
    local channel = GroupChannel()
    local inGroup = channel ~= nil
    if inGroup and not wasInGroup then
      C_Timer.After(3, function()
        local now = GroupChannel()
        if now then Announce(now) end
      end)
    end
    wasInGroup = inGroup

  elseif event == "PLAYER_REGEN_ENABLED" then
    if pendingWindow then
      pendingWindow = false
      ShowWindow()
    end
  end
end)

VersionCheck:Register("client", "Raukin GDKP", RaukinGDKP.version, "https://github.com/mayze13/RaukinGDKPClient")
