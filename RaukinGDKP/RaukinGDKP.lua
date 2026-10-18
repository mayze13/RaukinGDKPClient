-- RaukinGDKP: Using namespaced libraries to avoid conflicts with other addons
local CallbackHandler = RaukinLibStub("RaukinCallbackHandler-1.0")
local LibSerialize = RaukinLibStub("RaukinLibSerialize")
local LibDeflate = RaukinLibStub("RaukinLibDeflate")

-- Lua APIs
local math, pairs, print, select, table, type, unpack = math, pairs, print, select, table, type, unpack

-- WoW APIs
local CreateFrame = CreateFrame
local GetServerTime = RaukinGDKPCompat.GetServerTime
local C_Timer, FlashClientIcon, IsInGroup = RaukinGDKPCompat.C_Timer, RaukinGDKPCompat.FlashClientIcon, RaukinGDKPCompat.IsInGroup
local InCombatLockdown, UnitName, UnitClass = InCombatLockdown, UnitName, UnitClass
local GetNumGuildMembers, GetGuildRosterInfo = GetNumGuildMembers, GetGuildRosterInfo
local IsInGuild, C_GuildInfo = IsInGuild, C_GuildInfo
local RaidNotice_AddMessage, RaidWarningFrame = RaidNotice_AddMessage, RaidWarningFrame

-- 3.4.2 support
local GetAddOnMetadata = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata

-- Addon setup

local AddonName = "RaukinGDKP"
local Version = GetAddOnMetadata(AddonName, "Version")
local CommPrefix = AddonName..Version:sub(Version:find("[^.]*"))

local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):NewAddon(AddonName, "RaukinAceComm-3.0", "RaukinAceEvent-3.0")
RaukinGDKP.version = Version

RaukinGDKP.player = UnitName("player")

-- Message deduplication: track seen sequences per sender to ignore duplicate broadcasts
RaukinGDKP.seenMessages = {}  -- [sender][seq] = timestamp
RaukinGDKP.seenMessagesExpiry = 10  -- Seconds to keep seen messages (longer than retry window)

-- 3.3.5a doesn't return class ID from UnitClass, need lookup table
local CLASS_IDS = {
  ["WARRIOR"] = 1,
  ["PALADIN"] = 2,
  ["HUNTER"] = 3,
  ["ROGUE"] = 4,
  ["PRIEST"] = 5,
  ["DEATHKNIGHT"] = 6,
  ["SHAMAN"] = 7,
  ["MAGE"] = 8,
  ["WARLOCK"] = 9,
  ["DRUID"] = 11,
}
local _, englishClass = UnitClass("player")
RaukinGDKP.playerClass = CLASS_IDS[englishClass]

-- Constants

RaukinGDKP.MESSAGE = {
  ADD_ITEM = "Add",
  ASSIGN_ITEM = "Assign",
  BID_ITEM = "Bid",
  BID_ITEM_ACCEPTED = "BidAck",
  COUNTDOWN_ITEM = "Count",
  DELETE_ITEM = "Delete",
  DELETE_ALL_ITEMS = "DeleteAll",
  GOLD_DUE = "Due",
  HOST_MODE = "HostMode",  -- still sent by hosts; ignored by the client (GDKP only)
  ON_CHANGE = "OnChange",
  OS_ITEM = "OS",
  OPEN_BIDS = "OpenBids",
  START_BIDDING = "StartBid",  -- Lightweight: just item indices + expTime
  PAUSE_SESSION = "Pause",
  SYNC_REQUEST = "SyncReq",
  SYNC_RESPONSE = "Sync",
  TOGGLE_WATCH = "Watch",
  TOP_SPENDER = "TopSpend",
  VERSION_CHECK = "VersionReq",
  VERSION_CHECK_RESPONSE = "Version",
  VOTE_ITEM = "Vote",       -- old PVE votes: kept for host comms compatibility, never sent
  VOTE_UPDATE = "VoteUpd",  -- still sent by hosts; ignored by the client
}

