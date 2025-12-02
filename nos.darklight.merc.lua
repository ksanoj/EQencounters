--[[
    NoS Merc Quest Helper
    
    Grabs the three merc quests in Darklight Caverns:
    - The Strength of a Wolf (Shae)
    - The Bravery of a Bear (Valia)
    - The Cunning of a Tiger (Yasil)
    
    Usage: /lua run nosmerc
    Click "Get Quests" button to start
]]

local mq = require('mq')
local ImGui = require('ImGui')
local Actors = require('actors')

local mailboxName = "NoSMerc"
local actor
local itemCounts = {}
local myName = mq.TLO.Me.CleanName()

local function registerActor()
    actor = Actors.register(mailboxName, function(message)
        if not message() then return end
        local received = message()
        local sender = received.Sender
        local braveryCount = received.BraveryCount
        local cunningCount = received.CunningCount
        local strengthCount = received.StrengthCount
        local hasValia = received.HasValia
        
        if sender then
            if not itemCounts[sender] then
                itemCounts[sender] = {}
            end
            itemCounts[sender].bravery = braveryCount or 0
            itemCounts[sender].cunning = cunningCount or 0
            itemCounts[sender].strength = strengthCount or 0
            itemCounts[sender].hasValia = hasValia or false
        end
    end)
end

local function checkAndBroadcastItems()
    local braveryCount = mq.TLO.FindItemCount("Freed Spirit of Bravery")() or 0
    local cunningCount = mq.TLO.FindItemCount("Freed Spirit of Cunning")() or 0
    local strengthCount = mq.TLO.FindItemCount("Freed Spirit of Strength")() or 0
    local hasValia = mq.TLO.FindItemCount("Valia's Unyielding Bravery")() > 0
    
    if not itemCounts[myName] then
        itemCounts[myName] = {}
    end
    itemCounts[myName].bravery = braveryCount
    itemCounts[myName].cunning = cunningCount
    itemCounts[myName].strength = strengthCount
    itemCounts[myName].hasValia = hasValia
    
    if actor then
        actor:send({ mailbox = mailboxName }, {
            Sender = myName,
            BraveryCount = braveryCount,
            CunningCount = cunningCount,
            StrengthCount = strengthCount,
            HasValia = hasValia
        })
    end
end

local state = {
    isRunning = true,
    questActive = false,
    currentStep = "",
    showWindow = true,
    logMessages = {},
    groupMode = false,
    visibleChars = {},
    turnInType = nil,
    startQuest = false,
}

local function log(msg)
    local timestamp = os.date("%H:%M:%S")
    local logMsg = string.format("[%s] %s", timestamp, msg)
    print("[NoSMerc] " .. msg)
    table.insert(state.logMessages, logMsg)
    if #state.logMessages > 20 then
        table.remove(state.logMessages, 1)
    end
end

local function updateStep(step)
    state.currentStep = step
    log(step)
end

local function turnInBear()
    local zoneName = mq.TLO.Zone.ShortName()
    if zoneName ~= "darklightcaverns" then
        log(string.format("ERROR: Must be in Darklight Caverns (currently in %s)", zoneName))
        state.currentStep = "Error: Wrong zone"
        return
    end
    
    while mq.TLO.FindItemCount("Freed Spirit of Bravery")() >= 3 do
        local currentCount = mq.TLO.FindItemCount("Freed Spirit of Bravery")()
        log(string.format("Turning in Bear spirits (have %d)", currentCount))
        
        mq.cmdf("/target Valia, the Great Bear Spirit")
        mq.delay(500)
        
        local targetDist = mq.TLO.Target.Distance() or 999
        if targetDist > 10 then
            log(string.format("Distance %.1f - navigating to Valia", targetDist))
            mq.cmdf("/nav spawn \"Valia, the Great Bear Spirit\"")
            
            local navTimeout = 240000
            local startTime = os.clock() * 1000
            while mq.TLO.Navigation.Active() do
                mq.delay(100)
                if (os.clock() * 1000 - startTime) > navTimeout then
                    log("ERROR: Navigation timeout")
                    state.questActive = false
                    return
                end
            end
            
            mq.delay(500)
        else
            log(string.format("Distance %.1f - already in range", targetDist))
        end
        
        mq.cmdf("/shift /itemnotify \"Freed Spirit of Bravery\" leftmouseup")
        mq.delay(500)
        mq.cmdf("/click left target")
        mq.delay(100)
        mq.cmdf("/click left target")
        mq.delay(1000)
        
        mq.cmdf("/notify GiveWnd GVW_Give_Button leftmouseup")
        mq.delay(3000)
        
        while mq.TLO.Window("GiveWnd").Open() do
            mq.delay(100)
        end
        
        mq.delay(1000)
        
        log("Re-requesting Bear quest...")
        mq.cmdf("/say spirit")
        mq.delay(2000)
        
        checkAndBroadcastItems()
    end
    
    state.questActive = false
    updateStep("Bear turn-ins complete!")
    log("=== BEAR TURN-IN FINISHED ===")
