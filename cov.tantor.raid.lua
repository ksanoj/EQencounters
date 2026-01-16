local mq = require('mq')
local ImGui = require('ImGui')

local ZONE_NAME = 'westwastestwo_raid'
local ENABLE_TANTRUM = false
local isRunningFromTantor = false
local isDuckingFromRock = false
local guiOpen = true

local function nowMs()
    if mq and mq.gettime then return mq.gettime() end
    return os.clock() * 1000
end

-- Drive longer actions from the main loop so mq.doevents() stays responsive.
local state = {
    run = { active = false, stage = 0, stageAtMs = 0, returnStage = 0 },
    rock = { active = false, stage = 0, stageAtMs = 0, lastDuckKeyMs = 0 },
    tantrum = { active = false, stage = 0, stageAtMs = 0 },
}

-- Throttle expensive spawn scanning in GUI
local spawnCache = {
    lastUpdateMs = 0,
    guardians = {},
    tantorlings = {},
}

local function refreshSpawnCache()
    spawnCache.guardians = {}
    spawnCache.tantorlings = {}
    spawnCache.lastUpdateMs = nowMs()

    local guardianSearch = mq.TLO.SpawnCount('npc "a primal guardian" radius 1000')
    if guardianSearch and guardianSearch() and guardianSearch() > 0 then
        for i = 1, guardianSearch() do
            local guardian = mq.TLO.NearestSpawn(string.format('%d,npc "a primal guardian" radius 1000', i))
            if guardian and guardian.ID() and guardian.ID() > 0 then
                table.insert(spawnCache.guardians, {
                    id = guardian.ID(),
                    name = guardian.Name() or 'Unknown',
                    hp = guardian.PctHPs() or 0,
                })
            end
        end
    end

    local tantorlingSearch = mq.TLO.SpawnCount('npc "a tantorling" radius 1000')
    if tantorlingSearch and tantorlingSearch() and tantorlingSearch() > 0 then
        for i = 1, tantorlingSearch() do
            local tantorling = mq.TLO.NearestSpawn(string.format('%d,npc "a tantorling" radius 1000', i))
            if tantorling and tantorling.ID() and tantorling.ID() > 0 then
                table.insert(spawnCache.tantorlings, {
                    id = tantorling.ID(),
                    name = tantorling.Name() or 'Unknown',
                    hp = tantorling.PctHPs() or 0,
                })
            end
        end
    end
end

local function on_tantor_giveup(line, ...)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    if not isRunningFromTantor then return end
    state.run.returnStage = 1
end

local function on_tantor_roar(line, target)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    local tgt = (target or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%p%s]+$', '')
    if tgt ~= me then return end
    -- Non-blocking: main loop will drive the rest.
    isRunningFromTantor = true
    state.run.active = true
    state.run.stage = 1
    state.run.stageAtMs = nowMs()
end

local function on_tantor_rock(line, target)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    local tgt = (target or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%p%s]+$', '')
    if tgt ~= me then return end
    -- Non-blocking: main loop will repeatedly attempt to duck until successful.
    isDuckingFromRock = true
    state.rock.active = true
    state.rock.stage = 1
    state.rock.stageAtMs = nowMs()
    state.rock.lastDuckKeyMs = 0
end

local function on_tantor_rock_miss(line)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    
    -- Only process if THIS character was the one ducking
    if not isDuckingFromRock then return end

    -- Non-blocking: main loop will stand/unpause/cleanup.
    state.rock.stage = 3
    state.rock.stageAtMs = nowMs()
end

local function on_small_mammoths(line, name1, name2, name3)
    if not ENABLE_TANTRUM then return end
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    local function sanitize(s)
        return (s or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%p%s]+$', '')
    end
    local n1, n2, n3 = sanitize(name1), sanitize(name2), sanitize(name3)
    if me ~= n1 and me ~= n2 and me ~= n3 then return end
    state.tantrum.active = true
    state.tantrum.stage = 1
    state.tantrum.stageAtMs = nowMs()
