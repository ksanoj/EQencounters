local mq = require('mq')
local ImGui = require('ImGui')

local ZONE_NAME = 'westwastestwo_raid'
local ENABLE_TANTRUM = false
local isRunningFromTantor = false
local isDuckingFromRock = false
local guiOpen = true

local function on_tantor_giveup(line, ...)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    if not isRunningFromTantor then return end
    mq.cmd('/circle off')
    mq.cmd('/nav wp tmpcamp')
    while mq.TLO.Navigation.Active() do
        mq.delay(250)
    end
    mq.cmd('/mqp off')
    mq.cmd('/rdpause off')
    mq.cmd('/dgt [LUA] Returning to raid')
    isRunningFromTantor = false
end

local function on_tantor_roar(line, target)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    local tgt = (target or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%p%s]+$', '')
    if tgt ~= me then return end
    mq.cmd('/dgz /alt act 3704')
    mq.cmd('/mqp on')
    mq.cmd('/rdpause on')
    mq.cmd('/dgt [LUA] Running from Tantor!')
    mq.delay(100)
    isRunningFromTantor = true
    mq.cmd('/nav recordwaypoint tmpcamp "tmp camp"')
    mq.delay(500)
    mq.cmd('/circle on 200')
    mq.cmd('/circle loc -646.06 -936.68')
    mq.delay(2000)
end

local function on_tantor_rock(line, target)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    local tgt = (target or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%p%s]+$', '')
    if tgt ~= me then return end
    mq.cmd('/dgt [LUA] Ducking for stone.')
    mq.cmd('/mqp on')
    mq.cmd('/rdpause on')
    mq.delay(100)
    
    -- Set flag to indicate this character is ducking
    isDuckingFromRock = true
    
    if not mq.TLO.Me.State.Equal("DUCK")() then
        mq.cmd('/keypress DUCK')
    end
end

local function on_tantor_rock_miss(line)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    
    -- Only process if THIS character was the one ducking
    if not isDuckingFromRock then return end
    
    mq.cmd('/dgt [LUA] Stone missed re-engaging')
    
    if mq.TLO.Me.State.Equal("DUCK")() then
        mq.cmd('/keypress DUCK')
    end
    mq.delay(100)
    mq.cmd('/rdpause off')
    mq.cmd('/mqp off')
    
    -- Reset the flag
    isDuckingFromRock = false
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
    mq.cmd('/nav recordwaypoint tmpcamp "tmp camp"')
    mq.delay(1000)
    mq.cmd('/nav locxyz 3170 -730 -64')
    while mq.TLO.Navigation.Active() do
        mq.delay(250)
    end
    mq.delay(500)
    mq.cmd('/nav waypoint tmpcamp')
    while mq.TLO.Navigation.Active() do
        mq.delay(250)
    end
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
    local guardianSearch = mq.TLO.SpawnCount('npc "a primal guardian" radius 1000')
    if guardianSearch and guardianSearch() > 0 then
        for i = 1, guardianSearch() do
            local guardian = mq.TLO.NearestSpawn(string.format('%d,npc "a primal guardian" radius 1000', i))
            if guardian and guardian.ID() and guardian.ID() > 0 then
                local spawnID = guardian.ID()
                local spawnName = guardian.Name() or "Unknown"
                local hpPercent = guardian.PctHPs() or 0
                ImGui.Text(string.format("%s [ID:%d] %d%%", spawnName, spawnID, hpPercent))
                ImGui.SameLine()
                if ImGui.Button(string.format("Target##guardian%d", spawnID)) then
                    mq.cmdf('/target %s', spawnName)
                end
                guardianFound = true
            end
        end
    end
    if not guardianFound then
        ImGui.Text("No Primal Guardians up")
    end
    local tantorlingFound = false
    local tantorlingSearch = mq.TLO.SpawnCount('npc "a tantorling" radius 1000')
    if tantorlingSearch and tantorlingSearch() > 0 then
        for i = 1, tantorlingSearch() do
            local tantorling = mq.TLO.NearestSpawn(string.format('%d,npc "a tantorling" radius 1000', i))
            if tantorling and tantorling.ID() and tantorling.ID() > 0 then
                local spawnID = tantorling.ID()
                local spawnName = tantorling.Name() or "Unknown"
                local hpPercent = tantorling.PctHPs() or 0
                ImGui.Text(string.format("%s [ID:%d] %d%%", spawnName, spawnID, hpPercent))
                ImGui.SameLine()
                if ImGui.Button(string.format("Target##tantorling%d", spawnID)) then
                    mq.cmdf('/target %s', spawnName)
                end
                tantorlingFound = true
            end
        end
    end
    if not tantorlingFound then
        ImGui.Text("No Tantorlings up")
    end
    
    -- Setup instructions
    ImGui.Separator()
    ImGui.TextWrapped("Setup: set MT for permatanking Tantor. set ST for autopickup a_primal_guardian00 and activate auto")
    
    ImGui.End()
end

print('covtantor.lua loaded')
mq.imgui.init('TantorHP', drawGUI)

local lastAntiFeign = 0
while guiOpen do
    mq.doevents()
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
