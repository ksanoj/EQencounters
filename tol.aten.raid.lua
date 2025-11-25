local mq = require('mq')
local ImGui = require('ImGui')

local ZONE_NAME = 'vexthaltwo_raid'
local guiOpen = true
local isSilenced = false
local isReturningFromSilence = false

local function on_aten_ha_ra_silence(line, target)
    if (mq.TLO.Zone.ShortName() or '') ~= ZONE_NAME then return end
    local me = mq.TLO.Me.DisplayName() or ''
    local tgt = (target or ''):gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%p%s]+$', '')
    if tgt ~= me then return end
    
    if not isSilenced and not isReturningFromSilence then
        isSilenced = true
        print('[Aten Ha Ra] Targeted for silence - running to safe spot!')
        mq.cmd('/mqp on')
        mq.cmd('/rdpause on')
        mq.delay(100)
        mq.cmd('/nav recordwaypoint tmpcamp "tmp camp"')
        mq.delay(500)
        mq.cmd('/dgt got silenced moving')
        mq.cmd('/nav loc 4.66 1133.83 233.55')
    end
end

mq.event('ATEN_HA_RA_SILENCE', "#*#Aten Ha Ra points at #1# with one arm, while holding a finger to her lips.#*#", on_aten_ha_ra_silence)

local function drawGUI()
    local currentZone = mq.TLO.Zone.ShortName() or ''
    if currentZone ~= ZONE_NAME then return end
    if not guiOpen then return end
    local show
    guiOpen, show = ImGui.Begin("Aten Ha Ra HP", guiOpen, bit32.bor(ImGuiWindowFlags.AlwaysAutoResize, ImGuiWindowFlags.NoTitleBar))
    if not show then
        ImGui.End()
        return
    end
    local atenhara = mq.TLO.Spawn('#Aten_Ha_Ra00')
    if atenhara and atenhara.ID() and atenhara.ID() > 0 then
        local hpPercent = atenhara.PctHPs() or 0
        ImGui.Text(string.format("Aten Ha Ra: %d%%", hpPercent))
        
        if hpPercent > 93 then
            ImGui.Text("Adds will Spawn at 93%")
        elseif hpPercent > 56 then
            ImGui.Text("Adds will Spawn at 85%")
        elseif hpPercent > 39 then
            ImGui.Text("Adds will Spawn at 39%")
        elseif hpPercent > 24 then
            ImGui.Text("Adds will Spawn at 24%")
        end
    else
        ImGui.Text("Aten Ha Ra: Not Found")
    end
    
    -- Pli_liakao tracking (00-06)
    local pliFound = false
    for pliNum = 0, 6 do
        local pliName = string.format("Pli_liako%02d", pliNum)
        local pliSpawn = mq.TLO.Spawn(string.format('npc "%s" radius 250', pliName))
        if pliSpawn and pliSpawn.ID() and pliSpawn.ID() > 0 then
            local spawnID = pliSpawn.ID()
            local spawnName = pliSpawn.Name() or "Unknown"
            local hpPercent = pliSpawn.PctHPs() or 0
            local distance = pliSpawn.Distance() or 0
            ImGui.Text(string.format("%s [ID:%d] %d%% (%.0f)", spawnName, spawnID, hpPercent, distance))
            ImGui.SameLine()
            if ImGui.Button(string.format("Target##pli%d", spawnID)) then
                mq.cmdf('/target id %d', spawnID)
            end
            pliFound = true
        end
    end
    if not pliFound then
        ImGui.Text("No Pli_liakao spawns up (within 250 range)")
    end
    
    -- Setup instructions
    ImGui.Separator()
    ImGui.TextWrapped("Setup:")
    ImGui.Text("3 Pli Liako will engage when saying begin to AHR")
    
    -- Show setup buttons only if xtar is empty, not in combat, and boss is at 100%
    local xtarCount = mq.TLO.Me.XTarget() or 0
    local inCombat = mq.TLO.Me.CombatState() == "COMBAT"
    local atenHaRa = mq.TLO.Spawn('#Aten_Ha_Ra00')
    local bossAt100 = atenHaRa and atenHaRa.ID() and atenHaRa.ID() > 0 and atenHaRa.PctHPs() == 100
    
    if xtarCount == 0 and not inCombat and bossAt100 then
        if ImGui.Button("Move to Start") then
            mq.cmd('/dgz /nav loc 0.22 1374.20 231')
        end
        
        if ImGui.Button("Rmark 3") then
            mq.cmdf('/target id %d', atenHaRa.ID())
            mq.doevents()
            mq.cmdf('/timed 10 /rmark 3')
        end
    end
    
    ImGui.End()
end

print('tolaten.lua loaded')
mq.imgui.init('AtenHaRaHP', drawGUI)

local lastAntiFeign = 0
local lastBuffCheck = 0
while guiOpen do
    mq.doevents()
    local now = os.time()
    
    -- Check for Silence of Shadows buff to trigger return
    if (os.clock() * 1000) > lastBuffCheck + 500 then
        if isSilenced and not isReturningFromSilence then
            local silenceBuff = mq.TLO.Me.Buff('Silence of Shadows')
            if silenceBuff and silenceBuff.ID() and silenceBuff.ID() > 0 then
                -- We now have the silence debuff, return to fight
                isSilenced = false
                isReturningFromSilence = true
                print('[Aten Ha Ra] Silence of Shadows applied - returning to fight!')
                mq.cmd('/dgt returning to fight')
                mq.cmd('/nav waypoint tmpcamp')
                -- Wait for navigation to complete
                while mq.TLO.Navigation.Active() do
                    mq.delay(100)
                end
                mq.cmd('/mqp off')
                mq.cmd('/rdpause off')
                isReturningFromSilence = false
                print('[Aten Ha Ra] Returned to fight position')
            end
        end
        
        lastBuffCheck = os.clock() * 1000
    end
    
    if now > lastAntiFeign then
        if mq.TLO.Me.Feigning() and mq.TLO.Me.Class.ShortName() ~= 'MNK' then
            mq.cmd('/stand')
            mq.delay(100)
        end
        lastAntiFeign = now
    end
    mq.delay(50)
end

print('tolaten.lua stopped')
