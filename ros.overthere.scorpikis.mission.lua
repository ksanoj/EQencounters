-- Hails scorpikis NPCs in Ring of Scale - What Makes a Scorpiki? 
local mq = require('mq')
local ImGui = require('ImGui')

local NPC_SEARCH_PATTERNS = {
    'npc a_scorpikis',
    'npc a_shifty_scorpikis',
}

local NAV_TIMEOUT_SEC    = 30
local HAIL_WAIT_SEC      = 1.5
local TARGET_WAIT_SEC    = 0.5
local FACE_WAIT_SEC      = 0.3
local APPROACH_WAIT_SEC  = 0.3
local APPROACH_DIST      = 15
local MAIN_LOOP_MS       = 100
local MAX_TARGET_RETRIES = 3

local running     = true
local uiOpen      = true
local spawns      = {}
local spawnById   = {}
local hailedCount = 0
local totalCount  = 0
local currentIdx    = 0
local botState      = 'idle'
local runPhase      = 'none'
local phaseTimer    = 0
local targetRetries = 0
local statusText    = 'Idle - Click "Scan Zone" to find NPCs'

local function clock()
    return os.clock()
end

local function zoneName()
    return (mq.TLO.Zone and mq.TLO.Zone.Name and mq.TLO.Zone.Name()) or 'Unknown'
end

local function scanZone()
    statusText = 'Scanning zone for scorpikis NPCs...'

    local prevHailed = {}
    for _, s in ipairs(spawns) do
        if s.hailed then prevHailed[s.id] = true end
    end

    spawns    = {}
    spawnById = {}
    hailedCount = 0

    for _, pattern in ipairs(NPC_SEARCH_PATTERNS) do
        local count = mq.TLO.SpawnCount(pattern)() or 0
        for i = 1, count do
            local spawn = mq.TLO.NearestSpawn(i, pattern)
            if spawn and spawn.ID and spawn.ID() and spawn.ID() > 0 then
                local id = spawn.ID()
                if not spawnById[id] then
                    local wasHailed = prevHailed[id] or false
                    spawns[#spawns + 1] = {
                        id       = id,
                        name     = (spawn.Name and spawn.Name()) or 'Unknown',
                        distance = (spawn.Distance3D and spawn.Distance3D()) or 9999,
                        hailed   = wasHailed,
                        status   = wasHailed and 'hailed' or 'pending',
                    }
                    spawnById[id] = #spawns
                    if wasHailed then hailedCount = hailedCount + 1 end
                end
            end
        end
    end

    table.sort(spawns, function(a, b) return a.distance < b.distance end)

    spawnById = {}
    for i, s in ipairs(spawns) do spawnById[s.id] = i end

    totalCount = #spawns

    if totalCount == 0 then
        statusText = 'No scorpikis NPCs found in this zone!'
    else
        statusText = string.format('Found %d NPCs (%d already hailed).  Click "Start" to begin.',
                                   totalCount, hailedCount)
    end
end

local function refreshDistances()
    for _, s in ipairs(spawns) do
        local spawn = mq.TLO.Spawn(s.id)
        if spawn and spawn.ID and spawn.ID() and spawn.ID() > 0 then
            s.distance = (spawn.Distance3D and spawn.Distance3D()) or 9999
        else
            s.distance = 9999
        end
    end
end

local function findClosestUnhailed()
    refreshDistances()
    local bestIdx  = nil
    local bestDist = math.huge
    for i, s in ipairs(spawns) do
        if not s.hailed
           and s.status ~= 'despawned'
           and s.status ~= 'nav_timeout'
           and s.status ~= 'skipped'
           and s.status ~= 'target_failed' then
            if s.distance < bestDist then
                bestDist = s.distance
                bestIdx  = i
            end
        end
    end
    return bestIdx
end

local function advanceToNext()
    local nxt = findClosestUnhailed()
    if nxt then
        currentIdx      = nxt
        runPhase        = 'targeting'
        targetRetries   = 0
        spawns[currentIdx].status = 'current'
        statusText = string.format('Targeting %s (ID: %d) [%.0f away] ...',
                                   spawns[currentIdx].name, spawns[currentIdx].id,
                                   spawns[currentIdx].distance)
    else
        botState   = 'done'
        runPhase   = 'none'
        currentIdx = 0
        mq.cmd('/nav stop')
        statusText = string.format('Complete!  Hailed %d / %d NPCs.', hailedCount, totalCount)
    end
end

local function startRun()
    if totalCount == 0 then
        statusText = 'No NPCs found - scan the zone first!'
        return
    end
    botState   = 'running'
    currentIdx = 0
    local first = findClosestUnhailed()
    if first then
        currentIdx    = first
        runPhase      = 'targeting'
        targetRetries = 0
        spawns[currentIdx].status = 'current'
        statusText = string.format('Starting - targeting %s (ID: %d) [%.0f away] ...',
                                   spawns[currentIdx].name, spawns[currentIdx].id,
                                   spawns[currentIdx].distance)
    else
        botState   = 'done'
        statusText = 'All NPCs already hailed!'
    end
