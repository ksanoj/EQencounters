local mq = require('mq')
local ImGui = require('ImGui')

local ZONE_NAME = 'darklightcaverns_raid'
local guiOpen = true

-- State variables for event tracking
local eventState = {
    -- Add your event-specific state variables here
    -- Example:
    -- isActive = false,
    -- warningSeen = false,
    -- timers = {},
}

-- Event handler template - customize as needed
local function on_event_example(line)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    -- Add event handling logic here
    print('[NosSpirit] Event detected: ' .. (line or ''))
end

-- Register events here - customize patterns and handlers as needed
-- Example:
-- mq.event('NOSSPIRIT_EVENT1', "#*#event pattern here#*#", on_event_example)

local function drawGUI()
    local currentZone = mq.TLO.Zone.ShortName() or ''
    if currentZone ~= ZONE_NAME then return end
    if not guiOpen then return end
    
    local show
    guiOpen, show = ImGui.Begin("Nos Spirit Tracker", guiOpen, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar))
    if not show then
        ImGui.End()
        return
    end
    
    -- Check which bosses are alive to determine phase
    local depletion = mq.TLO.Spawn('#Demonstrated_Depletion00')
    local boss = mq.TLO.Spawn('#Weakness_Evinced00')
    local lethargy = mq.TLO.Spawn('#Manifest_Lethargy00')
    
    local depletionAlive = depletion and depletion.ID() and depletion.ID() > 0
    local bossAlive = boss and boss.ID() and boss.ID() > 0
    local lethargyAlive = lethargy and lethargy.ID() and lethargy.ID() > 0
    
    -- ===== PHASE 1: DEMONSTRATED DEPLETION =====
    if depletionAlive then
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 0.5, 0, 1))  -- Orange
        ImGui.Text("=== PHASE 1: LEECH ===")
        ImGui.PopStyleColor()
        ImGui.Separator()
        
        local hpPercent = depletion.PctHPs() or 0
        local spawnID = depletion.ID()
        local spawnName = depletion.Name() or "Unknown"
        ImGui.Text(string.format("%s [ID:%d] %d%%", spawnName, spawnID, hpPercent))
        ImGui.SameLine()
        if ImGui.Button("Target##depletion") then
            mq.cmdf('/target id %d', spawnID)
        end
        
        -- Check for Seething_Energy00
        local seethingEnergy = mq.TLO.Spawn('Seething_Energy00')
        if seethingEnergy and seethingEnergy.ID() and seethingEnergy.ID() > 0 then
            local distance = seethingEnergy.Distance() or 999
            if distance <= 70 then
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 1, 0, 1))  -- Yellow
                ImGui.Text("Energies within explosion range")
                ImGui.PopStyleColor()
            else
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 1, 1, 1))  -- White
                ImGui.Text("Seething Energies are active")
                ImGui.PopStyleColor()
            end
        end
    
    -- ===== PHASE 2: WEAKNESS EVINCED =====
    elseif bossAlive then
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.5, 0.5, 1, 1))  -- Light Blue
        ImGui.Text("=== PHASE 2: WEAKNESS EVINCED ===")
        ImGui.PopStyleColor()
        ImGui.Separator()
        
        local hpPercent = boss.PctHPs() or 0
        ImGui.Text(string.format("Weakness Evinced: %d%%", hpPercent))
        
        -- Location navigation buttons
        if ImGui.Button("Ledge") then
            mq.cmd('/dgz /nav loc 685 -846 202')
        end
        ImGui.SameLine()
        if ImGui.Button("Center") then
            mq.cmd('/dgz /nav loc 850 -887 175')
        end
        
        -- Check for Gathered_power00
        local gatheredPower = mq.TLO.Spawn('Gathered_power00')
        if gatheredPower and gatheredPower.ID() and gatheredPower.ID() > 0 then
            local distance = gatheredPower.Distance() or 999
            if distance <= 100 then
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 1, 0, 1))  -- Yellow
                ImGui.Text("Aura in Range MOVE!")
                ImGui.PopStyleColor()
            else
                ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 1, 1, 1))  -- White
                ImGui.Text("Aura active")
                ImGui.PopStyleColor()
            end
        end
        
        -- HP milestone indicators
        if hpPercent > 75 then
            ImGui.Text("Phase 1")
        elseif hpPercent > 50 then
            ImGui.Text("Phase 2")
        elseif hpPercent > 25 then
            ImGui.Text("Phase 3")
        else
            ImGui.Text("Final Phase")
        end
    
    -- ===== PHASE 3: MANIFEST LETHARGY =====
    elseif lethargyAlive then
        ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(0.5, 1, 0.5, 1))  -- Light Green
        ImGui.Text("=== PHASE 3: LETHARGY ===")
        ImGui.PopStyleColor()
        ImGui.Separator()
        
        local hpPercent = lethargy.PctHPs() or 0
        local spawnID = lethargy.ID()
        local spawnName = lethargy.Name() or "Unknown"
        ImGui.Text(string.format("%s [ID:%d] %d%%", spawnName, spawnID, hpPercent))
        ImGui.SameLine()
        if ImGui.Button("Target##lethargy") then
            mq.cmdf('/target id %d', spawnID)
        end
    
    -- ===== NO BOSSES UP =====
    else
        ImGui.Text("Demonstrated Depletion: Not Found")
        ImGui.Text("Weakness Evinced: Not Found")
        ImGui.Text("Manifest Lethargy: Not Found")
        
        -- Check if only Grakaw is up when no bosses are detected
        local grakaw = mq.TLO.Spawn('#Grakaw')
        if grakaw and grakaw.ID() and grakaw.ID() > 0 then
            ImGui.Separator()
            ImGui.PushStyleColor(ImGuiCol.Text, ImVec4(1, 1, 0, 1))  -- Yellow
            ImGui.Text("Only Grakaw Up")
            ImGui.PopStyleColor()
        end
    end
    
    ImGui.Separator()
    
    -- Add tracking section - customize NPC names as needed
    -- Example add tracking:
    -- local addFound = false
    -- local addSearch = mq.TLO.SpawnCount('npc "add_name" radius 1000')
    -- if addSearch and addSearch() > 0 then
    --     for i = 1, addSearch() do
    --         local add = mq.TLO.NearestSpawn(string.format('%d,npc "add_name" radius 1000', i))
    --         if add and add.ID() and add.ID() > 0 then
    --             local spawnID = add.ID()
    --             local spawnName = add.Name() or "Unknown"
    --             local hpPercent = add.PctHPs() or 0
    --             ImGui.Text(string.format("%s [ID:%d] %d%%", spawnName, spawnID, hpPercent))
    --             ImGui.SameLine()
    --             if ImGui.Button(string.format("Target##add%d", spawnID)) then
    --                 mq.cmdf('/target id %d', spawnID)
    --             end
    --             addFound = true
    --         end
    --     end
    -- end
    -- if not addFound then
    --     ImGui.Text("No adds up")
    -- end
    
    -- Setup instructions
    ImGui.Separator()
    ImGui.TextWrapped("Setup:")
    
    -- Cubby Setup button - only visible if no corpse within 200 and no NPC targeted
    local showGrakawButton = true
    
    -- Check for corpse within 200 radius
    local corpseCount = mq.TLO.SpawnCount('corpse radius 200')
    if corpseCount and corpseCount() > 0 then
        showGrakawButton = false
    end
    
    -- Check if current target is an NPC
    local target = mq.TLO.Target
    if target and target.ID() and target.ID() > 0 and target.Type() == "NPC" then
        showGrakawButton = false
    end
    
    if showGrakawButton then
        if ImGui.Button("Cubby Setup") then
            mq.cmd('/dgz /nav loc 684 -832 201')
        end
    end
    
    ImGui.End()
