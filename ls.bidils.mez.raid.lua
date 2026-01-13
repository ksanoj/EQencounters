---@type Mq
local mq = require('mq')

-- Pause state
local isPaused = false
local dpsPaused = false  -- Track DPS pause state to avoid spam

local required_zone = {
    ['mischiefplane_raid'] = true,  -- Add your zone here
}

-- Mobs that should be mezzed
local mezTargets = {
    ['a_white_rabbit00'] = true,
    ['a_white_rabbit01'] = true,
}

-- Mez spells configuration for each class
local mezzes = {
    ENC = {
        {name='Beam of Slumber', type='aa', order='1'},
        {name='Mesmerize XX', type='spell', order='2'},
        {name='Beguiler\'s Banishment', type='aa', order='3'},
        {name='Mesmerizing Wave XV', type='spell', order='4'}
    },
    BRD = {
        {name='Slumber of Suja', type='spell', order='1'},
    },
}

-- Classes that should not be interrupted while casting
local unbreakable = {
    ['ENC'] = false,  -- Enchanter mez is interruptible
    ['BRD'] = false,  -- Bard mez is interruptible
}

-- Spawn caching for performance
local lastSpawnCheck = 0
local spawnCheckInterval = 2000  -- Check spawns every 2 seconds
local cachedSpawns = {}  -- Cache spawn IDs and data

-- Check if target has the mez buff
local function hasMezBuff(targetID)
    if not targetID or targetID == 0 then return false end
    
    -- Target the mob to check buffs
    local currentTarget = mq.TLO.Target.ID()
    if currentTarget ~= targetID then
        mq.cmdf('/target id %d', targetID)
        mq.delay(200)
    end
    
    -- Check if target has the mez buff
    local numBuffs = mq.TLO.Target.BuffCount() or 0
    for i = 1, numBuffs do
        local buff = mq.TLO.Target.Buff(i)
        if buff() and buff.Name() then
            local buffName = buff.Name()
            -- Check if buff name contains "Mesmerize" or "Slumber"
            if buffName:find("Mesmerize") or buffName:find("Slumber") or buffName:find("Beam of Slumber") or buffName:find("Banishment") then
                return true
            end
        end
    end
    
    return false
end

local function StopDPS()
    if dpsPaused then
        return  -- Already paused, don't spam
    end
    dpsPaused = true
    mq.cmd('/squelch /rdpause on')
    mq.delay(10)
    if mq.TLO.Me.Class.ShortName() == 'BRD' then
        mq.cmd('/squelch /stopsong')
        mq.delay(10)
        mq.cmd('/squelch /stopsong')
        mq.delay(10)
    end
    mq.cmd('/squelch /rdpause on')
    mq.delay(10)
    if (mq.TLO.Me.Casting.ID()) and (not unbreakable[mq.TLO.Me.Class.ShortName()]) then
        mq.cmd('/squelch /stopcast')
        mq.delay(100)
    end
end

local function ResumeDPS()
    if not dpsPaused then
        return  -- Already resumed, don't spam
    end
    dpsPaused = false
    mq.cmd('/squelch /rdpause off')
    mq.delay(10)
    mq.cmd('/squelch /rdpause off')
    mq.delay(10)
end

-- Update cached spawns
local function updateSpawnCache()
    local currentTime = mq.gettime()
    
    -- Only update cache every 2 seconds
    if currentTime - lastSpawnCheck < spawnCheckInterval then
        return
    end
    
    lastSpawnCheck = currentTime
    
    -- Cache rabbit spawn IDs
    local rabbit1 = mq.TLO.Spawn('npc "a_white_rabbit00"')
    local rabbit2 = mq.TLO.Spawn('npc "a_white_rabbit01"')
    
    cachedSpawns = {
        rabbit1ID = rabbit1 and rabbit1.ID() or 0,
        rabbit2ID = rabbit2 and rabbit2.ID() or 0
    }
end

local function mez_ready(data)
    -- Customize this function for your specific mez targets
    -- 200 should be enough
    if not spawn or not spawn.Type then return false end
    
    -- Check if this is a mob we should mez
    local mobName = spawn.CleanName()
    if not mezTargets[mobName] then
        return false
    end
    
    -- Check basic validity first
    if spawn.Type() ~= 'NPC' or spawn.Dead() or not spawn.LineOfSight() or (spawn.Distance() or 999) > 200 then
        return false
    end
    
    -- Check if already mezzed using buff check
    local spawnID = spawn.ID()
    if hasMezBuff(spawnID) then
        return false
    end
    
    return true
end

local function mez_ready(data)
    if not unbreakable[mq.TLO.Me.Class.ShortName()] then
        if data.type == 'spell' then
            return mq.TLO.Me.SpellReady(mq.TLO.Spell(data.name).RankName())()
        elseif data.type == 'aa' then
            return mq.TLO.Me.AltAbilityReady(data.name)()
        end
    else
        if data.type == 'spell' then
            return (mq.TLO.Me.SpellReady(mq.TLO.Spell(data.name).RankName())() and not mq.TLO.Me.Casting())
        elseif data.type == 'aa' then
            return (mq.TLO.Me.AltAbilityReady(data.name)() and not mq.TLO.Me.Casting())
        end
    end
end