end

local function pauseRun()
    if botState == 'running' then
        botState = 'paused'
        mq.cmd('/nav stop')
        statusText = 'Paused'
    end
end

local function resumeRun()
    if botState == 'paused' then
        botState      = 'running'
        runPhase      = 'targeting'
        targetRetries = 0
        if currentIdx > 0 and currentIdx <= #spawns then
            statusText = string.format('Resumed - targeting %s (ID: %d) ...',
                                       spawns[currentIdx].name, spawns[currentIdx].id)
        else
            advanceToNext()
        end
    end
end

local function skipCurrent()
    if (botState == 'running' or botState == 'paused') and currentIdx > 0 and currentIdx <= #spawns then
        mq.cmd('/nav stop')
        spawns[currentIdx].status = 'skipped'
        statusText = string.format('Skipped %s (ID: %d)', spawns[currentIdx].name, spawns[currentIdx].id)
        if botState == 'paused' then botState = 'running' end
        advanceToNext()
    end
end

local function stopRun()
    mq.cmd('/nav stop')
    if currentIdx > 0 and currentIdx <= #spawns and spawns[currentIdx].status == 'current' then
        spawns[currentIdx].status = 'pending'
    end
    botState   = 'idle'
    runPhase   = 'none'
    currentIdx = 0
    statusText = 'Stopped.'
end

local function cleanup()
    mq.cmd('/nav stop')
end

local function processStep()
    if botState ~= 'running' or currentIdx < 1 or currentIdx > #spawns then
        return
    end

    local npc   = spawns[currentIdx]
    local spawn = mq.TLO.Spawn(npc.id)

    if not spawn or not spawn.ID or not spawn.ID() or spawn.ID() == 0 then
        npc.status = 'despawned'
        statusText = string.format('%s (ID: %d) despawned - skipping', npc.name, npc.id)
        advanceToNext()
        return
    end
    if spawn.Dead and spawn.Dead() then
        npc.status = 'despawned'
        statusText = string.format('%s (ID: %d) is dead - skipping', npc.name, npc.id)
        advanceToNext()
        return
    end

    npc.distance = (spawn.Distance3D and spawn.Distance3D()) or 9999

    if runPhase == 'targeting' then
        mq.cmdf('/target id %d', npc.id)
        phaseTimer = clock()
        runPhase   = 'wait_target'

    elseif runPhase == 'wait_target' then
        if clock() - phaseTimer >= TARGET_WAIT_SEC then
            local tid = mq.TLO.Target and mq.TLO.Target.ID and mq.TLO.Target.ID()
            if tid and tid == npc.id then
                mq.cmdf('/nav id %d', npc.id)
                phaseTimer = clock()
                runPhase   = 'navigating'
                statusText = string.format('Navigating to %s (ID: %d) [%.0f away] ...',
                                           npc.name, npc.id, npc.distance)
            else
                targetRetries = targetRetries + 1
                if targetRetries >= MAX_TARGET_RETRIES then
                    npc.status = 'target_failed'
                    statusText = string.format('Could not target %s (ID: %d) - skipping', npc.name, npc.id)
                    advanceToNext()
                else
                    runPhase = 'targeting'
                end
            end
        end

    elseif runPhase == 'navigating' then
        local dist = (spawn.Distance3D and spawn.Distance3D()) or 9999
        npc.distance = dist
        statusText = string.format('Navigating to %s (ID: %d) [%.0f away] ...',
                                   npc.name, npc.id, dist)

        if dist <= APPROACH_DIST then
            mq.cmd('/nav stop')
            phaseTimer = clock()
            runPhase   = 'approach'
        elseif clock() - phaseTimer > NAV_TIMEOUT_SEC then
            mq.cmd('/nav stop')
            npc.status = 'nav_timeout'
            statusText = string.format('Nav timeout: %s (ID: %d) - skipping', npc.name, npc.id)
            advanceToNext()
        elseif mq.TLO.Navigation and mq.TLO.Navigation.Active
               and not mq.TLO.Navigation.Active() then
            if dist > APPROACH_DIST then
                mq.cmdf('/nav id %d', npc.id)
            end
        end

    elseif runPhase == 'approach' then
        if clock() - phaseTimer >= APPROACH_WAIT_SEC then
            mq.cmdf('/target id %d', npc.id)
            mq.cmd('/face fast')
            phaseTimer = clock()
            runPhase   = 'facing'
            statusText = string.format('Facing %s (ID: %d) ...', npc.name, npc.id)
        end

    elseif runPhase == 'facing' then
        if clock() - phaseTimer >= FACE_WAIT_SEC then
            mq.cmd('/keypress H')
            phaseTimer = clock()
            runPhase   = 'wait_hail'
            statusText = string.format('Hailing %s (ID: %d) ...', npc.name, npc.id)
        end

    elseif runPhase == 'wait_hail' then
        if clock() - phaseTimer >= HAIL_WAIT_SEC then
            npc.hailed = true
            npc.status = 'hailed'
            hailedCount = hailedCount + 1
            statusText = string.format('Hailed %s!  [%d / %d complete]',
                                       npc.name, hailedCount, totalCount)
            advanceToNext()
        end
    end