end

local function turnInTiger()
    local zoneName = mq.TLO.Zone.ShortName()
    if zoneName ~= "darklightcaverns" then
        log(string.format("ERROR: Must be in Darklight Caverns (currently in %s)", zoneName))
        state.currentStep = "Error: Wrong zone"
        return
    end
    
    while mq.TLO.FindItemCount("Freed Spirit of Cunning")() >= 3 do
        local currentCount = mq.TLO.FindItemCount("Freed Spirit of Cunning")()
        log(string.format("Turning in Tiger spirits (have %d)", currentCount))
        
        mq.cmdf("/target Yasil, the Great Tiger Spirit")
        mq.delay(500)
        
        local targetDist = mq.TLO.Target.Distance() or 999
        if targetDist > 10 then
            log(string.format("Distance %.1f - navigating to Yasil", targetDist))
            mq.cmdf("/nav spawn \"Yasil, the Great Tiger Spirit\"")
            
            local navTimeout = 240000
            local startTime = os.clock() * 1000
            while mq.TLO.Navigation.Active() do
                mq.delay(100)
                if (os.clock() * 1000 - startTime) > navTimeout then
                    log("ERROR: Navigation timeout")
                    state.questActive = false
                    return
                end
            end
            
            mq.delay(500)
        else
            log(string.format("Distance %.1f - already in range", targetDist))
        end
        
        mq.cmdf("/shift /itemnotify \"Freed Spirit of Cunning\" leftmouseup")
        mq.delay(500)
        mq.cmdf("/click left target")
        mq.delay(100)
        mq.cmdf("/click left target")
        mq.delay(1000)
        
        mq.cmdf("/notify GiveWnd GVW_Give_Button leftmouseup")
        mq.delay(3000)
        
        while mq.TLO.Window("GiveWnd").Open() do
            mq.delay(100)
        end
        
        mq.delay(1000)
        
        log("Re-requesting Tiger quest...")
        mq.cmdf("/say destroy")
        mq.delay(2000)
        
        checkAndBroadcastItems()
    end
    
    state.questActive = false
    updateStep("Tiger turn-ins complete!")
    log("=== TIGER TURN-IN FINISHED ===")
end

local function turnInWolf()
    local zoneName = mq.TLO.Zone.ShortName()
    if zoneName ~= "darklightcaverns" then
        log(string.format("ERROR: Must be in Darklight Caverns (currently in %s)", zoneName))
        state.currentStep = "Error: Wrong zone"
        return
    end
    
    while mq.TLO.FindItemCount("Freed Spirit of Strength")() >= 3 do
        local currentCount = mq.TLO.FindItemCount("Freed Spirit of Strength")()
        log(string.format("Turning in Wolf spirits (have %d)", currentCount))
        
        mq.cmdf("/target Shae, the Great Wolf Spirit")
        mq.delay(500)
        
        local targetDist = mq.TLO.Target.Distance() or 999
        if targetDist > 10 then
            log(string.format("Distance %.1f - navigating to Shae", targetDist))
            mq.cmdf("/nav spawn \"Shae, the Great Wolf Spirit\"")
            
            local navTimeout = 240000
            local startTime = os.clock() * 1000
            while mq.TLO.Navigation.Active() do
                mq.delay(100)
                if (os.clock() * 1000 - startTime) > navTimeout then
                    log("ERROR: Navigation timeout")
                    state.questActive = false
                    return
                end
            end
            
            mq.delay(500)
        else
            log(string.format("Distance %.1f - already in range", targetDist))
        end
        
        mq.cmdf("/shift /itemnotify \"Freed Spirit of Strength\" leftmouseup")
        mq.delay(500)
        mq.cmdf("/click left target")
        mq.delay(100)
        mq.cmdf("/click left target")
        mq.delay(1000)
        
        mq.cmdf("/notify GiveWnd GVW_Give_Button leftmouseup")
        mq.delay(3000)
        
        while mq.TLO.Window("GiveWnd").Open() do
            mq.delay(100)
        end
        
        mq.delay(1000)
        
        log("Re-requesting Wolf quest...")
        mq.cmdf("/say return")
        mq.delay(2000)
        
        checkAndBroadcastItems()
    end
    
    state.questActive = false
    updateStep("Wolf turn-ins complete!")
    log("=== WOLF TURN-IN FINISHED ===")
