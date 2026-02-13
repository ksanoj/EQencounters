---@type Mq
local mq = require('mq')

local dpsPaused = false  -- Track DPS pause state to avoid spam

local required_zone = {
    ['mischiefplane_raid'] = true,  -- Add your zone here
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
        {name='Dirge of the Sleepwalker', type='aa', order='1'},
        {name='Slumber of Suja', type='spell', order='2'},
    },
}

-- Classes that should not be interrupted while casting
local unbreakable = {
    ['ENC'] = false,  -- Enchanter mez is interruptible
    ['BRD'] = false,  -- Bard mez is interruptible
}

-- Spawn caching for performance
local lastSpawnCheck = 0
local spawnCheckInterval = 500  -- Check spawns frequently for fast mez response
local cachedSpawns = {}  -- Cached list of rabbit spawn data

-- Hardcoded rabbit spawn names (maximum possible)
local mezTargetNames = {
    'a_white_rabbit00',
    'a_white_rabbit01',
    'a_white_rabbit02',
    'a_white_rabbit03',
}

-- Update cached spawns - direct lookup for each known rabbit
local function updateSpawnCache()
    local currentTime = mq.gettime()
    
    if currentTime - lastSpawnCheck < spawnCheckInterval then
        return
    end
    
    lastSpawnCheck = currentTime
    
    cachedSpawns = {}
    
    for _, name in ipairs(mezTargetNames) do
        local spawn = mq.TLO.Spawn(string.format('npc "%s"', name))
        if spawn and spawn() and spawn.ID() and spawn.ID() > 0 then
            table.insert(cachedSpawns, {
                ID = spawn.ID(),
                CleanName = spawn.CleanName() or name,
                Distance = spawn.Distance() or 999,
                LineOfSight = spawn.LineOfSight() or false,
            })
        end
    end
    
    if #cachedSpawns > 0 then
        print(string.format('[LS Mez] Found %d rabbit(s)', #cachedSpawns))
        for i, s in ipairs(cachedSpawns) do
            print(string.format('[LS Mez]   #%d: %s (ID: %s, Dist: %.0f, LoS: %s)', 
                i, s.CleanName, s.ID, s.Distance, tostring(s.LineOfSight)))
        end
    end
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
    end
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
end

-- Cached mez abilities (populated at startup with resolved rank names / AA IDs)
local cachedMezAbilities = {}

local function initMezCache(myClass)
    local mez = mezzes[myClass]
    if not mez then return end
    
    -- Sort once at startup
    table.sort(mez, function(a, b) return a['order'] < b['order'] end)
    
    for _, data in ipairs(mez) do
        local entry = { name = data.name, type = data.type, order = data.order }
        if data.type == 'spell' then
            entry.rankName = mq.TLO.Spell(data.name).RankName() or data.name
        elseif data.type == 'aa' then
            entry.aaID = mq.TLO.Me.AltAbility(data.name).ID() or 0
        end
        table.insert(cachedMezAbilities, entry)
    end
    
    print(string.format('[LS Mez] Cached %d mez abilities for %s', #cachedMezAbilities, myClass))
end

local function mez_ready(data)
    local isUnbreakable = unbreakable[mq.TLO.Me.Class.ShortName()]
    if data.type == 'spell' then
        local ready = mq.TLO.Me.SpellReady(data.rankName)()
        return ready and (not isUnbreakable or not mq.TLO.Me.Casting())
    elseif data.type == 'aa' then
        local ready = mq.TLO.Me.AltAbilityReady(data.name)()
        return ready and (not isUnbreakable or not mq.TLO.Me.Casting())
    end
    return false
end

-- Simple mez function - target is already validated by performMezRotation
local function castMezOnTarget(targetID, targetName)
    if not targetID or targetID == 0 then return false end
    
    -- Target the mob
    mq.cmdf('/target id %d', targetID)
    mq.delay(200, function() return mq.TLO.Target.ID() == targetID end)
    
    -- Verify target
    if mq.TLO.Target.ID() ~= targetID then
        print(string.format('[LS Mez] Failed to target %s (ID: %d)', targetName, targetID))
        return false
    end
    
    -- Check line of sight
    if not mq.TLO.Target.LineOfSight() then
        return false
    end
    
    -- Skip if target is fleeing (pathing out of room)
    if mq.TLO.Target.Fleeing() then
        return false
    end
    
    -- Try to cast first available mez (already sorted at startup)
    for _, data in ipairs(cachedMezAbilities) do
        if mez_ready(data) then
            print(string.format('[LS Mez] Mezzing %s (ID: %d) with %s', targetName, targetID, data.name))
            
            if data.type == 'spell' then
                mq.cmdf('/cast "%s"', data.rankName)
            else
                mq.cmdf('/alt activate %d', data.aaID)
            end
            
            -- Wait for cast to complete with timeout (max 10 seconds)
            mq.delay(100)
            local castWait = 0
            while mq.TLO.Me.Casting() and castWait < 200 do
                mq.delay(50)
                castWait = castWait + 1
            end
            
            -- Bards need to stop singing after cast or the song keeps pulsing
            if mq.TLO.Me.Class.ShortName() == 'BRD' then
                mq.cmd('/squelch /stopsong')
                mq.delay(50)
            end
            
            print(string.format('[LS Mez] Cast %s on %s', data.name, targetName))
            return true
        end
    end
    
    return false
end

-- Main mez check - prioritize closest non-fleeing rabbit in line of sight
local function performMezRotation()
    -- Update spawn cache
    updateSpawnCache()
    
    -- Build list of valid rabbits (in range, LoS)
    local targets = {}
    
    for _, spawn in ipairs(cachedSpawns) do
        local id = spawn['ID']
        local name = spawn['CleanName']
        local dist = spawn['Distance'] or 999
        local los = spawn['LineOfSight']
        
        if id and id > 0 and dist <= 120 and los then
            table.insert(targets, { id = id, name = name, distance = dist })
        end
    end
    
    -- Nothing needs mezzing
    if #targets == 0 then
        ResumeDPS()
        return
    end
    
    -- Sort by distance (closest first)
    table.sort(targets, function(a, b) return a.distance < b.distance end)
    
    -- Try each target in distance order until one succeeds
    StopDPS()
    for _, target in ipairs(targets) do
        if castMezOnTarget(target.id, target.name) then
            return
        end
    end
end

-- Main loop
local function main()
    print('[LS Mez] Starting mez coordination...')
    
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

    -- Cache spell data at startup
    initMezCache(myClass)
    if #cachedMezAbilities == 0 then
        print('[LS Mez] No mez abilities resolved, exiting')
        return
    end
    
    print('[LS Mez] Mez loop active. Monitoring for rabbits...')
    
    -- Main loop
    while true do
        mq.delay(250)
        
        -- Skip if dead
        if (mq.TLO.Me.PctHPs() or 0) < 5 then
            goto continue
        end
        
        -- Exit if no longer in required zone
        if not required_zone[mq.TLO.Zone.ShortName()] then
            print('[LS Mez] Left required zone - terminating.')
            ResumeDPS()
            return
        end
        
        performMezRotation()
        ::continue::
    end
end

-- Start the script
main()