end

local function renderGUI()
    if not uiOpen then return end

    local ret1, ret2 = ImGui.Begin('Scorpikis Hail Bot##MainWindow', uiOpen)
    if ret2 == nil then
        if not ret1 then
            ImGui.End()
            uiOpen = false
            return
        end
    else
        uiOpen = ret1
        if not uiOpen then
            ImGui.End()
            return
        end
    end

    ImGui.Text('Zone: ' .. zoneName())
    ImGui.Text(string.format('NPCs Found: %d   |   Hailed: %d / %d',
                             totalCount, hailedCount, totalCount))

    local pct = totalCount > 0 and (hailedCount / totalCount) or 0
    local overlay = totalCount > 0
        and string.format('%d / %d  (%.1f%%)', hailedCount, totalCount, pct * 100)
        or '-- no data --'
    ImGui.ProgressBar(pct, -1, 0, overlay)

    ImGui.Separator()

    if ImGui.Button('Scan Zone', 90, 22) then
        scanZone()
    end
    ImGui.SameLine()

    if botState == 'idle' or botState == 'done' then
        if ImGui.Button('Start', 70, 22) then startRun() end
    elseif botState == 'running' then
        if ImGui.Button('Pause', 70, 22) then pauseRun() end
    elseif botState == 'paused' then
        if ImGui.Button('Resume', 70, 22) then resumeRun() end
    end
    ImGui.SameLine()

    if ImGui.Button('Stop', 60, 22) then stopRun() end
    ImGui.SameLine()
    if ImGui.Button('Skip', 60, 22) then skipCurrent() end

    ImGui.Separator()

    ImGui.TextColored(0.4, 0.8, 1.0, 1.0, 'Status:')
    ImGui.SameLine()
    ImGui.Text(statusText)

    ImGui.Separator()
    ImGui.Text('NPC List:')

    ImGui.BeginChild('NPCList', 0, 0, true)

    ImGui.Columns(5, 'npc_cols', true)
    ImGui.SetColumnWidth(0, 35)
    ImGui.SetColumnWidth(1, 210)
    ImGui.SetColumnWidth(2, 70)
    ImGui.SetColumnWidth(3, 65)

    ImGui.Text('#')       ImGui.NextColumn()
    ImGui.Text('Name')    ImGui.NextColumn()
    ImGui.Text('ID')      ImGui.NextColumn()
    ImGui.Text('Dist')    ImGui.NextColumn()
    ImGui.Text('Status')  ImGui.NextColumn()
    ImGui.Separator()

    for i, npc in ipairs(spawns) do
        local r, g, b, a = 0.7, 0.7, 0.7, 1.0
        local label = 'Pending'

        if npc.status == 'hailed' then
            r, g, b = 0.0, 1.0, 0.3
            label = 'Hailed'
        elseif npc.status == 'current' then
            r, g, b = 1.0, 1.0, 0.0
            label = '>> Current'
        elseif npc.status == 'skipped' then
            r, g, b = 1.0, 0.6, 0.0
            label = 'Skipped'
        elseif npc.status == 'despawned' then
            r, g, b = 1.0, 0.2, 0.2
            label = 'Despawned'
        elseif npc.status == 'nav_timeout' then
            r, g, b = 1.0, 0.35, 0.35
            label = 'Nav Timeout'
        elseif npc.status == 'target_failed' then
            r, g, b = 1.0, 0.35, 0.35
            label = 'Target Failed'
        end

        ImGui.TextColored(r, g, b, a, tostring(i))                              ImGui.NextColumn()
        ImGui.TextColored(r, g, b, a, npc.name)                                 ImGui.NextColumn()
        ImGui.TextColored(r, g, b, a, tostring(npc.id))                         ImGui.NextColumn()
        ImGui.TextColored(r, g, b, a, string.format('%.0f', npc.distance))      ImGui.NextColumn()
        ImGui.TextColored(r, g, b, a, label)                                    ImGui.NextColumn()
    end

    ImGui.Columns(1)
    ImGui.EndChild()

    ImGui.End()
end

local function main()
    mq.imgui.init('ScorpikisHailBot', renderGUI)
    printf('\ag[Scorpikis Hail Bot]\aw Loaded.  Use the GUI to scan and hail NPCs.')

    while running do
        if not uiOpen then
            running = false
            break
        end
        processStep()
        mq.delay(MAIN_LOOP_MS)
    end

    cleanup()
    printf('\ag[Scorpikis Hail Bot]\aw Shutting down.')
end

local ok, err = pcall(main)
if not ok then
    printf('\ar[Scorpikis Hail Bot] Error: %s\aw', tostring(err))
    cleanup()
end