end

local function startTurnInBear()
    if state.questActive then
        log("Already running a quest/turn-in")
        return
    end
    
    state.questActive = true
    state.turnInType = 'bear'
    updateStep("Starting Bear turn-ins...")
end

local function startTurnInTiger()
    if state.questActive then
        log("Already running a quest/turn-in")
        return
    end
    
    state.questActive = true
    state.turnInType = 'tiger'
    updateStep("Starting Tiger turn-ins...")
end

local function startTurnInWolf()
    if state.questActive then
        log("Already running a quest/turn-in")
        return
    end
    
    state.questActive = true
    state.turnInType = 'wolf'
    updateStep("Starting Wolf turn-ins...")
end

local function talkToNPC(npcName, keyword, questName)
    updateStep(string.format("Grabbing Quest: %s", questName))
    
    -- Target the NPC
    updateStep(string.format("Targeting %s...", npcName))
    local targetCmd = string.format('/target "%s"', npcName)
    if state.groupMode then
        mq.cmdf('/dgz %s', targetCmd)
    else
        mq.cmd(targetCmd)
    end
    mq.delay(2000, function() return mq.TLO.Target() and mq.TLO.Target.CleanName() == npcName end)
    
    if not mq.TLO.Target() or mq.TLO.Target.CleanName() ~= npcName then
        log(string.format("ERROR: Could not target %s", npcName))
        return false
    end
    
    -- Navigate to the NPC
    updateStep(string.format("Navigating to %s...", npcName))
    local navCmd = string.format('/nav spawn "%s"', npcName)
    if state.groupMode then
        mq.cmdf('/dgz %s', navCmd)
    else
        mq.cmd(navCmd)
    end
    
    -- Wait for navigation to complete (max 4 minutes)
    local startTime = os.clock()
    while mq.TLO.Navigation.Active() do
        mq.delay(100)
        if (os.clock() - startTime) > 240 then
            log("ERROR: Navigation timeout")
            return false
        end
    end
    
    -- Say the keyword
    updateStep(string.format("Saying '%s' to %s...", keyword, npcName))
    local sayCmd = string.format('/say %s', keyword)
    if state.groupMode then
        mq.cmdf('/dgz %s', sayCmd)
    else
        mq.cmd(sayCmd)
    end
    mq.delay(2000)
    
    log(string.format("Completed: %s", questName))
    return true
end

-- Main quest sequence
local function runQuestSequence()
    state.questActive = true
    updateStep("Starting quest sequence...")
    
    -- Check if we're in Darklight Caverns
    local zoneName = mq.TLO.Zone.ShortName()
    if zoneName ~= "darklightcaverns" then
        log(string.format("ERROR: Must be in Darklight Caverns (currently in %s)", zoneName))
        state.questActive = false
        state.currentStep = "Error: Wrong zone"
        return
    end
    
    log("In Darklight Caverns - starting quest grabs")
    
    -- Quest 1: The Strength of a Wolf
    if not talkToNPC("Shae, the Great Wolf Spirit", "return", "The Strength of a Wolf") then
        state.questActive = false
        state.currentStep = "Error: Failed at Shae"
        return
    end
    
    mq.delay(2000)
    
    -- Quest 2: The Bravery of a Bear
    if not talkToNPC("Valia, the Great Bear Spirit", "spirit", "The Bravery of a Bear") then
        state.questActive = false
        state.currentStep = "Error: Failed at Valia"
        return
    end
    
    mq.delay(2000)
    
    -- Quest 3: The Cunning of a Tiger
    if not talkToNPC("Yasil, the Great Tiger Spirit", "destroy", "The Cunning of a Tiger") then
        state.questActive = false
        state.currentStep = "Error: Failed at Yasil"
        return
    end
    
    -- Complete
    state.questActive = false
    updateStep("All quests grabbed! COMPLETE")
    log("=== QUEST SEQUENCE FINISHED ===")
end