RaukinGDKP.SEPARATOR = {
  ARG = "|",
  ELEMENT = "~",
  LIST_ELEMENT = "^",
  MESSAGE = "#",
  SUBLIST_ELEMENT = "$",
}

RaukinGDKP.STATUS = {
  PENDING = 1,
  BIDDING = 2,
  ASSIGNED = 3,
}

-- Saved prefs version: bump this to invalidate stale client SavedVariables on next login
local SAVED_PREFS_VERSION = 1

-- Lifecycle

function RaukinGDKP:OnInitialize()
  -- Version guard: wipe stale prefs from older formats
  if RaukinGDKPPrefs and (RaukinGDKPPrefs._version or 0) < SAVED_PREFS_VERSION then
    RaukinGDKPPrefs = nil
  end

  -- During initialization commands are queued
  self.initializing = true
  self.commandQueue = {}
  -- self.debugPrint = true -- Uncomment for debug output

  -- Slash commands: /wgdkp plus /rgdkp and common short forms / typos
  local slashCommands = {
    "/wgdkp", "/rgdkp", "/wgdk", "/rgdk",
    "/wdkp", "/rdkp", "/wdpk", "/rdpk",
    "/wkdp", "/rkdp", "/wgkdp", "/rgkdp",
  }
  for i, command in ipairs(slashCommands) do
    _G["SLASH_RaukinGDKP" .. i] = command
  end
  SlashCmdList["RaukinGDKP"] = function(...) self:ProcessCommand("hl", ...) end

  self:RegisterComm(CommPrefix)
  self:AddMessageSystem(self)

  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  -- 3.3.5a has no GROUP_JOINED / GROUP_LEFT events (added in MoP), so they never fired.
  -- Detect joining/leaving from the roster events instead.
  self:RegisterEvent("RAID_ROSTER_UPDATE", "OnGroupRosterChanged")
  self:RegisterEvent("PARTY_MEMBERS_CHANGED", "OnGroupRosterChanged")
  self:RegisterEvent("GROUP_ROSTER_UPDATE", "OnGroupRosterChanged")  -- newer clients

  RaukinGDKP.client = RaukinGDKP.Client:Create()
end

function RaukinGDKP:OnEnable()
  -- Messages now sent immediately via ChatThrottleLib (handles rate limiting)
end

function RaukinGDKP:PLAYER_ENTERING_WORLD()
  -- 3.3.5a: event doesn't pass login/reload args, so always process on first fire
  self:UnregisterEvent("PLAYER_ENTERING_WORLD")

  -- There is some period of time after logging in or reloading where addon messages aren't sent
  -- This delay is an attempt to wait a "safe" amount of time before attempting init messages
  C_Timer.After(8, function()
    self.initializing = false
    self.wasInGroup = IsInGroup() and true or false
    if self.wasInGroup then
      self:GROUP_JOINED()
    end
    self:ProcessQueuedCommands()
  end)
end

function RaukinGDKP:OnGroupRosterChanged()
  if self.initializing then return end

  local inGroup = IsInGroup() and true or false
  if inGroup == self.wasInGroup then return end
  self.wasInGroup = inGroup

  if inGroup then
    self:GROUP_JOINED()
  else
    -- Roster data can briefly read "not in a group" (loading screens, raid<->party conversion,
    -- server hiccups). Only reset once we are still out of the group a few seconds later.
    C_Timer.After(3, function()
      if not IsInGroup() then
        self:GROUP_LEFT()
      else
        self.wasInGroup = true
      end
    end)
  end
end

