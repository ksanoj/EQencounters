local mq = require('mq')
local ImGui = require('ImGui')

-- State
local running = true
local ui_open = true
local started = false

local getMissionStatus = ''  -- status text for Get Mission
local combatStatus = ''      -- status text shown in GUI
local killCount = 0          -- number of mobs killed

local guiFlags = {
    startRequested = false,
    getMissionRequested = false,
    enterMissionRequested = false,
}

local REQUIRED_ZONE = 'paineel_av25mission'
local MISSION_ZONE = 'katta'
local MISSION_NPC = 'Ghrald McMannus'

--- Check if we are in the required zone
local function isInRequiredZone()
    local zone = mq.TLO.Zone.ShortName() or ''
    return zone == REQUIRED_ZONE
end

--- Find the first alive XTarget mob and return its index and ID
local function getNextXTarget()
    local slots = mq.TLO.Me.XTargetSlots() or 0
    for i = 1, slots do
        local xt = mq.TLO.Me.XTarget(i)
        if xt and xt.ID() and xt.ID() > 0 and not xt.Dead() then
            return i, xt.ID()
        end
    end
    return nil, nil
end

--- Wait for nav to finish
local function waitForNav()
    mq.delay(500)
    while mq.TLO.Navigation.Active() do
        if not running then return end
        mq.delay(100)
    end
end

--- Kill a single target by ID
local function killTarget(id)
    mq.cmdf('/target id %d', id)
    mq.delay(500)

    if not mq.TLO.Target.ID() or mq.TLO.Target.ID() ~= id then
        return
    end

    local targetName = mq.TLO.Target.CleanName() or 'Unknown'

    -- Wait for line of sight before engaging
    combatStatus = 'Waiting for LoS: ' .. targetName
    local losRetries = 50  -- up to 5 seconds
    while not mq.TLO.Target.LineOfSight() and losRetries > 0 do
        if not running then return end
        mq.delay(100)
        losRetries = losRetries - 1
    end
    if not mq.TLO.Target.LineOfSight() then
        combatStatus = 'No LoS to ' .. targetName .. ', skipping'
        return
    end

    combatStatus = 'Fighting: ' .. targetName

    mq.cmd('/stick moveback 5')
    mq.delay(200)
    mq.cmd('/attack on')

    while mq.TLO.Target.ID() and mq.TLO.Target.ID() == id and not mq.TLO.Target.Dead() do
        if not running then
            mq.cmd('/attack off')
            return
        end
        mq.delay(100)
    end

    mq.cmd('/attack off')
    killCount = killCount + 1
    combatStatus = targetName .. ' dead'
    mq.delay(300)
end

--- Combat loop: kill all XTarget mobs one by one
local function combatLoop()
    -- Wait up to 5 seconds for mobs to appear on XTarget
    local retries = 10
    local idx, id = getNextXTarget()
    while not idx and retries > 0 do
        combatStatus = 'Waiting for mobs on XTarget...'
        mq.delay(500)
        retries = retries - 1
        idx, id = getNextXTarget()
        if not running then return end
    end

    while running do
        idx, id = getNextXTarget()
        if not idx then
            combatStatus = 'No more targets on XTarget'
            -- Brief wait in case a new mob pops
            mq.delay(1000)
            idx, id = getNextXTarget()
            if not idx then
                break
            end
        end
        if idx and id then
            killTarget(id)
        end
    end
    combatStatus = 'Combat complete'
end

--- Navigate to a spawn and kill all XTarget mobs there
local function navAndKill(spawnName)
    combatStatus = 'Navigating to ' .. spawnName .. '...'
    print('[25th] Navigating to ' .. spawnName .. '...')
    mq.cmdf('/nav spawn %s', spawnName)
    waitForNav()

    if not running then return end

    combatStatus = 'Killing at ' .. spawnName .. '...'
    print('[25th] Arrived at ' .. spawnName .. '. Engaging XTarget mobs...')
    combatLoop()
    print('[25th] All mobs cleared at ' .. spawnName)
end

--- Navigate to a loc and kill all XTarget mobs there
local function navLocAndKill(y, x, z, label)
    label = label or string.format('%.0f, %.0f, %.0f', y, x, z)
    combatStatus = 'Navigating to ' .. label .. '...'
    print('[25th] Navigating to ' .. label .. '...')
    mq.cmdf('/nav loc %.2f %.2f %.2f', y, x, z)
    waitForNav()

    if not running then return end

    combatStatus = 'Killing at ' .. label .. '...'
    print('[25th] Arrived at ' .. label .. '. Engaging XTarget mobs...')
    combatLoop()
    print('[25th] All mobs cleared at ' .. label)
