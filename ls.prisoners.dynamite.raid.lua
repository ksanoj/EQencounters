--[[
    LS Prisoners Navulta Dynamite
    Watches for a_bomb00-03 spawns within 200 range.
    After 5 second delay, spams Valia's Unyielding Bravery until not ready
    and Protection of the Primal Spirits buff is present, then exits.
--]]

local mq = require('mq')

local VALIA_ITEM = "Valia's Unyielding Bravery"
local BUFF_NAME = "Protection of the Primal Spirits"
local DETECT_RANGE = 200
local DELAY_SECONDS = 5
local VALIA_RETRY_MS = 500

local BOMB_NAMES = {
    "a_bomb00",
    "a_bomb01",
    "a_bomb02",
    "a_bomb03",
}

local phase = "scanning"
local delayEndMs = 0
local lastValiaAttemptMs = 0
local valiaStopcastDone = false
local detectedBomb = nil
local scriptDone = false

local function checkForBombs()
    for _, name in ipairs(BOMB_NAMES) do
        local spawn = mq.TLO.Spawn(string.format('npc "%s"', name))
        if spawn and spawn() and spawn.ID() and spawn.ID() > 0 then
            local dist = spawn.Distance() or 999
            if dist <= DETECT_RANGE then
                return name, dist
            end
        end
    end
    return nil, nil
end

local function hasBuff()
    local buff = mq.TLO.Me.Buff(BUFF_NAME)
    return buff and buff() and buff.ID() and buff.ID() > 0
end

local function isValiaReady()
    local ready = mq.TLO.Cast.Ready(VALIA_ITEM)
    return ready and ready() == true
end

print('[LS Prisoners Dynamite] Scanning for bomb spawns...')

while not scriptDone do
    mq.doevents()

    if phase == "scanning" then
        local name, dist = checkForBombs()
        if name then
            detectedBomb = name
            print(string.format('[LS Prisoners Dynamite] Bomb detected: %s at %.0f range. Waiting %ds...', name, dist, DELAY_SECONDS))
            delayEndMs = mq.gettime() + (DELAY_SECONDS * 1000)
            phase = "waiting"
        end

    elseif phase == "waiting" then
        if mq.gettime() >= delayEndMs then
            print('[LS Prisoners Dynamite] Delay complete. Casting Valia...')
            phase = "casting"
            valiaStopcastDone = false
            lastValiaAttemptMs = 0
        end

    elseif phase == "casting" then
        local valiaReady = isValiaReady()
        local buffPresent = hasBuff()

        if not valiaReady and buffPresent then
            print('[LS Prisoners Dynamite] Valia used and buff active. Done.')
            phase = "done"
            scriptDone = true
        elseif valiaReady then
            local nowMs = mq.gettime()
            if (nowMs - lastValiaAttemptMs) >= VALIA_RETRY_MS then
                lastValiaAttemptMs = nowMs
                if not valiaStopcastDone then
                    mq.cmd('/stopcast')
                    mq.delay(50)
                    valiaStopcastDone = true
                end
                mq.cmdf('/useitem "%s"', VALIA_ITEM)
            end
        end
    end

    mq.delay(50)
end

print('[LS Prisoners Dynamite] Script exiting.')
