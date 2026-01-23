local mq = require('mq')

-- ToV - Velks (Bled)
-- Listens for the Bled emote.

local function sanitizeName(s)
    return (s or '')
        :gsub('^%s+', '')
        :gsub('%s+$', '')
        :gsub('[%p%s]+$', '')
end

local NAV1 = '146.46 -72.69 5.46'

-- Navigation state machine:
-- 0 = idle/listening
-- 1 = need to run nav1 (issue if not already)
local navStage = 0
local navIssued = false
local navIssueTimeMs = 0
local NAV_TIMEOUT_MS = 180000

local function on_bled_turn(line)
    local me = sanitizeName(mq.TLO.Me.DisplayName() or '')
    if me == '' or line == nil then return end

    local lowerLine = tostring(line):lower()
    local lowerMe = me:lower()

    -- Some emotes use your actual name; others may say "you".
    if not (lowerLine:find(lowerMe, 1, true) or lowerLine:find('toward you', 1, true)) then
        return
    end

    -- If we're already in a nav sequence, ignore additional emotes until complete.
    if navStage ~= 0 then
        return
    end

    navStage = 1
    navIssued = false
end

-- Match the fixed part of the emote, then validate the target in the handler.
mq.event('TOV_VELKS_BLED_TURN', '#*#Bled takes in a deep, wheezing breath and turns its head toward#*#', on_bled_turn)

print('tov_velks.lua loaded')

while true do
    mq.doevents()

    -- Drive navigation without blocking event processing.
    if navStage ~= 0 then
        local now = mq.gettime and mq.gettime() or (os.clock() * 1000)

        -- If nav is active, just wait for it to finish (or timeout).
        if mq.TLO.Navigation.Active() then
            if navIssued and navIssueTimeMs > 0 and (now - navIssueTimeMs) > NAV_TIMEOUT_MS then
                mq.cmd('/nav stop')
                navStage = 0
                navIssued = false
                navIssueTimeMs = 0
            end
        else
            -- Nav is not active. Either we need to issue the current stage, or it just finished.
            if not navIssued then
                if navStage == 1 then
                    mq.cmd('/nav loc ' .. NAV1)
                end
                navIssued = true
                navIssueTimeMs = now
            else
                -- Previously issued and now nav is inactive => assume arrived/finished.
                navStage = 0
                navIssued = false
                navIssueTimeMs = 0
            end
        end
    end

    mq.delay(50)
end