local function renderUI()
    if not state.showWindow then
        state.isRunning = false
        return
    end
    
    state.showWindow, _ = ImGui.Begin("NoS Merc Quest Helper", state.showWindow, ImGuiWindowFlags.AlwaysAutoResize)
    
    if state.showWindow then
        -- Header
        ImGui.Text("NoS Merc Quest Helper")
        ImGui.Text("Zone: Darklight Caverns")
        ImGui.Separator()
        
        -- Group mode checkbox
        local groupModeChanged, newGroupMode = ImGui.Checkbox("Group Mode (use /dgz)", state.groupMode)
        if groupModeChanged then
            state.groupMode = newGroupMode
            if state.groupMode then
                log("Group Mode ENABLED - Commands will use /dgz")
            else
                log("Group Mode DISABLED - Commands are local only")
            end
        end
        ImGui.Separator()
        
        -- Quest info
        ImGui.TextColored(0.7, 0.7, 1, 1, "Grabs 3 merc quests:")
        
        ImGui.Text("  1. The Strength of a Wolf (Strength)")
        ImGui.SameLine()
        local strengthCount = mq.TLO.FindItemCount("Freed Spirit of Strength")() or 0
        if strengthCount < 3 then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 1)
            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1)
            ImGui.Button("Turn-in##wolf", 80, 20)
            ImGui.PopStyleColor(2)
        elseif not state.questActive then
            if ImGui.Button("Turn-in##wolf", 80, 20) then
                log("Wolf Turn-in button clicked")
                startTurnInWolf()
            end
        else
            ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.2, 1)
            ImGui.Button("RUNNING##wolf", 80, 20)
            ImGui.PopStyleColor()
        end
        
        ImGui.Text("  2. The Bravery of a Bear (Bravery)")
        ImGui.SameLine()
        local braveryCount = mq.TLO.FindItemCount("Freed Spirit of Bravery")() or 0
        if braveryCount < 3 then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 1)
            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1)
            ImGui.Button("Turn-in##bear", 80, 20)
            ImGui.PopStyleColor(2)
        elseif not state.questActive then
            if ImGui.Button("Turn-in##bear", 80, 20) then
                log("Bear Turn-in button clicked")
                startTurnInBear()
            end
        else
            ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.2, 1)
            ImGui.Button("RUNNING##bear", 80, 20)
            ImGui.PopStyleColor()
        end
        
        ImGui.Text("  3. The Cunning of a Tiger (Cunning)")
        ImGui.SameLine()
        local cunningCount = mq.TLO.FindItemCount("Freed Spirit of Cunning")() or 0
        if cunningCount < 3 then
            ImGui.PushStyleColor(ImGuiCol.Button, 0.3, 0.3, 0.3, 1)
            ImGui.PushStyleColor(ImGuiCol.Text, 0.5, 0.5, 0.5, 1)
            ImGui.Button("Turn-in##tiger", 80, 20)
            ImGui.PopStyleColor(2)
        elseif not state.questActive then
            if ImGui.Button("Turn-in##tiger", 80, 20) then
                log("Tiger Turn-in button clicked")
                startTurnInTiger()
            end
        else
            ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.2, 1)
            ImGui.Button("RUNNING##tiger", 80, 20)
            ImGui.PopStyleColor()
        end
        
        ImGui.Separator()
        
        -- Get Quests button
        if not state.questActive then
            if ImGui.Button("Get Quests", 200, 40) then
                log("Get Quests button clicked")
                state.startQuest = true
            end
        else
            ImGui.PushStyleColor(ImGuiCol.Button, 0.8, 0.5, 0.2, 1)
            ImGui.Button("RUNNING...", 200, 40)
            ImGui.PopStyleColor()
        end
        
        ImGui.Separator()
        
        -- Item Count Display
        ImGui.Text("Freed Spirit Inventory - Group:")
        ImGui.BeginChild("ItemCounts", 450, 150, true)
        
        local hasItems = false
        for char, _ in pairs(itemCounts) do
            hasItems = true
            break
        end
        
        if hasItems then
            if ImGui.BeginTable("SpiritTable", 6, ImGuiTableFlags.Borders) then
                ImGui.TableSetupColumn("Show", ImGuiTableColumnFlags.WidthFixed, 40)
                ImGui.TableSetupColumn("Character")
                ImGui.TableSetupColumn("Bravery")
                ImGui.TableSetupColumn("Cunning")
                ImGui.TableSetupColumn("Strength")
                ImGui.TableSetupColumn("Need")
                ImGui.TableHeadersRow()
                
                for char, counts in pairs(itemCounts) do
                    if state.visibleChars[char] == nil then
                        state.visibleChars[char] = true
                    end
                    
                    ImGui.TableNextRow()
                    ImGui.TableSetColumnIndex(0)
                    local visibleChanged, newVisible = ImGui.Checkbox("##show_" .. char, state.visibleChars[char])
                    if visibleChanged then
                        state.visibleChars[char] = newVisible
                    end
                    
                    if counts.hasValia then
                        ImGui.TableSetColumnIndex(1)
                        ImGui.Text(char)
                        ImGui.TableSetColumnIndex(2)
                        ImGui.Text("")
                        ImGui.TableSetColumnIndex(3)
                        ImGui.Text("")
                        ImGui.TableSetColumnIndex(4)
                        ImGui.Text("")
                        ImGui.TableSetColumnIndex(5)
                        ImGui.TextColored(ImVec4(0.4, 1, 0.4, 1), "Has Valia's")
                    else
                        local bravery = counts.bravery or 0
                        local cunning = counts.cunning or 0
                        local strength = counts.strength or 0
                        local total = bravery + cunning + strength
                        local remaining = 135 - total
                        local braveryColor = bravery > 0 and ImVec4(0.4, 1, 0.4, 1) or ImVec4(0.7, 0.7, 0.7, 1)
                        local cunningColor = cunning > 0 and ImVec4(0.4, 1, 0.4, 1) or ImVec4(0.7, 0.7, 0.7, 1)
                        local strengthColor = strength > 0 and ImVec4(0.4, 1, 0.4, 1) or ImVec4(0.7, 0.7, 0.7, 1)
                        local needColor = remaining <= 0 and ImVec4(0.4, 1, 0.4, 1) or ImVec4(1, 0.8, 0, 1)
                        
                        ImGui.TableSetColumnIndex(1)
                        ImGui.Text(char)
                        ImGui.TableSetColumnIndex(2)
                        ImGui.TextColored(braveryColor, tostring(bravery))
                        ImGui.TableSetColumnIndex(3)
                        ImGui.TextColored(cunningColor, tostring(cunning))
                        ImGui.TableSetColumnIndex(4)
                        ImGui.TextColored(strengthColor, tostring(strength))
                        ImGui.TableSetColumnIndex(5)
                        ImGui.TextColored(needColor, tostring(remaining))
                    end
                end
                
                ImGui.EndTable()
            end
        else
            ImGui.TextColored(0.7, 0.7, 0.7, 1, "  No data yet...")
        end
        
        ImGui.EndChild()
        ImGui.Separator()
        
        -- Current step
        ImGui.Text("Status:")
        if state.questActive then
            ImGui.TextColored(1, 0.8, 0, 1, state.currentStep)
        else
            ImGui.TextColored(0.5, 1, 0.5, 1, state.currentStep)
        end
        
        ImGui.Separator()
        
        -- Log window
        ImGui.Text("Log:")
        ImGui.BeginChild("LogWindow", 400, 200, true)
        for _, msg in ipairs(state.logMessages) do
            ImGui.TextWrapped(msg)
        end
        if ImGui.GetScrollY() >= ImGui.GetScrollMaxY() then
            ImGui.SetScrollHereY(1.0)
        end
        ImGui.EndChild()
    end
    
    ImGui.End()
end

local function main()
    log("NoS Merc Quest Helper started")
    log("Click 'Get Quests' to begin")
    
    state.currentStep = "Ready - Click 'Get Quests' to start"
    
    registerActor()
    checkAndBroadcastItems()
    
    mq.imgui.init("NoSMercQuestHelper", renderUI)
    
    local lastItemCheck = os.clock()
    while state.isRunning do
        mq.delay(100)
        mq.doevents()
        
        if state.startQuest then
            state.startQuest = false
            runQuestSequence()
        end
        
        if state.questActive and state.turnInType then
            if state.turnInType == 'bear' then
                turnInBear()
                state.turnInType = nil
            elseif state.turnInType == 'tiger' then
                turnInTiger()
                state.turnInType = nil
            elseif state.turnInType == 'wolf' then
                turnInWolf()
                state.turnInType = nil
            end
        end
        
        if os.clock() - lastItemCheck > 3 then
            checkAndBroadcastItems()
            lastItemCheck = os.clock()
        end
    end
    
    log("NoS Merc Quest Helper stopped")
end

main()