end

print('nosspirit.lua loaded for zone: ' .. ZONE_NAME)
mq.imgui.init('NosSpiritTracker', drawGUI)

local lastAntiFeign = 0
local lastCheck = 0

while guiOpen do
    mq.doevents()
    local now = os.time()
    local clockMs = os.clock() * 1000
    
    -- Periodic checks (every 500ms)
    if clockMs > lastCheck + 500 then
        -- Add periodic check logic here
        -- Example: check for specific buffs, proximity warnings, etc.
        
        -- Example boss buff check:
        -- local boss = mq.TLO.Spawn('=boss_name')
        -- if boss and boss.ID() and boss.ID() > 0 then
        --     local specificBuff = boss.Buff('Buff Name')
        --     if specificBuff and specificBuff.ID() then
        --         -- Buff is active
        --         if not eventState.buffActive then
        --             eventState.buffActive = true
        --             print('[NosSpirit] Boss buff detected!')
        --         end
        --     else
        --         -- Buff is not active
        --         if eventState.buffActive then
        --             eventState.buffActive = false
        --             print('[NosSpirit] Boss buff dropped!')
        --         end
        --     end
        -- end
        
        lastCheck = clockMs
    end
    
    -- Anti-feign check (prevent accidental feigning)
    if now > lastAntiFeign then
        if mq.TLO.Me.Feigning() and mq.TLO.Me.Class.ShortName() ~= 'MNK' then
            mq.cmd('/stand')
            mq.delay(100)
        end
        lastAntiFeign = now
    end
    
    mq.delay(50)
end

print('nosspirit.lua stopped')