end

mq.event('COV_TANTOR_ROAR', "#*#Tantor roars, pointing its trunk at #1#.", on_tantor_roar)
mq.event('COV_TANTOR_GIVEUP', "#*#Tantor gives up the chase#*#", on_tantor_giveup)
mq.event('COV_TANTOR_ROCK', "#*#Tantor grabs a rock with its trunk and turns toward #1#.#*#", on_tantor_rock)
mq.event('COV_TANTOR_ROCK_MISS', "#*#A rock whizzes over the head of its intended target.#*#", on_tantor_rock_miss)
mq.event('COV_TANTOR_TANTRUM', "#*#The small mammoths trumpet and prepare to throw a tantrum at #1#, #2#, and #3#.", on_small_mammoths)

local function drawGUI()
    local currentZone = mq.TLO.Zone.ShortName() or ''
    if currentZone ~= ZONE_NAME then return end
    if not guiOpen then return end

    -- Refresh heavy spawn lists at most twice per second.
    local now = nowMs()
    if (now - (spawnCache.lastUpdateMs or 0)) > 500 then
        refreshSpawnCache()
    end

    local show
    guiOpen, show = ImGui.Begin("Tantor HP", guiOpen, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar))
    if not show then
        ImGui.End()
        return
    end
    local tantor = mq.TLO.Spawn('#Tantor')
    if tantor and tantor.ID() and tantor.ID() > 0 then
        local hpPercent = tantor.PctHPs() or 0
        ImGui.Text(string.format("Tantor: %d%%", hpPercent))
        
        -- Flashing red DUCKING! text if player is ducking
        if mq.TLO.Me.Ducking() then
            local flashRate = math.floor(os.clock() * 2) % 2  -- Flash every 0.5 seconds
            if flashRate == 0 then
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 0, 0, 1))  -- Bright red
                ImGui.Text("DUCKING!")
                ImGui.PopStyleColor()
            end
        end
        
        if hpPercent > 71 then
            ImGui.Text("Tantorlings will Spawn at 71%")
        elseif hpPercent > 56 then
            ImGui.Text("Tantorlings will Spawn at 56%")
        elseif hpPercent > 39 then
            ImGui.Text("Tantorlings will Spawn at 39%")
        elseif hpPercent > 24 then
            ImGui.Text("Tantorlings will Spawn at 24%")
        end
    else
        ImGui.Text("Tantor: Not Found")
    end
    local guardianFound = false
    for _, g in ipairs(spawnCache.guardians) do
        local spawnID = g.id
        local spawnName = g.name
        local hpPercent = g.hp
        ImGui.Text(string.format("%s [ID:%d] %d%%", spawnName, spawnID, hpPercent))
        ImGui.SameLine()
        if ImGui.Button(string.format("Target##guardian%d", spawnID)) then
            mq.cmdf('/target %s', spawnName)
        end
        guardianFound = true
    end
    if not guardianFound then
        ImGui.Text("No Primal Guardians up")
    end
    local tantorlingFound = false
    for _, t in ipairs(spawnCache.tantorlings) do
        local spawnID = t.id
        local spawnName = t.name
        local hpPercent = t.hp
        ImGui.Text(string.format("%s [ID:%d] %d%%", spawnName, spawnID, hpPercent))
        ImGui.SameLine()
        if ImGui.Button(string.format("Target##tantorling%d", spawnID)) then
            mq.cmdf('/target %s', spawnName)
        end
        tantorlingFound = true
    end
    if not tantorlingFound then
        ImGui.Text("No Tantorlings up")
    end
    
    -- Setup instructions
    ImGui.Separator()
    ImGui.TextWrapped("Setup: set MT for permatanking Tantor. set ST for autopickup a_primal_guardian00 and activate auto. No mounts if you want duck achevement.")
    
    ImGui.End()
end

print('covtantor.lua loaded')
mq.imgui.init('TantorHP', drawGUI)

