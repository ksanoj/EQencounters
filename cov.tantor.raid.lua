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

local state = {
    run = { active = false, stage = 0, stageAtMs = 0, returnStage = 0 },
    rock = { active = false, stage = 0, stageAtMs = 0, lastDuckKeyMs = 0, wasMqpOn = false, wasRdpauseOn = false },
    tantrum = { active = false, stage = 0, stageAtMs = 0 },
}

local spawnCache = {
    lastUpdateMs = 0,
    guardians = {},
    tantorlings = {},
}

local ROCK_TIMEOUT_MS = 10000
local RUN_TIMEOUT_MS = 30000
local NAV_TIMEOUT_MS = 15000
local RETURN_NAV_GRACE_MS = 500

local function sanitize(s)
    return (s or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%p%s]+$', '')
end

local cachedZone = ''

local function refreshSpawnCache()
    spawnCache.guardians = {}
    spawnCache.tantorlings = {}
    spawnCache.lastUpdateMs = nowMs()

    local guardianCount = mq.TLO.SpawnCount('npc "a primal guardian" radius 1000')() or 0
    for i = 1, guardianCount do
        local guardian = mq.TLO.NearestSpawn(string.format('%d,npc "a primal guardian" radius 1000', i))
        if guardian and guardian.ID() and guardian.ID() > 0 then
            table.insert(spawnCache.guardians, {
                id = guardian.ID(),
                name = guardian.Name() or 'Unknown',
                hp = guardian.PctHPs() or 0,
            })
        end
    end

    local tantorlingCount = mq.TLO.SpawnCount('npc "a tantorling" radius 1000')() or 0
    for i = 1, tantorlingCount do
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

local function on_tantor_giveup(line, ...)
    if cachedZone ~= ZONE_NAME then return end
    if not isRunningFromTantor then return end
    state.run.returnStage = 1
end

local function on_tantor_roar(line, target)
    if cachedZone ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    if sanitize(target) ~= me then return end
    isRunningFromTantor = true
    state.run.active = true
    state.run.stage = 1
    state.run.stageAtMs = nowMs()
end

local function on_tantor_rock(line, target)
    if cachedZone ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    if sanitize(target) ~= me then return end
    isDuckingFromRock = true
    state.rock.active = true
    state.rock.stage = 1
    state.rock.stageAtMs = nowMs()
    state.rock.lastDuckKeyMs = 0
end

local function on_tantor_rock_miss(line)
    if cachedZone ~= ZONE_NAME then return end
    if not isDuckingFromRock then return end
    state.rock.stage = 4  -- Jump to cleanup
    state.rock.stageAtMs = nowMs()
end

local function on_small_mammoths(line, name1, name2, name3)
    if not ENABLE_TANTRUM then return end
    if cachedZone ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
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
    local tantor = mq.TLO.Spawn('npc Tantor')
    if tantor and tantor.ID() and tantor.ID() > 0 then
        local hpPercent = tantor.PctHPs() or 0
        ImGui.Text(string.format("Tantor: %d%%", hpPercent))
        
        -- Flashing red DUCKING! text if player is ducking
        if mq.TLO.Me.Ducking() then
            local flashAlpha = (math.floor(os.clock() * 4) % 2 == 0) and 1.0 or 0.3
            ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 0, 0, flashAlpha))
            ImGui.Text("DUCKING!")
            ImGui.PopStyleColor()
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
    cachedZone = mq.TLO.Zone.ShortName() or ''
    if cachedZone ~= ZONE_NAME then return end

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
                state.run.stageAtMs = now
            end
        elseif state.run.stage == 3 then
            if (now - state.run.stageAtMs) > RUN_TIMEOUT_MS then
                mq.cmd('/dgt [LUA] Run timeout - forcing return')
                state.run.returnStage = 1
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
        local elapsed = now - state.run.stageAtMs
        if elapsed > RETURN_NAV_GRACE_MS and not mq.TLO.Navigation.Active() then
            mq.cmd('/mqp off')
            mq.cmd('/rdpause off')
            mq.cmd('/dgt [LUA] Returning to raid')
            isRunningFromTantor = false
            state.run.active = false
            state.run.stage = 0
            state.run.returnStage = 0
        elseif elapsed > NAV_TIMEOUT_MS then
            mq.cmd('/nav stop')
            mq.cmd('/mqp off')
            mq.cmd('/rdpause off')
            mq.cmd('/dgt [LUA] Return nav timeout - unpausing')
            isRunningFromTantor = false
            state.run.active = false
            state.run.stage = 0
            state.run.returnStage = 0
        end
    end

    -- Rock ducking sequence (non-blocking, with pause state preservation)
    if state.rock.active then
        if state.rock.stage == 1 then
            -- Stage 1: Save state, pause, dismount
            state.rock.wasMqpOn = mq.TLO.MacroQuest.Paused and mq.TLO.MacroQuest.Paused() or false
            state.rock.wasRdpauseOn = _G.RdPaused or false
            mq.cmd('/mqp on')
            mq.cmd('/rdpause on')
            mq.cmd('/dismount')
            mq.cmd('/dgt [LUA] Ducking for stone.')
            state.rock.stage = 2
            state.rock.stageAtMs = now
            state.rock.lastDuckKeyMs = 0
        elseif state.rock.stage == 2 then
            -- Stage 2: Wait for dismount (1 second)
            if (now - state.rock.stageAtMs) >= 1000 then
                state.rock.stage = 3
                state.rock.stageAtMs = now
            end
        elseif state.rock.stage == 3 then
            -- Stage 3: Duck and maintain
            if (now - state.rock.stageAtMs) > ROCK_TIMEOUT_MS then
                state.rock.stage = 4
                state.rock.stageAtMs = now
            elseif not mq.TLO.Me.Ducking() then
                if (now - state.rock.lastDuckKeyMs) > 250 then
                    mq.cmd('/keypress DUCK')
                    state.rock.lastDuckKeyMs = now
                end
            end
        elseif state.rock.stage == 4 then
            -- Stage 4: Cleanup with state preservation
            if mq.TLO.Me.Ducking() then
                mq.cmd('/keypress DUCK')
            end
            if not state.rock.wasRdpauseOn then mq.cmd('/rdpause off') end
            if not state.rock.wasMqpOn then mq.cmd('/mqp off') end
            mq.cmd('/dgt [LUA] Stone complete - re-engaging')
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
            if not mq.TLO.Navigation.Active() or (now - state.tantrum.stageAtMs) > NAV_TIMEOUT_MS then
                state.tantrum.stage = 4
                state.tantrum.stageAtMs = now
            end
        elseif state.tantrum.stage == 4 then
            mq.cmd('/nav waypoint tmpcamp')
            state.tantrum.stage = 5
            state.tantrum.stageAtMs = now
        elseif state.tantrum.stage == 5 then
            if not mq.TLO.Navigation.Active() or (now - state.tantrum.stageAtMs) > NAV_TIMEOUT_MS then
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
