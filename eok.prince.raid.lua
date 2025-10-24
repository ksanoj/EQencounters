local mq = require('mq')

-- EoK Prince Event Torch Lighter Script
-- Decodes ghostly voice emotes and runs to appropriate torch locations
-- Author: Noobjuice 

local script_name = "EoK Prince Torch Lighter"
local running = true
local openGUI = true
local shouldDrawGUI = true

local cipher_numbers = {0, 0, 0}  -- The 3 numbers that change each raid
local last_emote = ""
local decoded_locations = {}
local waiting_for_return = false  -- Flag to track if we should return after torch success

local torch_locations = {
    ["Upper"] = {
        ["North"] = {
            ["Red"] = {x = -710.07, y = -329.41, z = -273.07},
            ["Blue"] = {x = -710.56, y = -3.95, z = -273.07}
        },
        ["South"] = {
            ["Blue"] = {x = -1056.29, y = -333.56, z = -273.07},
            ["Green"] = {x = -1063.57, y = -14.47, z = -273.07}
        },
        ["East"] = {
            ["Red"] = {x = -921.56, y = -290.34, z = -273.07},
            ["Blue"] = {x = -843.92, y = -289.23, z = -273.07}
        },
        ["West"] = {
            ["Green"] = {x = -902.78, y = -13.90, z = -273.07},
            ["Red"] = {x = -863.67, y = -17.89, z = -273.07}
        }
    },
    ["Lower"] = {
        ["North"] = {
            ["Red"] = {x = -804.16, y = -248.61, z = -302.93},
            ["Blue"] = {x = -798.55, y = -104.59, z = -302.93}
        },
        ["South"] = {
            ["Green"] = {x = -969.88, y = -106.15, z = -302.93},
            ["Blue"] = {x = -969.33, y = -240.89, z = -302.93}
        }
    }
}

local cipher_input_string = ""
local status_text = "Waiting for cipher numbers..."

