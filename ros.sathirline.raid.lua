local mq = require('mq')

-- Ring of Scale - The Sathir Line
-- Listens for Drusella Sathir chase emote.
-- This script assumes your fighting in the north end of the event area, otherwise the locs must change.

local function sanitizeName(s)
    return (s or '')
        :gsub('^%s+', '')
        :gsub('%s+$', '')
        :gsub('[%p%s]+$', '')
end

local NAV1 = '0.29 -274.34 1.50'
local NAV2 = '-188.08 -423.43 1.50'

-- Navigation state machine:
-- 0 = idle/listening
-- 1 = need to run nav1 (issue if not already)
-- 2 = need to run nav2 (after nav1 complete)
local navStage = 0
local navIssued = false
local navIssueTimeMs = 0
local NAV_TIMEOUT_MS = 180000

local function on_drusella_chase(line, target)
    local me = sanitizeName(mq.TLO.Me.DisplayName() or '')
    local tgt = sanitizeName(target)
    if tgt == '' or me == '' then return end
    if tgt ~= me then return end

    -- If we're already in a nav sequence, ignore additional emotes until complete.
    if navStage ~= 0 then
        return
    end

    navStage = 1
    navIssued = false
end

-- Matches: "Drusella Sathir peers at <name> and prepares to give chase!"
-- #1# captures the name from the emote.
mq.event('ROS_DRUSELLA_CHASE', '#*#Drusella Sathir peers at #1# and prepares to give chase!#*#', on_drusella_chase)

print('ros_sathirs.lua loaded')

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
                elseif navStage == 2 then
                    mq.cmd('/nav loc ' .. NAV2)
                end
                navIssued = true
                navIssueTimeMs = now
            else
                -- Previously issued and now nav is inactive => assume arrived/finished.
                if navStage == 1 then
                    navStage = 2
                    navIssued = false
                    navIssueTimeMs = 0
                else
                    -- Stage 2 complete; return to listening.
                    navStage = 0
                    navIssued = false
                    navIssueTimeMs = 0
                end
            end
        end
    end

    mq.delay(50)
end