function RaukinGDKP:GROUP_JOINED()
  if self.initializing then return end

  -- NOTE: this used to broadcast DELETE_ALL_ITEMS whenever the host module had no items yet.
  -- After a /reload, a crash or a Lua error the raid lead's host data is often not restored
  -- (SavedVariables aren't written on a crash) or not restored yet after 8 seconds, so the raid
  -- lead's own login wiped the running session for the WHOLE raid. Ending a session is the
  -- host's decision only; logging in / reloading never deletes anything anymore.

  -- Send sync request multiple times for reliability (messages can get lost)
  self:Broadcast(RaukinGDKP.MESSAGE.SYNC_REQUEST, { "1" })
  C_Timer.After(0.5, function()
    self:Broadcast(RaukinGDKP.MESSAGE.SYNC_REQUEST, { "1" })
  end)
  C_Timer.After(1.0, function()
    self:Broadcast(RaukinGDKP.MESSAGE.SYNC_REQUEST, { "1" })
  end)
end

function RaukinGDKP:GROUP_LEFT()
  self.client:Reset()
end

-- Commands

function RaukinGDKP:ProcessCommand(cmd, ...)
  local arg = select(1, ...)

  if self.initializing then
    self:Info("Initializing... one moment please!")
    self.commandQueue[cmd] = self
  elseif cmd == "hl" then
    if arg == "test" then
      -- Add a test item for debugging (Betrayer of Humanity - 2H Sword from Naxx)
      -- Format: index:itemId,status,minPrice,exp,winner,salePrice
      -- Status 2 = BIDDING
      self:Info("Adding test item...")
      self.client:OnOpenBids(self.player, "1:40384,2,500", 100, 180, 10, "Test Session", 1)
    elseif arg == "center" then
      self:CenterWindow()
    elseif arg and arg:lower():match("^%s*autoopen%s*$") then
      local disabled = not self:GetPref("autoOpenDisabled", false)
      self:SetPref("autoOpenDisabled", disabled)
      self:Info(disabled and "The bidding window no longer opens by itself." or "The bidding window opens by itself when bidding starts.")
    elseif arg and arg:lower():match("^%s*help%s*$") then
      self:PrintHelp()
    elseif arg and arg:lower():match("^%s*version%s*$") then
      if RaukinGDKPVersionCheck then RaukinGDKPVersionCheck:PrintStatus() end
    elseif arg and arg:lower():match("^%s*rows") then
      local value = tonumber(arg:match("(%d+)"))
      if value then
        value = self.GUI:SetMaxRows(value)
        local window = self.client and self.client.window
        if window and window.FitToRows then window:FitToRows() end
        self:Info(string.format("Window shows up to %d items before scrolling.", value))
      else
        self:Info(string.format("Usage: /rgdkp rows 1-%d (now %d)", self.GUI.MAX_ROWS_LIMIT, self.GUI:GetMaxRows()))
      end
    elseif arg and arg:lower():match("^%s*skin%s*$") then
      RaukinGDKPSkin:ToggleSkin()
    elseif arg and arg:lower():match("^%s*opacity") then
      local value = tonumber(arg:match("(%d+)"))
      if value then
        RaukinGDKPSkin:SetOpacity(value / 100)
        self:Info(string.format("Window opacity: %d%%", math.floor(RaukinGDKPSkin:GetOpacity() * 100 + 0.5)))
      else
        self:Info("Usage: /rgdkp opacity 10-100")
      end
    else
      self.client:Toggle()
    end
  end
end

function RaukinGDKP:ProcessQueuedCommands()
  for cmd, target in pairs(self.commandQueue) do
    target:ProcessCommand(cmd)
  end
  self.commandQueue = {}
end

-- Communication

function RaukinGDKP:Broadcast(msg, data)
  if not msg then
    self:Debug("Attempted to broadcast invalid message", msg)
    return
  end
  self:SendComm(msg, data, "RAID")
end

-- This is an addon message whisper not a chat whisper
function RaukinGDKP:Whisper(msg, data, target)
  if not msg then
    self:Debug("Attempted to whisper invalid message", msg)
    return
  end
  if not target then
    self:Debug("Attempted to whisper invalid target", target)
    return
  end
  self:SendComm(msg, data, "WHISPER", target)
end

function RaukinGDKP:SendComm(msg, data, channel, target)
  data = type(data) == 'table' and table.concat(data, RaukinGDKP.SEPARATOR.ARG) or data
  local payload = data and msg..RaukinGDKP.SEPARATOR.ARG..data or msg

  self:Debug("SendComm", payload, channel, target)

  local serializedPayload = LibSerialize:Serialize(payload)
  local compressedPayload = LibDeflate:CompressDeflate(serializedPayload)
  local encodedPayload = LibDeflate:EncodeForWoWAddonChannel(compressedPayload)

  self:SendCommMessage(CommPrefix, encodedPayload, channel, target)
end

function RaukinGDKP:OnCommReceived(prefix, encodedPayload, channel, sender)
  if sender == RaukinGDKP.player and channel ~= "WHISPER" then return end

  local decodedPayload = LibDeflate:DecodeForWoWAddonChannel(encodedPayload)
  if not decodedPayload then self:Debug("Failed to decode", encodedPayload); return end
  local decompressedPayload = LibDeflate:DecompressDeflate(decodedPayload)
  if not decompressedPayload then self:Debug("Failed to decompress", encodedPayload); return end
  local success, payload = LibSerialize:Deserialize(decompressedPayload)
  if not success then self:Debug("Failed to deserialize", encodedPayload); return end

  local messages = self:Split(payload, RaukinGDKP.SEPARATOR.MESSAGE)

  for i = 1, #messages do
    local data = self:Split(messages[i], RaukinGDKP.SEPARATOR.ARG)
    local msg = table.remove(data, 1)
    if not msg then return end

    -- Apply deduplication to RAID and PARTY channel messages (reliable broadcasts)
    -- WHISPER messages don't have sequence numbers and don't need deduplication
    if channel == "RAID" or channel == "PARTY" then
      -- Check for sequence number (first data element is numeric = reliable broadcast)
      local seq = tonumber(data[1])
      if seq then
        -- This is a reliable broadcast with deduplication
        -- Check if we've already seen this message
        if self:IsMessageSeen(sender, seq) then
          self:Debug("Ignoring duplicate message", msg, "seq", seq, "from", sender)
        else
          -- Mark as seen and process
          self:MarkMessageSeen(sender, seq)
          -- Remove sequence number from data before passing to handlers
          table.remove(data, 1)
          self:FireMessage(msg, sender, unpack(data))
        end
      else
        -- Message without sequence (VERSION_CHECK or old format)
        self:FireMessage(msg, sender, unpack(data))
      end
    else
      -- WHISPER or other channel - no deduplication needed
      self:FireMessage(msg, sender, unpack(data))
    end
  end
end

-- Message deduplication helpers
function RaukinGDKP:IsMessageSeen(sender, seq)
  if not self.seenMessages[sender] then return false end
  local timestamp = self.seenMessages[sender][seq]
  if not timestamp then return false end
  -- Check if expired (handles host relog where seq resets)
  if GetTime() - timestamp > self.seenMessagesExpiry then
    self.seenMessages[sender][seq] = nil  -- Clean up expired entry
    return false
  end
  return true
end

function RaukinGDKP:MarkMessageSeen(sender, seq)
  if not self.seenMessages[sender] then
    self.seenMessages[sender] = {}
  end
  self.seenMessages[sender][seq] = GetTime()

  -- Cleanup old entries periodically (every 100 messages)
  if not self.seenMessagesCount then self.seenMessagesCount = 0 end
  self.seenMessagesCount = self.seenMessagesCount + 1
  if self.seenMessagesCount >= 100 then
    self:CleanupSeenMessages()
    self.seenMessagesCount = 0
  end
end

function RaukinGDKP:CleanupSeenMessages()
  local now = GetTime()
  local expiry = self.seenMessagesExpiry
  for sender, seqs in pairs(self.seenMessages) do
    for seq, timestamp in pairs(seqs) do
      if now - timestamp > expiry then
        seqs[seq] = nil
      end
    end
    -- Remove empty sender tables
    if not next(seqs) then
      self.seenMessages[sender] = nil
    end
  end
end


function RaukinGDKP:NotifyLocal(msg, r, g, b)
  if msg and not InCombatLockdown() then
    local color = { r = r or 1, g = g or 0.96, b = b or 0.41 }
    RaidNotice_AddMessage(RaidWarningFrame, msg, color, 5);
  end
  FlashClientIcon()
end

-- Window

function RaukinGDKP:CenterWindow()
  local window = self.client and self.client.window
  if not window then
    self:Info("Window not open. Use /wgdkp to open it first.")
    return
  end

  if window.Center then
    -- single anchor + saved position cleared (GUI.lua)
    window:Center()
  else
    local frame = window.frame
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end

  -- Old (pre 3.2.2) position keys
  local name = "RaukinGDKPClient"
  self:SetPref(name .. "X", nil)
  self:SetPref(name .. "Y", nil)

  self:Info("Window centered.")
end

function RaukinGDKP:PrintHelp()
  self:Info("Commands (/rgdkp or /wgdkp):")
  print("  /rgdkp - show or hide the bidding window")
  print("  /rgdkp center - move the window back to the middle of the screen")
  print(string.format("  /rgdkp rows N - items shown before the list scrolls (1-%d, now %d; or drag the bottom edge)", self.GUI.MAX_ROWS_LIMIT, self.GUI:GetMaxRows()))
  print("  /rgdkp opacity 10-100 - window background opacity")
  print("  /rgdkp skin - ElvUI/AddOnSkins look on/off (needs /reload)")
  print("  /rgdkp version - your version, and the download link if a newer one is out")
  print("  /rgdkp help - this list")
end

-- Persistence

function RaukinGDKP:SetPref(key, value)
  if not self.prefs then self.prefs = RaukinGDKPPrefs or {} end
  self.prefs[key] = value
  self.prefs._version = SAVED_PREFS_VERSION
  RaukinGDKPPrefs = self.prefs
end

function RaukinGDKP:GetPref(key, default)
  if not self.prefs then self.prefs = RaukinGDKPPrefs or {} end

  if self.prefs[key] == nil then
    return default
  end

  local value = self.prefs[key]

  if type(default) == 'number' then
    return tonumber(value)
  else
    return value
  end
end


-- Utility

function RaukinGDKP:Debug(...)
  if self.debugPrint then
    self:Info(...)
  end
  self:Log("[Debug]", ...)
end

function RaukinGDKP:Info(...)
  print("|cFFFF6900[RaukinGDKP]|cFFFFFFFF", ...)
  self:Log("[Info]", ...)
end

function RaukinGDKP:Error(...)
  print("|cFFFF6900[RaukinGDKP]|cFFFF0000 Error:|cFFFFFFFF", ...)
  self:Log("[Error]", ...)
end

function RaukinGDKP:Log(...)
  if self.enableDebugLog and self.debugLog then
    self.debugLog:Write(...)
  end
end

function RaukinGDKP:Split(str, sep)
  local t = {}
  local pattern = "([^"..sep.."]*)"..sep.."?"
  for s in str:gmatch(pattern) do
    table.insert(t, s)
  end
  -- Remove trailing empty element from pattern matching
  if t[#t] == "" then
    table.remove(t)
  end
  return t
end

function RaukinGDKP:GetGuildRank(playerName)
  local count = GetNumGuildMembers()

  for i = 1, count do
    local name, _, rankIdx = GetGuildRosterInfo(i)
    name = self:Split(name, "-")[1]

    if name == playerName then
      return rankIdx
    end
  end

  return nil
end

function RaukinGDKP:AddMessageSystem(target)
  if target.messageSystem then return end

  local messageSystem = {}
  messageSystem.callbacks = CallbackHandler:New(messageSystem)
  target.messageSystem = messageSystem

  target.RegisterCallback = messageSystem.RegisterCallback
  target.UnregisterCallback = messageSystem.UnregisterCallback
  target.UnregisterAllCallbacks = messageSystem.UnregisterAllCallbacks
  target.FireMessage = function(self, msg, ...) messageSystem.callbacks:Fire(msg, self, ...) end
end
