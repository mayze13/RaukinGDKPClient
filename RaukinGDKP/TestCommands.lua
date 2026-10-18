-- RaukinGDKP: Test Commands (DELETE THIS FILE WHEN DONE DEBUGGING)
-- Usage: /gdkplisten - Toggle listening mode to log incoming OPEN_BIDS

local RaukinGDKP = RaukinLibStub("RaukinAceAddon-3.0"):GetAddon("RaukinGDKP")
local C_Timer = RaukinGDKPCompat.C_Timer

local isListening = false
local receivedBatches = {}

SLASH_GDKPLISTEN1 = "/gdkplisten"
SlashCmdList["GDKPLISTEN"] = function(msg)
    local cmd = msg:lower():trim()

    if cmd == "on" or (cmd == "" and not isListening) then
        isListening = true
        receivedBatches = {}
        print("|cFF00FF00[GDKP Listen]|r Listening mode ON - waiting for OPEN_BIDS messages...")
        print("|cFF00FF00[GDKP Listen]|r Run '/gdkptest send' on the host account")

    elseif cmd == "off" or (cmd == "" and isListening) then
        isListening = false
        print("|cFF00FF00[GDKP Listen]|r Listening mode OFF")

    elseif cmd == "report" then
        print("|cFF00FF00[GDKP Listen]|r === RECEIVED BATCHES REPORT ===")
        if #receivedBatches == 0 then
            print("|cFF00FF00[GDKP Listen]|r No batches received yet.")
        else
            for i, batch in ipairs(receivedBatches) do
                print("|cFF00FF00[GDKP Listen]|r Batch " .. i .. ":")
                print("  Items: " .. batch.itemCount)
                print("  expTime: " .. tostring(batch.expTime))
                print("  OS items: " .. batch.osCount .. " / " .. batch.itemCount)
                if batch.osCount == 0 then
                    print("  (MS batch - no OS items)")
                elseif batch.osCount < batch.itemCount then
                    print("  |cFFFF0000WARNING: Not all items have isOS=true!|r")
                else
                    print("  (OS batch - all items OS)")
                end
            end
        end
        print("|cFF00FF00[GDKP Listen]|r === END REPORT ===")

    elseif cmd == "items" then
        -- Show current state of items in the session
        print("|cFF00FF00[GDKP Listen]|r === CURRENT SESSION ITEMS ===")
        if not RaukinGDKP.client or not RaukinGDKP.client.activeSession then
            print("|cFF00FF00[GDKP Listen]|r No active session")
        else
            local session = RaukinGDKP.client.activeSession
            local osCount = 0
            local totalCount = 0
            for index, item in pairs(session.items) do
                totalCount = totalCount + 1
                local isOS = item:IsOS()
                local status = item:GetStatus()
                if isOS then osCount = osCount + 1 end
                print("|cFF00FF00[GDKP Listen]|r  Item " .. index .. ": status=" .. status .. " isOS=" .. tostring(isOS))
            end
            print("|cFF00FF00[GDKP Listen]|r Total: " .. totalCount .. " items, " .. osCount .. " with isOS=true")
        end
        print("|cFF00FF00[GDKP Listen]|r === END ITEMS ===")

    elseif cmd == "clear" then
        receivedBatches = {}
        print("|cFF00FF00[GDKP Listen]|r Cleared received batches.")

    else
        print("|cFF00FF00[GDKP Listen]|r Commands:")
        print("  /gdkplisten       - Toggle listening on/off")
        print("  /gdkplisten on    - Turn on listening")
        print("  /gdkplisten off   - Turn off listening")
        print("  /gdkplisten report - Show received batches summary")
        print("  /gdkplisten clear  - Clear received batches")
    end
end

-- Hook into the message callback to log OPEN_BIDS when listening
local originalOnOpenBids = nil

local function HookOpenBids()
    if not RaukinGDKP.client then
        C_Timer.After(1, HookOpenBids)
        return
    end

    -- Store original function
    originalOnOpenBids = RaukinGDKP.client.OnOpenBids

    -- Replace with logging version
    RaukinGDKP.client.OnOpenBids = function(self, sender, encodedItems, minIncrement, bidDuration, countdown, sessionName, allowOS, splitPercent, raidSize, mode, expTime)
        if isListening then
            print("|cFF00FF00[GDKP Listen]|r ========== OPEN_BIDS RECEIVED ==========")
            print("|cFF00FF00[GDKP Listen]|r From: " .. tostring(sender))
            print("|cFF00FF00[GDKP Listen]|r expTime: " .. tostring(expTime))

            -- Parse items to count them and check isOS
            local itemCount = 0
            local osCount = 0

            if encodedItems and encodedItems ~= "" then
                local elements = RaukinGDKP:Split(encodedItems, RaukinGDKP.SEPARATOR.LIST_ELEMENT)
                print("|cFF00FF00[GDKP Listen]|r Raw elements: " .. #elements)

                for i = 1, #elements, 2 do
                    local index = elements[i]
                    local itemData = elements[i + 1]
                    if index and itemData then
                        itemCount = itemCount + 1
                        -- Parse item data to find isOS
                        local parts = RaukinGDKP:Split(itemData, RaukinGDKP.SEPARATOR.ELEMENT)
                        local rawIsOS = parts[8]
                        local parsedIsOS = tonumber(rawIsOS) == 1

                        print("|cFF00FF00[GDKP Listen]|r   Item " .. index .. ": " .. #parts .. " fields, isOS raw=[" .. tostring(rawIsOS) .. "] parsed=" .. tostring(parsedIsOS))

                        if parsedIsOS then
                            osCount = osCount + 1
                        end
                    end
                end
            end

            print("|cFF00FF00[GDKP Listen]|r Total: " .. itemCount .. " items, " .. osCount .. " with isOS=true")
            print("|cFF00FF00[GDKP Listen]|r ==========================================")

            -- Store for report
            table.insert(receivedBatches, {
                sender = sender,
                itemCount = itemCount,
                osCount = osCount,
                expTime = expTime,
                time = GetTime()
            })
        end

        -- Call original function
        return originalOnOpenBids(self, sender, encodedItems, minIncrement, bidDuration, countdown, sessionName, allowOS, splitPercent, raidSize, mode, expTime)
    end

    print("|cFF00FF00[GDKP Listen]|r Client listener hooked successfully.")
end

-- Start hooking after a delay to ensure client is created
C_Timer.After(2, HookOpenBids)

print("|cFF00FF00[GDKP Listen]|r Test commands loaded. Use /gdkplisten")