end

--- Called when Start is clicked
local function onStart()
    started = true

    navAndKill('not a fae drake')
    if not running then return end

    navAndKill('not a drake')
    if not running then return end

    navAndKill('not an undead drake')
    if not running then return end

    navLocAndKill(1117.58, 734.14, -39.02, 'spot 4')
    if not running then return end

    navLocAndKill(1147.89, 412.19, -40.02, 'spot 5')
    if not running then return end

    combatStatus = 'All spots cleared'
    print('[25th] All spots cleared.')
end

--- Called when Get Mission is clicked
local function onGetMission()
    local function spawnDistance()
        local spawn = mq.TLO.Spawn('npc ' .. MISSION_NPC)
        if spawn and spawn.ID() and spawn.ID() > 0 then
            return spawn.Distance3D() or 999
        end
        return 999
    end

    -- Navigate to NPC if not within 22 radius
    if spawnDistance() > 22 then
        getMissionStatus = 'Navigating to ' .. MISSION_NPC .. '...'
        mq.cmdf('/nav spawn %s', MISSION_NPC)
        mq.delay(500) -- let nav start
        while spawnDistance() > 22 do
            if not running then return end
            mq.delay(100)
        end
        mq.cmd('/nav stop')
    end

    -- Target the NPC
    getMissionStatus = 'Targeting ' .. MISSION_NPC .. '...'
    mq.cmdf('/target npc %s', MISSION_NPC)
    mq.delay(1000)

    -- Say the keyword
    getMissionStatus = 'Saying plane...'
    mq.cmd('/say plane')
    mq.delay(500)

    getMissionStatus = 'Done'
    print('[25th] Get Mission complete.')
end

--- Called when Enter Mission is clicked
local function onEnterMission()
    getMissionStatus = 'Entering mission...'
    mq.cmd('/dgz /target McMannus')
    mq.delay(2000)
    mq.cmd('/dgz /say prepared')
    mq.delay(500)
    getMissionStatus = 'Mission entered'
    print('[25th] Enter Mission complete.')
end

--- ImGui render callback
local function renderUI()
    if not ui_open then return end

    ui_open, _ = ImGui.Begin('25th Anniversary', ui_open, ImGuiWindowFlags_AlwaysAutoResize)
    if not ui_open then
        ImGui.End()
        return
    end

    local zone = mq.TLO.Zone.ShortName() or ''
    ImGui.Text('Zone: ' .. zone)
    ImGui.Separator()

    if isInRequiredZone() then
        if not started then
            if ImGui.Button('Start', 120, 30) then
                guiFlags.startRequested = true
            end
        else
            ImGui.TextColored(0, 1, 0, 1, 'Running')
            ImGui.Text('Kills: ' .. killCount)
            if combatStatus ~= '' then
                ImGui.Text(combatStatus)
            end
            if ImGui.Button('Reset', 120, 30) then
                started = false
                killCount = 0
                combatStatus = ''
            end
        end
    end

    if zone == MISSION_ZONE then
        if ImGui.Button('Get Mission', 120, 30) then
            guiFlags.getMissionRequested = true
        end
        ImGui.SameLine()
        if ImGui.Button('Enter Mission', 120, 30) then
            guiFlags.enterMissionRequested = true
        end
        if getMissionStatus ~= '' then
            ImGui.Text(getMissionStatus)
        end
    end

    if not isInRequiredZone() and zone ~= MISSION_ZONE then
        ImGui.TextColored(1, 0.5, 0, 1, 'Go to katta or paineel_av25mission')
    end

    ImGui.End()
end

-- Register GUI
mq.imgui.init('25thUI', renderUI)

-- Main loop
while running do
    if not ui_open then
        running = false
        break
    end

    if guiFlags.startRequested then
        guiFlags.startRequested = false
        onStart()
    end

    if guiFlags.getMissionRequested then
        guiFlags.getMissionRequested = false
        onGetMission()
    end

    if guiFlags.enterMissionRequested then
        guiFlags.enterMissionRequested = false
        onEnterMission()
    end

    mq.doevents()
    mq.delay(100)
end

print('[25th] Exiting.')
