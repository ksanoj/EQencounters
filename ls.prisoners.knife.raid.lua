--[[
    LS Prisoner Knife - Emote listener
    Listens for Brigadier Navulta knife emote and moves to furthest safe location.
--]]

local mq = require('mq')
local ImGui = require('ImGui')

local guiOpen = true

local knifePhase = nil
local knifePreEndMs = 0
local knifePostEndMs = 0
local knifeTargetLoc = nil

local SAFE_LOCS = {
    {x = 1163.40, y = 1652.63, z = 438.52},
    {x = 1068.64, y = 1714.43, z = 438.52},
    {x = 995.20, y = 1631.82, z = 438.52},
    {x = 1094.34, y = 1570.35, z = 438.52},
}

local function calculateDistance(x1, y1, z1, x2, y2, z2)
    local dx = x2 - x1
    local dy = y2 - y1
    local dz = z2 - z1
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function findFurthestSafeLoc()
    local myX = mq.TLO.Me.X() or 0
    local myY = mq.TLO.Me.Y() or 0
    local myZ = mq.TLO.Me.Z() or 0

    local furthest = nil
    local maxDistance = -1

    for _, loc in ipairs(SAFE_LOCS) do
        local distance = calculateDistance(myX, myY, myZ, loc.x, loc.y, loc.z)
        if distance > maxDistance then
            maxDistance = distance
            furthest = loc
        end
    end

    return furthest
end

local function onBrigadierKnives(line)
    -- Only react if Brigadier_Navulta00 is within 65 range
    local nav = mq.TLO.Spawn('npc "Brigadier_Navulta00"')
    if not nav or not nav.ID() or nav.ID() == 0 then return end
    local dist = nav.Distance() or 999
    if dist > 65 then return end

    mq.cmd('/nav recordwaypoint tmpcamp "tmp camp"')
    knifeTargetLoc = findFurthestSafeLoc()
    knifePhase = 'pre'
    knifePreEndMs = mq.gettime() + 6000
end

mq.event('ls_prisonerknife_brigadier_knives', '#*#Brigadier Navulta magically twirls several knives in the air#*#', onBrigadierKnives)

local function drawGUI()
    if not guiOpen then return end

    local open
    guiOpen, open = ImGui.Begin('LS Prisoner Knife', guiOpen, ImGuiWindowFlags.AlwaysAutoResize)
    if not open then
        ImGui.End()
        return
    end

    if knifePhase == 'pre' then
        local remainingMs = knifePreEndMs - mq.gettime()
        local remainingSec = math.ceil(remainingMs / 1000)
        if remainingSec < 0 then remainingSec = 0 end
        ImGui.Text(string.format('Knives: moving in %ds', remainingSec))
    elseif knifePhase == 'post' then
        local remainingMs = knifePostEndMs - mq.gettime()
        local remainingSec = math.ceil(remainingMs / 1000)
        if remainingSec < 0 then remainingSec = 0 end
        ImGui.Text(string.format('Knives: returning in %ds', remainingSec))
    else
        ImGui.Text('Waiting for Brigadier Navulta knives emote...')
    end

    ImGui.End()
end

print('[LS Prisoner Knife] Listening for Brigadier Navulta knives emote...')
mq.imgui.init('LS_PrisonerKnife_GUI', drawGUI)

while true do
    mq.doevents()

    if knifePhase == 'pre' and mq.gettime() >= knifePreEndMs then
        if knifeTargetLoc then
            mq.cmd('/rdpause on')
            mq.cmd('/mqp on')
            mq.cmd('/target ${Me.CleanName}')
            mq.cmdf('/nav loc %f %f %f', knifeTargetLoc.y, knifeTargetLoc.x, knifeTargetLoc.z)
            knifePhase = 'moving'
        else
            knifePhase = nil
        end
    elseif knifePhase == 'moving' then

        local myName = mq.TLO.Me.CleanName() or ""
        local targetName = mq.TLO.Target.CleanName() or ""
        if targetName ~= myName then
            mq.cmd('/target ${Me.CleanName}')
        end

        -- Check: is nav active, or are we already far enough from Navulta?
        local navActive = mq.TLO.Navigation.Active() or false
        local nav = mq.TLO.Spawn('npc "Brigadier_Navulta00"')
        local navDist = 999
        if nav and nav.ID() and nav.ID() > 0 then
            navDist = nav.Distance() or 999
        end

        if not navActive and navDist <= 65 then
            -- Nav stopped but still too close — retry
            if knifeTargetLoc then
                mq.cmdf('/nav loc %f %f %f', knifeTargetLoc.y, knifeTargetLoc.x, knifeTargetLoc.z)
            end
        elseif not navActive and navDist > 65 then

            knifePhase = 'post'
            knifePostEndMs = mq.gettime() + 8000
        end
    elseif knifePhase == 'post' and mq.gettime() >= knifePostEndMs then
        mq.cmd('/nav waypoint tmpcamp')
        mq.cmd('/rdpause off')
        mq.cmd('/mqp off')
        knifePhase = nil
        knifeTargetLoc = nil
    end

    mq.delay(50)
end
