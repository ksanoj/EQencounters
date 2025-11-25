-- this runs around for the soundproof achievement
---@type Mq

local mq = require('mq')

local announce = true
local useevent = true

local safeSpotYXZ = '568 -1317 327'

mq.cmd('/hidecorpse npc')
mq.cmd('/hidecorpse alwaysnpc')
mq.delay(1000)

local function debuff(buffName)
    local buffID = mq.TLO.Me.Buff(buffName).ID()
    mq.TLO.Me.Buff('song of echoes').ID()
    if buffID ~= nil and buffID > 0 then return true end
    return false
end

local function pause(state)
    if state == true then
        -- Pause automation
        mq.cmd('/mqp on')
        mq.cmd('/rdpause on')
    else
        -- Unpause automation
        mq.cmd('/mqp off')
        mq.cmd('/rdpause off')
    end
end
-- Notes
local function handleAoEEvent()
    if mq.TLO.Me.CleanName() == mq.TLO.Group.MainAssist() then return end

    -- Berserkers
    if mq.TLO.Me.ActiveDisc.Name() ~= nil and string.find(mq.TLO.Me.ActiveDisc.Name(),'Frenzied Resolve Discipline') then
        mq.cmd('/stopdisc')
        mq.delay(500)
    end

    -- we have the debuff, run to safe spot
    if announce then mq.cmd('/dgt I have the AOE debuff, running to safe spot') end
    pause(true)

    mq.delay(200)
    mq.cmdf('/nav locyxz %s', safeSpotYXZ)
    while mq.TLO.Navigation.Active() == true do mq.delay(300) end

    -- check who is with me
    local first = 0

    -- I am a healer dru,shm,cleric,pal
    local called1 = string.find('DRU SHM CLR PAL', mq.TLO.Me.Class.ShortName())
    -- They are a healer
    local calledID = mq.TLO.Spawn('radius 50 pc notid '..mq.TLO.Me.ID()).ID()
    local called2 = mq.TLO.Spawn(calledID).Class.ShortName()

    printf('called %s and %s ', mq.TLO.Me.CleanName(), mq.TLO.Spawn(calledID).CleanName())

    if called2 ~= nil and string.find('DRU SHM CLR PAL', called2) ~= nil and called1 ~= nil then
        -- both healers
        if calledID < mq.TLO.Me.ID() then
            first = calledID
        end
    else
        if called1 ~= nil then
            -- I am a healer
            print('I am a healer')
            first = mq.TLO.Me.ID()
        end
    end

    -- not healers/both healers, lowest ID goes first
    if first == 0 then
        if  mq.TLO.Me.ID() < calledID  then
            first = mq.TLO.Me.ID()
            if announce then mq.cmd('/g I return first') end
        else
            first = calledID
            if announce then mq.cmd('/g I return second') end
        end
    elseif first == mq.TLO.Me.ID() then
        if announce then mq.cmd('/g I return first because healer') end
    else
        if announce then mq.cmd('/g well fudgestickles !') end
    end

    ::death::
    local doWait = 0
    while debuff('Song of Echoes') or doWait do
        mq.delay(300)
        doWait = doWait - 1
    end

    if first == mq.TLO.Me.ID() then
        if announce then mq.cmd('/g AOE debuff is gone, running to aura') end
        -- run to aura
        mq.cmd('/nav spawn a_sound_echo')
    else
        -- give them 20 seconds to be hit by the aura
        -- which will give me the buff again
        -- set myself to go, should wait for debuff to fade

        -- death or glory !
        doWait = 60
        first = mq.TLO.Me.ID()
        if announce then mq.cmd('/g Glory or death!') end
        goto death
    end

    -- while nav is active wait
    while mq.TLO.Navigation.Active() == true do mq.delay(300) end

    mq.cmd('/nav spawn ' .. mq.TLO.Group.MainAssist())
    while mq.TLO.Navigation.Active() == true do mq.delay(300) end

    if announce then mq.cmd('/g helping out again') end
    pause(false)
end

-- Whip Eggs
local function HandleEggs()
    -- Finish this up
    if string.find('SHM CLR DRU', mq.TLO.Me.Class.ShortName()) == nil then
        pause(true)
    end

    -- mq.cmd('/nav spawn egg | distance=50')
    mq.cmd('/target npc egg')

    while mq.TLO.SpawnCount('egg')() > 0 do
        mq.doevents()

        if mq.TLO.Pet.ID() ~= nil and mq.TLO.Pet.Target.ID() ~= mq.TLO.Spawn('egg').ID() then
            mq.cmd('/target npc egg')
            mq.delay(1000)
            mq.cmd('/pet attack')
            mq.cmd('/pet swarm')
        end

        if string.find('BRD', mq.TLO.Me.Class.ShortName()) == nil then
            mq.cmd('/pet swarm')
        end
    end

    if announce then mq.cmd('/g Egg is dead, resuming') end
    pause(false)
end

local function event_musicalmagic(line, nameOne, nameTwo)
    -- local time_remaining = 0
    mq.cmdf('/bc run %s, %s', nameOne, nameTwo)
    if nameOne ~= mq.TLO.Me.CleanName() and nameTwo ~= mq.TLO.Me.CleanName() then
        return 0
    end

    -- pause assists (oops if healer, hang)
    pause(true)

    local position = {}