local function parse_emote(emote_text)
    local words = {}
    
    local quoted_text = emote_text:match("a ghostly voice shouts, '([^']+)'")
    
    if not quoted_text then
        quoted_text = emote_text:match("'([^']+)'[^']*$")
    end
    
    if not quoted_text then
        print("Error: Could not extract quoted text from: " .. emote_text)
        return {}
    end
    
    print("Extracted quoted text: " .. quoted_text)
    
    for word in quoted_text:gmatch("([^,]+)") do
        local trimmed = word:match("^%s*(.-)%s*$")
        trimmed = trimmed:gsub("[%.%!%?%,%:%;]+", "")
        if trimmed and trimmed ~= "" then
            table.insert(words, trimmed)
        end
    end
    
    print("Parsed " .. #words .. " words: " .. table.concat(words, ", "))
    return words
end

local function decode_emote(words)
    if #words < 8 or cipher_numbers[1] == 0 or cipher_numbers[2] == 0 or cipher_numbers[3] == 0 then
        print("Decode failed: words=" .. #words .. ", cipher=[" .. 
              cipher_numbers[1] .. "," .. cipher_numbers[2] .. "," .. cipher_numbers[3] .. "]")
        return nil
    end
    
    if cipher_numbers[1] > #words or cipher_numbers[2] > #words or cipher_numbers[3] > #words then
        print("Decode failed: cipher numbers exceed word count")
        print("Words available: " .. #words .. ", Max cipher: " .. math.max(cipher_numbers[1], cipher_numbers[2], cipher_numbers[3]))
        return nil
    end
    
    print("Decoding with cipher: " .. cipher_numbers[1] .. ", " .. cipher_numbers[2] .. ", " .. cipher_numbers[3])
    print("Using words at positions: " .. cipher_numbers[1] .. ", " .. cipher_numbers[2] .. ", " .. cipher_numbers[3])
    print("Word " .. cipher_numbers[1] .. ": " .. (words[cipher_numbers[1]] or "nil"))
    print("Word " .. cipher_numbers[2] .. ": " .. (words[cipher_numbers[2]] or "nil"))
    print("Word " .. cipher_numbers[3] .. ": " .. (words[cipher_numbers[3]] or "nil"))
    
    local decoded = {
        words[cipher_numbers[1]],
        words[cipher_numbers[2]], 
        words[cipher_numbers[3]]
    }
    
    return decoded
end

local function navigate_to_location(level, direction, color)
    if not torch_locations[level] or not torch_locations[level][direction] or not torch_locations[level][direction][color] then
        print("Error: Invalid location - " .. level .. " " .. direction .. " " .. color)
        return false
    end
    
    local loc = torch_locations[level][direction][color]
    print(string.format("Navigating to %s %s %s: %.2f, %.2f, %.2f", level, direction, color, loc.x, loc.y, loc.z))
    
    mq.cmdf("/nav loc %.2f %.2f %.2f", loc.x, loc.y, loc.z)
    
    return true
end

local function use_torch()
    mq.delay(1000)  -- Wait a second after arriving
    print("Using Alchemist's Torch")
    mq.cmd("/useitem \"Alchemist's Torch\"")
    waiting_for_return = true  -- Set flag to wait for success emote
end

local function has_torch()
    local torch = mq.TLO.FindItem("Alchemist's Torch")
    return torch() ~= nil
end

local function process_locations(locations)
    if not locations or #locations ~= 3 then
        print("Error: Invalid decoded locations")
        return
    end
    
    if not has_torch() then
        print("Alchemist's Torch not found - skipping this emote")
        mq.cmd("/dgt I do not have a torch, skipping this emote")
        status_text = "Skipped: No torch found"
        return
    end
    
    print("Decoded locations: " .. table.concat(locations, ", "))
    
    local level = nil
    local color = nil
    local direction = nil
    
    for i, word in ipairs(locations) do
        if word == "Upper" or word == "Lower" then
            level = word
        elseif word == "Blue" or word == "Red" or word == "Green" then
            color = word
        elseif word == "North" or word == "South" or word == "East" or word == "West" then
            direction = word
        end
    end
    
    if not level or not color or not direction then
        print("Error: Missing required information")
        print(string.format("Level: %s, Color: %s, Direction: %s", 
            level or "MISSING", color or "MISSING", direction or "MISSING"))
        status_text = "Error: Incomplete decode"
        return
    end
    
    local decoded_output = string.format("%s - %s - %s", level, color, direction)
    print("Decoded: " .. decoded_output)
    
    local nav_level = level
    local nav_direction = direction
    if navigate_to_location(nav_level, nav_direction, color) then
        print("Waiting for navigation to complete...")
        local timeout = 0
        while mq.TLO.Navigation.Active() and timeout < 60 do  -- 60 second timeout
            mq.delay(500)
            timeout = timeout + 0.5
        end
        
        if timeout >= 60 then
            print("Warning: Navigation timeout reached")
            status_text = string.format("Warning: Navigation timeout for %s", decoded_output)
        else
            print("Navigation complete, using torch")
        end
        
        use_torch()
        status_text = string.format("Completed: %s", decoded_output)
    else
        status_text = string.format("Error: Failed to navigate to %s", decoded_output)
    end
end

local function handle_torch_success(line, ...)
    local player_name = mq.TLO.Me.Name()
    local success_pattern = player_name .. " lights the key brazier, illuminating the entire library!"
    
    if line:find(success_pattern, 1, true) then  -- true for plain text search
        print("Torch lighting successful! Returning to saved position...")
        waiting_for_return = false
        
        mq.cmd("/nav wp tmpwp")
        
        local timeout = 0
        while mq.TLO.Navigation.Active() and timeout < 60 do
            mq.delay(500)
            timeout = timeout + 0.5
        end
        
        if timeout >= 60 then
            print("Warning: Return navigation timeout reached")
            status_text = "Warning: Return navigation timeout"
        else
            print("Successfully returned to original position")
            status_text = "Returned to original position"
        end
    end
end

local function handle_ghostly_voice(line, ...)
    if line:find("Ghostly voice detected:") or line:find("Parsed words:") or line:find("Decoded:") then
        return
    end
    
    print("Ghostly voice detected: " .. line)
    last_emote = line
    
    print("Recording current position as waypoint 'tmpwp'")
    mq.cmd("/nav rwp tmpwp")
    mq.delay(500)  -- Small delay to ensure waypoint is saved
    
    local words = parse_emote(line)
    if #words >= 8 then  -- Changed from 9 to 8 as some emotes might have 8 words
        print("Parsed words: " .. table.concat(words, ", "))
        
        local decoded = decode_emote(words)
        if decoded then
            decoded_locations = decoded
            process_locations(decoded)
        else
            print("Error: Could not decode emote. Check cipher numbers.")
            status_text = "Error: Could not decode emote"
        end
    else
        print("Error: Could not parse emote properly (found " .. #words .. " words, need at least 8)")
        status_text = "Error: Could not parse emote"
    end
end

local function drawGUI()
    if not openGUI then 
        return 
    end
    
    openGUI, shouldDrawGUI = ImGui.Begin(script_name, openGUI, ImGuiWindowFlags.None)
    
    if shouldDrawGUI then
        ImGui.Text("EoK Prince Event - Torch Lighter")
        ImGui.Separator()
        
        ImGui.Text("Enter 3 cipher numbers (e.g., 249):")
        cipher_input_string = ImGui.InputText("##cipher", cipher_input_string, ImGuiInputTextFlags.None)
        
        if #cipher_input_string == 3 then
            for i = 1, 3 do
                local digit = cipher_input_string:sub(i, i)
                local num = tonumber(digit)
                if num and num >= 1 and num <= 9 then
                    cipher_numbers[i] = num
                else
                    cipher_numbers[i] = 0
                end
            end
        else
            cipher_numbers = {0, 0, 0}
        end
        
        ImGui.Separator()
        
        local cipher_display = ""
        if cipher_numbers[1] > 0 and cipher_numbers[2] > 0 and cipher_numbers[3] > 0 then
            cipher_display = string.format("Current cipher: %d, %d, %d", 
                cipher_numbers[1], cipher_numbers[2], cipher_numbers[3])
        else
            cipher_display = "Current cipher: Invalid (need 3 digits 1-9)"
        end
        ImGui.Text(cipher_display)
        
        ImGui.Text("Status: " .. status_text)
        
        if last_emote ~= "" then
            ImGui.Separator()
            ImGui.Text("Last emote:")
            ImGui.TextWrapped(last_emote)
            
            if #decoded_locations > 0 then
                local level, color, direction = nil, nil, nil
                for i, word in ipairs(decoded_locations) do
                    if word == "Upper" or word == "Lower" then
                        level = word
                    elseif word == "Blue" or word == "Red" or word == "Green" then
                        color = word
                    elseif word == "North" or word == "South" or word == "East" or word == "West" then
                        direction = word
                    end
                end
                
                if level and color and direction then
                    ImGui.Text(string.format("Decoded: %s - %s - %s", level, color, direction))
                else
                    ImGui.Text("Raw decoded: " .. table.concat(decoded_locations, ", "))
                    ImGui.Text("Missing: " .. (level and "" or "Level ") .. 
                              (color and "" or "Color ") .. (direction and "" or "Direction"))
                end
            end
        end
        
        ImGui.Separator()
        
        if ImGui.Button("Test Current Emote") then
            if last_emote ~= "" then
                handle_ghostly_voice(last_emote)
            else
                status_text = "No emote to test"
            end
        end
        
        ImGui.SameLine()
        
        if ImGui.Button("Clear") then
            last_emote = ""
            decoded_locations = {}
            cipher_input_string = ""
            cipher_numbers = {0, 0, 0}
            status_text = "Cleared"
        end
    end
    
    ImGui.End()
end

local function main_loop()
    mq.imgui.init('eokprince', drawGUI)
    
    while running and openGUI do
        mq.delay(50)
        
        mq.doevents()
    end
end

mq.event('ghostly_voice', "#*#a ghostly voice shouts, '#1#'", handle_ghostly_voice)
mq.event('torch_success', "#*# lights the key brazier, illuminating the entire library!", handle_torch_success)

print("EoK Prince Torch Lighter script loaded")
print("Usage: Enter the 3 cipher numbers in the GUI")
print("The script will automatically decode ghostly voice emotes and navigate to torch locations")

main_loop()