local function tickState()
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end

    local now = nowMs()

    -- Roar/run-away sequence (non-blocking)
    if state.run.active then
        if state.run.stage == 1 then
            mq.cmd('/dgz /alt act 3704')
            mq.cmd('/mqp on')
            mq.cmd('/rdpause on')
            mq.cmd('/dgt [LUA] Running from Tantor!')
            mq.cmd('/nav recordwaypoint tmpcamp "tmp camp"')
            state.run.stage = 2
            state.run.stageAtMs = now
        elseif state.run.stage == 2 then
            if (now - state.run.stageAtMs) > 500 then
                mq.cmd('/circle on 200')
                mq.cmd('/circle loc -646.06 -936.68')
                state.run.stage = 3
            end
        end
    end

    -- Give-up/return-to-raid sequence (non-blocking)
    if state.run.returnStage == 1 then
        mq.cmd('/circle off')
        mq.cmd('/nav wp tmpcamp')
        state.run.returnStage = 2
        state.run.stageAtMs = now
    elseif state.run.returnStage == 2 then
        if not mq.TLO.Navigation.Active() then
            mq.cmd('/mqp off')
            mq.cmd('/rdpause off')
            mq.cmd('/dgt [LUA] Returning to raid')
            isRunningFromTantor = false
            state.run.active = false
            state.run.stage = 0
            state.run.returnStage = 0
        end
    end

    -- Rock ducking sequence (non-blocking, retries duck keypress to handle lag)
    if state.rock.active then
        if state.rock.stage == 1 then
            mq.cmd('/dgt [LUA] Ducking for stone.')
            mq.cmd('/mqp on')
            mq.cmd('/rdpause on')
            mq.cmd('/dismount')
            state.rock.stage = 2
            state.rock.stageAtMs = now
            state.rock.lastDuckKeyMs = 0
        elseif state.rock.stage == 2 then
            if not mq.TLO.Me.Ducking() then
                if (now - (state.rock.lastDuckKeyMs or 0)) > 250 then
                    mq.cmd('/keypress DUCK')
                    state.rock.lastDuckKeyMs = now
                end
            end
        elseif state.rock.stage == 3 then
            mq.cmd('/dgt [LUA] Stone missed re-engaging')
            if mq.TLO.Me.Ducking() then
                mq.cmd('/keypress DUCK')
            end
            mq.cmd('/rdpause off')
            mq.cmd('/mqp off')
            isDuckingFromRock = false
            state.rock.active = false
            state.rock.stage = 0
        end
    end

    -- Tantrum sequence (non-blocking)
    if state.tantrum.active then
        if state.tantrum.stage == 1 then
            mq.cmd('/nav recordwaypoint tmpcamp "tmp camp"')
            state.tantrum.stage = 2
            state.tantrum.stageAtMs = now
        elseif state.tantrum.stage == 2 then
            if (now - state.tantrum.stageAtMs) > 1000 then
                mq.cmd('/nav locxyz 3170 -730 -64')
                state.tantrum.stage = 3
            end
        elseif state.tantrum.stage == 3 then
            if not mq.TLO.Navigation.Active() then
                state.tantrum.stage = 4
            end
        elseif state.tantrum.stage == 4 then
            mq.cmd('/nav waypoint tmpcamp')
            state.tantrum.stage = 5
        elseif state.tantrum.stage == 5 then
            if not mq.TLO.Navigation.Active() then
                state.tantrum.active = false
                state.tantrum.stage = 0
            end
        end
    end
end

local lastAntiFeign = 0
while guiOpen do
    mq.doevents()
    tickState()
    local now = os.time()
    if now > lastAntiFeign then
        if mq.TLO.Me.Feigning() and mq.TLO.Me.Class.ShortName() ~= 'MNK' then
            mq.cmd('/stand')
            mq.delay(100)
        end
        lastAntiFeign = now
    end
    mq.delay(50)
end

print('covtantor.lua stopped')
