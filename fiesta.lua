--[[
Fiesta: Random starting weapons

LICENCE: GNU GPL3
]]

api_version = "1.12.0.0"

local weapon_paths = {}


function OnScriptLoad()
    register_callback(cb['EVENT_GAME_START'], "OnGameStart")
    register_callback(cb['EVENT_SPAWN'], "OnPlayerSpawn")
    if (get_var(0, '$gt') ~= "") then
        -- Game has already started
        OnGameStart()
    end
end


function OnScriptUnload() end


function OnGameStart()
    weapon_paths = {}
    for path, _ in pairs(get_map_weapons()) do
        weapon_paths[#weapon_paths+1] = path
    end
end


function OnPlayerSpawn(player_index)
    -- Don't do anything if there are 2 or less weapons
    if #weapon_paths < 2 then return end

    execute_command("wdel " .. player_index)
    
    -- Pick 2 random weapons
    weapon_tag_idx = rand(1, #weapon_paths)
    assign_weapon(spawn_object("weap", weapon_paths[weapon_tag_idx]), player_index)
    
    -- Only try to get a second weapon 50 times in case the server is super unlucky
    for i=1,50 do
        local new_weapon_tag_idx = rand(1, #weapon_paths)
        if new_weapon_tag_idx ~= weapon_tag_idx then
            assign_weapon(spawn_object("weap", weapon_paths[new_weapon_tag_idx]), player_index)
            break
        end
    end
end


-- Decode an integer to an ascii string
function decode_ascii(value)
    local r, i = {}, 1
    while value > 0 do
        r[i] = string.char(value%256)
        i = i + 1
        value = math.floor(value/256)
    end
    return string.reverse(table.concat(r))
end


--Convenience function for iterating over an array of data
function iter_array(base, count, size)
    local i = -1
    return function()
        i = i + 1
        if i <= count - 1 then return base + i * size end
    end
end


-- Get weapons that are enabled on the current map
function get_map_weapons()
    r = {}
    
    local map_base = 0x40440000
    local tag_base = read_dword(map_base)
    local tag_count = read_dword(map_base + 0xC)
    local tag_size = 0x20
    
    local get_tag_address = function(tag_id)
        local tag_index = bit.band(tag_id, 0xFFFF)
        if tag_index >= tag_count then return nil end
        return tag_base + tag_index * tag_size
    end
    
    local valid_weapon = function(tag)
        local tag_type = decode_ascii(read_dword(tag))
        local data = read_dword(tag + 0x14)
        if tag_type ~= "weap" then return false end
        
        -- check if an actual weapon (ball, flags, etc)
        local weapon_flags = read_dword(data + 0x308)
        if bit.band(weapon_flags, math.pow(2,3)) > 0 then return false end
        if read_word(data + 0x45C) == 0xFFFF then return false end
        
        return true
    end
    
    local add_itmc_weaps = function(tag_id)
        local tag = get_tag_address(tag_id)
        if tag == nil then return end
        
        local tag_data = read_dword(tag + 0x14)
        local equip_count = read_dword(tag_data)
        local equip_base = read_dword(tag_data + 0x4)
        for equip in iter_array(equip_base, equip_count, 0x54) do
            local equip_address = equip + 0x24
            local equip_tag_id = read_dword(equip_address + 0xC)
            local equip_tag = get_tag_address(equip_tag_id)
            if valid_weapon(equip_tag) then
                -- Found a valid weapon in the collection, add it to the result
                local equip_path = read_string(read_dword(equip_tag + 0x10))
                r[equip_path] = true
            end
        end
    end

    for tag in iter_array(tag_base, tag_count, tag_size) do
        local tag_type = decode_ascii(read_dword(tag))
        local tag_data = read_dword(tag + 0x14)
        
        -- Pull the item collections out of the scenario data
        if tag_type == "scnr" then
            local netgame_equipment_count = read_dword(tag_data + 0x384)
            local netgame_equipment_address = read_dword(tag_data + 0x384 + 0x4)
            for itmc in iter_array(netgame_equipment_address, netgame_equipment_count, 0x90) do
                local itmc_tag_address = itmc + 0x50
                local itmc_tag_id = read_dword(itmc_tag_address + 0xC)
                add_itmc_weaps(itmc_tag_id)
            end
            
            local starting_equipment_count = read_dword(tag_data + 0x390)
            local starting_equipment_address = read_dword(tag_data + 0x390 + 0x4)
            for starting in iter_array(starting_equipment_address, starting_equipment_count, 0xCC) do
                for itmc in iter_array(starting, 6, 0x10) do
                    local itmc_tag_address = itmc + 0x3C
                    local itmc_tag_id = read_dword(itmc_tag_address + 0xC)
                    add_itmc_weaps(itmc_tag_id)
                end
            end
        end
    end
    return r
end