--[[     position[1] = '/nav locxyz -1095 399 197'
    position[2] = '/nav locxyz -1041 374 197'
    position[3] = '/nav locxyz -1000 330 197'
    position[4] = '/nav locxyz  -989 270 197'
    position[5] = '/nav locxyz -1048 209 197'
    position[6] = '/nav locxyz -1097 230 197' ]]

    position[1] = '/nav locyxz 308 -1167 197'
    position[2] = '/nav locyxz 401 -1077 197'
    position[3] = '/nav locyxz 289 -976 197'
    position[4] = '/nav locyxz 198 -1060 197'

    -- move to position 1
    mq.cmd(position[1])
    while mq.TLO.Navigation.Active() == true do mq.delay(300) end

    -- wait for auras to spawn
    while mq.TLO.SpawnCount('sound')() == 0 do
        mq.delay('1s')
    end

    local returnIn = 0
    local mayReturn = false
    ::suredeath::
    while not mayReturn do

        -- now run in a square
        for _, point in ipairs(position) do
            returnIn = returnIn - 1

            mq.cmd(point)
            while mq.TLO.Navigation.Active() == true do mq.delay(300) end
            mq.delay('3s')

            if not debuff('Song of Echoes') then
                if returnIn < 0 and nameOne == mq.TLO.Me.CleanName() then
                    mayReturn = true
                else
                    nameOne = mq.TLO.Me.CleanName()

                    -- so that it doesn't return immediatly
                    -- other guy gets hit by aura it reapplies to me
                    -- 5 * 3 = 15 seconds at least
                    returnIn = 5
                end
            end
        end
    end

    if announce then mq.cmd('/dgt running to aura') end
    mq.cmd('/nav spawn a_sound_echo')
    while mq.TLO.Navigation.Active() == true do mq.delay(300) end

    if announce then mq.cmd('/dgt returning to group') end
    mq.cmd('/nav spawn Shalowain | distance=20')
    while mq.TLO.Navigation.Active() == true do mq.delay(300) end

    -- activate combat assists
    if announce then mq.cmd('/dgt helping out') end
    pause(false)

end

local args = {...}
for i=1, #args, 1 do
    if args[i] == 'quiet' then
        announce = false
    elseif args[i] == 'event' then
        useevent = true
    elseif args[i] == 'safespot' then
        useevent = false
    elseif args[i] == 'help' then
        print('LS.lua [quiet] [event (default)|safespot]')
    end
end

print('Starting...')
-- mq.cmd('/lua run zfix')
if useevent then
    print('using the event')
    mq.event('MusicalAura',
        '#*#Shalowain links #*# object that begins to move toward #1# and #2#.#*#',
        event_musicalmagic)
end

local command = 0
local lichHandle = true

local event_zoned = function(line)
    -- zoned so quit
    command = 1
end

-- died/kicked task/whatever
mq.event('Zoned','LOADING, PLEASE WAIT...#*#',event_zoned)

-- Main Loop

while true do
    mq.doevents()

    if command == 1 then
        break
    elseif not useevent and debuff('Song of Echoes') then
        handleAoEEvent()
    elseif mq.TLO.Spawn('Shalowain').Dead() then
        print('Success: Dead Shalowain')
        break
    elseif lichHandle and mq.TLO.Spawn('#Lich').ID() > 0 then
        if mq.TLO.Spawn('#Lich').Dead() then
            print('Success: Dead Lich')
            mq.cmd('/pet taunt off')
            if mq.TLO.Me.CleanName() == mq.TLO.Group.MainAssist() then
                -- Tank runs to Shalo
                mq.cmd('/nav spawn Shalowain | distance=20')
                mq.cmd('/target Shalowain')
                mq.cmd('/attack on')
                while mq.TLO.Navigation.Active() == true do mq.delay(100) end
                break
            end
            lichHandle = false
    elseif not mq.TLO.Spawn('#Lich').Dead() then
            mq.cmdf('/target id %s', mq.TLO.Spawn('#Lich').ID()) 
            if string.find('SHM CLR DRU MAG WIZ NEC ENC', mq.TLO.Me.Class.ShortName()) == nil then
                if mq.TLO.Spawn('#Lich').Distance() > 20 then
                    mq.cmd('/nav spawn #Lich | distance=15')                    
                    mq.cmdf('/target id %s', mq.TLO.Spawn('#Lich').ID())
                    while mq.TLO.Navigation.Active() == true do mq.delay(300) end
                else
                    mq.cmd('/face fast')
                    mq.cmd('/attack on')
                end
            else
                if not mq.TLO.Target.LineOfSight() then
                    mq.cmd('/nav spawn #Lich | distance=15')
                    while mq.TLO.Navigation.Active() == true do
                        mq.delay(300)
                        if mq.TLO.Target.LineOfSight() then
                            mq.cmd('/nav stop')
                            break
                        end
                    end
                end
            end
        end
    end

    mq.delay(1)
end

while mq.TLO.SpawnCount('_chest')() < 1 do
    mq.doevents()
    mq.delay(1000)
end

pause(false)

mq.unevent('MusicalAura')
mq.unevent('Zoned')
-- mq.cmd('/lua stop zfix')
print('...Ended')