-- Simple mez function like encmez - kopia
local function castMezOnTarget(targetID, targetName)
    if not targetID or targetID == 0 then return false end
    
    -- Target the mob
    mq.cmdf('/target id %d', targetID)
    mq.delay(200)
    
    -- Verify target
    if mq.TLO.Target.ID() ~= targetID then
        print(string.format('[LS Mez] Failed to target %s (ID: %d)', targetName, targetID))
        return false
    end
    
    -- Check if already mezzed
    if hasMezBuff(targetID) then
        return false
    end
    
    -- Check line of sight
    if not mq.TLO.Target.LineOfSight() then
        return false
    end
    
    -- Get mez abilities
    local mez = mezzes[mq.TLO.Me.Class.ShortName()]
    if not mez then return false end
    
    table.sort(mez, function(a, b) return a['order'] < b['order'] end)
    
    -- Try to cast first available mez
    for _, data in ipairs(mez) do
        if mez_ready(data) then
            print(string.format('[LS Mez] Mezzing %s (ID: %d) with %s', targetName, targetID, data.name))
            
            if data.type == 'spell' then
                mq.cmdf('/cast "%s"', mq.TLO.Spell(data.name).RankName())
            else
                mq.cmdf('/alt activate %d', mq.TLO.Me.AltAbility(data.name).ID())
            end
            
            -- Wait for cast to complete
            mq.delay(100)
            while mq.TLO.Me.Casting() do
                mq.delay(50)
            end
            
            return true
        end
    end
    
    return false
end

-- Main mez check like encmez - kopia
local function performMezRotation()
    -- Update spawn cache
    updateSpawnCache()
    
    local rabbit1ID = cachedSpawns.rabbit1ID or 0
    local rabbit2ID = cachedSpawns.rabbit2ID or 0
    
    -- Check if rabbits exist and are alive
    local rabbit1Spawn = nil
    local rabbit2Spawn = nil
    
    if rabbit1ID > 0 then
        rabbit1Spawn = mq.TLO.Spawn(string.format('id %d', rabbit1ID))
    end
    if rabbit2ID > 0 then
        rabbit2Spawn = mq.TLO.Spawn(string.format('id %d', rabbit2ID))
    end
    
    local rabbit1Valid = rabbit1Spawn and rabbit1Spawn() and not rabbit1Spawn.Dead()
    local rabbit2Valid = rabbit2Spawn and rabbit2Spawn() and not rabbit2Spawn.Dead()
    
    -- If no rabbits are alive, resume DPS
    if not rabbit1Valid and not rabbit2Valid then
        ResumeDPS()
        return
    end
    
    local needsMezzing = false
    
    -- Check rabbit1 first - mez if not already mezzed
    if rabbit1Valid then
        local distance = rabbit1Spawn.Distance() or 999
        if distance <= 120 and rabbit1Spawn.LineOfSight() then
            if not hasMezBuff(rabbit1ID) then
                StopDPS()
                castMezOnTarget(rabbit1ID, "a_white_rabbit00")
                needsMezzing = true
                -- Don't return here - we might need to check rabbit2 on next cycle
            end
        end
    end
    
    -- Check rabbit2 - mez if not already mezzed (and we didn't just mez rabbit1)
    if rabbit2Valid and not needsMezzing then
        local distance = rabbit2Spawn.Distance() or 999
        if distance <= 120 and rabbit2Spawn.LineOfSight() then
            if not hasMezBuff(rabbit2ID) then
                StopDPS()
                castMezOnTarget(rabbit2ID, "a_white_rabbit01")
                needsMezzing = true
            end
        end
    end
    
    -- If no mezzing needed (all mezzed), resume DPS
    if not needsMezzing then
        ResumeDPS()
    end
end

-- Command handler for pause/unpause
local function handleCommand(...)
    local args = {...}
    if #args > 0 then
        local cmd = args[1]:lower()
        if cmd == 'on' then
            isPaused = true
            print('[LS Mez] PAUSED - Mez loop stopped')
        elseif cmd == 'off' then
            isPaused = false
            print('[LS Mez] UNPAUSED - Mez loop resumed')
        else
            print('[LS Mez] Usage: /mqp on|off')
        end
    else
        print('[LS Mez] Usage: /mqp on|off')
    end
end

-- Main loop
local function main()
    print('[LS Mez] Starting mez coordination...')
    
    -- Register command
    mq.bind('/mqp', handleCommand)
    print('[LS Mez] Command registered: /mqp on|off')
    
    -- Validate class first (before zone check)
    local myClass = mq.TLO.Me.Class.ShortName()
    if myClass ~= 'ENC' and myClass ~= 'BRD' then
        print(string.format('[LS Mez] ERROR: Class %s is not supported (only ENC/BRD)', myClass))
        print('[LS Mez] Script exiting...')
        return
    end
    
    -- Validate zone
    if not required_zone[mq.TLO.Zone.ShortName()] then
        print('[LS Mez] Not in required zone, exiting')
        return
    end
    
    -- Validate class configuration
    local mez = mezzes[myClass]
    if not mez then
        print('[LS Mez] No mez configuration found, exiting')
        return
    end
    
    -- Initialize
    math.randomseed(os.time()*mq.TLO.Me.ID())
    print('[LS Mez] Mez coordination loaded for ' .. mq.TLO.Me.Class.ShortName())
    
    -- Check spell loadout
    for _, data in ipairs(mez) do
        if data.type == 'spell' then
            local Spellname = mq.TLO.Spell(data.name).RankName()
            if mq.TLO.Me.Gem(Spellname)() and mq.TLO.Me.Gem(Spellname)() > 0 then
                print('[LS Mez] Spell ', data.name,' memmed, good boy')
            else
                print('[LS Mez] Spell ', data.name,' not memmed, you suck')
            end
        end
    end
    
    -- Enable DPS pause to allow mezzing
    print('[LS Mez] Starting with /mqp on and /rdpause on...')
    
    print('[LS Mez] Mez loop active. Monitoring for rabbits...')
    
    -- Main loop
    local running = true
    while running do
        mq.delay(500)  -- Check every 500ms like encmez
        
        -- Only perform mez rotation if not paused
        if not isPaused then
            performMezRotation()
        end
    end
    
    print('[LS Mez] Mez coordination stopped')
end

-- Start the script
main()
