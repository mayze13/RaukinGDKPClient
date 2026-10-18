-- Compatibility layer for WoW 3.3.5a (WotLK)
-- Provides PRIVATE polyfills for newer WoW APIs.
-- Nothing here is written into the global namespace except the single RaukinGDKPCompat
-- table. Other addons (e.g. RCLootCouncil) that probe for C_Timer, C_Item, Item,
-- GetServerTime, IsInGroup etc. are therefore not fooled into thinking they run on a
-- newer client, and they never end up using our simplified versions.
local Compat = {}
RaukinGDKPCompat = Compat

-- BackdropTemplate doesn't exist in 3.3.5a
-- Create a LOCAL wrapper to strip it out - do NOT replace the global CreateFrame
-- as that causes taint issues with secure actions (spell casting, etc.)
local RaukinCreateFrame
do
    local originalCreateFrame = CreateFrame
    RaukinCreateFrame = function(frameType, name, parent, template, ...)
        if template then
            -- Remove BackdropTemplate from template string
            template = template:gsub("BackdropTemplate,?", "")
            template = template:gsub(",?BackdropTemplate", "")
            if template == "" then template = nil end
        end
        return originalCreateFrame(frameType, name, parent, template, ...)
    end
end

-- Export for use by other addon files
RaukinGDKP = RaukinGDKP or {}
RaukinGDKP.CreateFrame = RaukinCreateFrame

-- C_Timer implementation using OnUpdate frames
-- Hidden when idle, throttled to 50ms. Written so a timer can never get stuck:
--   * a one-shot timer is removed BEFORE its callback runs (an error can't make it fire forever)
--   * callbacks run under pcall (one failing callback doesn't stop the others or the frame)
--   * timers created inside a callback are merged after the loop (never modify a table during pairs())
do
    local C_TimerImpl = {}

    local timerFrame = CreateFrame("Frame")
    local timers = {}      -- [id] = timer
    local pending = {}     -- timers created while a tick is running
    local ticking = false
    local timerID = 0
    local timerCount = 0
    local frameElapsed = 0
    local TICK_INTERVAL = 0.05

    timerFrame:Hide()  -- Start hidden (no timers)

    local function ReportError(err)
        local handler = geterrorhandler and geterrorhandler()
        if handler then handler(err) end
    end

    local function Remove(id)
        if timers[id] then
            timers[id] = nil
            timerCount = timerCount - 1
        end
    end

    local fired = {}
    timerFrame:SetScript("OnUpdate", function(self, elapsed)
        frameElapsed = frameElapsed + elapsed
        if frameElapsed < TICK_INTERVAL then return end
        local dt = frameElapsed
        frameElapsed = 0

        -- 1) advance all timers and collect the ones that are due
        ticking = true
        for id, timer in pairs(timers) do
            timer.elapsed = timer.elapsed + dt
            if timer.elapsed >= timer.duration then
                timer.elapsed = timer.elapsed - timer.duration
                if not timer.repeating then
                    Remove(id)
                end
                table.insert(fired, timer)
            end
        end
        ticking = false

        -- 2) merge timers that were created during the loop
        for id, timer in pairs(pending) do
            timers[id] = timer
            pending[id] = nil
        end

        -- 3) run callbacks; an error in one callback no longer stops the others
        for i = 1, #fired do
            local timer = fired[i]
            fired[i] = nil
            if not timer.cancelled then
                local ok, err = pcall(timer.callback)
                if not ok then ReportError(err) end
            end
        end

        -- Hide frame when no timers left
        if timerCount == 0 then
            timerFrame:Hide()
        end
    end)

    local function Add(duration, callback, repeating)
        timerID = timerID + 1
        timerCount = timerCount + 1
        local timer = { duration = duration or 0, elapsed = 0, callback = callback, repeating = repeating }
        if ticking then
            pending[timerID] = timer
        else
            timers[timerID] = timer
        end
        timerFrame:Show()  -- Ensure frame is running
        return timerID, timer
    end

    function C_TimerImpl.After(duration, callback)
        Add(duration, callback, false)
    end

    function C_TimerImpl.NewTicker(duration, callback, iterations)
        local id, timer
        local count = 0
        local ticker = {}
        function ticker.Cancel()
            if timer then timer.cancelled = true end
            if pending[id] then
                pending[id] = nil
                timerCount = timerCount - 1
            else
                Remove(id)
            end
        end
        id, timer = Add(duration, function()
            count = count + 1
            if iterations and count >= iterations then
                ticker.Cancel()
            end
            callback(ticker)
        end, true)
        return ticker
    end

    Compat.C_Timer = C_TimerImpl
end

-- GetServerTime: native if the client has it, otherwise time() (unix timestamp)
Compat.GetServerTime = GetServerTime or time

-- IsInGroup / IsInRaid: check raid or party members
Compat.IsInGroup = IsInGroup or function()
    return (GetNumRaidMembers() > 0) or (GetNumPartyMembers() > 0)
end
Compat.IsInRaid = IsInRaid or function()
    return GetNumRaidMembers() > 0
end

-- FlashClientIcon: no-op (cosmetic feature, not available in 3.3.5a)
Compat.FlashClientIcon = FlashClientIcon or function() end

-- SendSystemMessage: use chat frame
Compat.SendSystemMessage = SendSystemMessage or function(msg)
    DEFAULT_CHAT_FRAME:AddMessage(msg, 1, 1, 0) -- Yellow color
end

-- C_Item implementation for item data caching
Compat.C_Item = {
    IsItemDataCachedByID = function(itemID)
        local name = GetItemInfo(itemID)
        return name ~= nil
    end,
}

-- CreateObjectPool: simple object pooling for reuse
do
    local function CreateObjectPoolImpl(creationFunc, resetFunc)
        local pool = {
            objects = {},
            creationFunc = creationFunc,
            resetFunc = resetFunc
        }

        function pool:Acquire()
            local obj = table.remove(self.objects)
            if not obj then
                obj = self.creationFunc()
            end
            return obj
        end

        function pool:Release(obj)
            if self.resetFunc then
                self.resetFunc(obj)
            end
            -- Clear object properties for reuse
            for k in pairs(obj) do
                obj[k] = nil
            end
            table.insert(self.objects, obj)
        end

        return pool
    end
    Compat.CreateObjectPool = CreateObjectPoolImpl  -- always our own (a foreign one might not clear released objects)
end

-- Item class for async item loading
-- In 3.3.5a we need to implement our own retry mechanism
-- Use namespaced RaukinItem to avoid conflicts with other addons
RaukinItem = RaukinItem or {}

function RaukinItem:CreateFromItemID(itemID)
    local item = { itemID = itemID }

    function item:ContinueOnItemLoad(callback)
        -- Check if already cached
        if GetItemInfo(itemID) then
            callback()
            return
        end

        -- Create retry frame
        local retryFrame = CreateFrame("Frame")
        local retryCount = 0
        local maxRetries = 100 -- ~10 seconds at 0.1s interval

        retryFrame:SetScript("OnUpdate", function(self, elapsed)
            self.elapsed = (self.elapsed or 0) + elapsed
            if self.elapsed >= 0.1 then
                self.elapsed = 0
                retryCount = retryCount + 1

                if GetItemInfo(itemID) then
                    self:SetScript("OnUpdate", nil)
                    callback()
                elseif retryCount >= maxRetries then
                    self:SetScript("OnUpdate", nil)
                    -- Item couldn't be loaded, call anyway to handle error
                    callback()
                end
            end
        end)
    end

    return item
end

-- NOTE: no global "Item" any more. Other addons check for it to detect newer clients.
