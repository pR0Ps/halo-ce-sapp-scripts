--[[
One in the Chamber

Players start with a pistol containing a single bullet.
Each player killed gives you another bullet.

LICENCE: GNU GPL3
]]

----------------- Config ------------------

local STARTING_WEAPON = "weapons\\pistol\\pistol"
local DAMAGE_MULTIPLIER = 10
local STARTING_AMMO = 1
local AMMO_PER_KILL = 1

----------------- Script ------------------

api_version = "1.12.0.0"


local damage_ids = {}
local weapon_ids = {}

function OnScriptLoad()
    register_callback(cb['EVENT_GAME_START'], "OnGameStart")

    if (get_var(0, '$gt') ~= "") then
        -- Game has already started
        OnGameStart()
    end
end


function OnScriptUnload()
end


function OnGameStart()
    register_callback(cb['EVENT_SPAWN'], "OnPlayerSpawn")
    register_callback(cb['EVENT_DAMAGE_APPLICATION'], "OnDamageApplication")
    register_callback(cb['EVENT_DIE'], "OnPlayerDie")
    register_callback(cb['EVENT_OBJECT_SPAWN'], "OnObjectSpawn")

    -- Disable vehicles
    execute_command("disable_all_vehicles 0 1")

    -- Note damage tags to modify
    damage_ids = {}
    for _, path in pairs(get_damage_tags("weap", STARTING_WEAPON)) do
        damage_ids[get_tag_id("jpt!", path)] = true
    end

    weapon_ids = {}
    local map_base = 0x40440000
    local tag_base = read_dword(map_base)
    local tag_count = read_dword(map_base + 0xC)
    for tag in iter_array(tag_base, tag_count, 0x20) do
        local tag_type = decode_ascii(read_dword(tag))
        local tag_path = read_string(read_dword(tag + 0x10))
        local tag_data = read_dword(tag + 0x14)
        if (tag_type == "weap" or tag_type == "eqip") and string.find(tag_path, '^weapons\\') ~= nil then
            -- Disable weapons and grenades
            execute_command("disable_object '" .. tag_path .. "'")

            -- Store the ID of the weapon to prevent it from spawning
            weapon_ids[get_tag_id(tag_type, tag_path)] = true
        end
    end
end


function OnPlayerSpawn(player_index)
    local player = get_dynamic_player(player_index)
    if player == 0 then return end

    -- Start with no grenades and a pistol with 1 ammo
    write_word(player + 0x31E, 0)
    write_word(player + 0x31F, 0)

    execute_command("wdel " .. player_index)
    local weapon_obj = spawn_object("weap", STARTING_WEAPON)
    assign_weapon(weapon_obj, player_index)

    execute_command_sequence("ammo me 0 5;mag me " .. STARTING_AMMO .. " 5", player_index)
    execute_command("battery me " .. STARTING_AMMO .. " 5", player_index)
end


function OnPlayerDie(player_index, killer_index)
    killer_index = tonumber(killer_index)

    -- Stops the weapon the player was carrying from dropping on the ground
    execute_command("wdel " .. player_index)

    if killer_index < 1 or killer_index == player_index then return end

    -- Give killer ammo
    execute_command("mag me +" .. AMMO_PER_KILL .. " 5", killer_index)
    execute_command("battery me +" .. AMMO_PER_KILL .. " 5", killer_index)
end


function OnDamageApplication(player_index, causer_index, damage_tag_id, damage, collision_mat, backtap)
    if damage_ids[damage_tag_id] then
        return true, damage * DAMAGE_MULTIPLIER
    end
end


function OnObjectSpawn(player_index, tag_id, parent_id, new_obj_id, sapp_spawned)
    -- block weapons spawned by the server (unless it was from a script)
    if sapp_spawned == 0 and player_index == 0 and weapon_ids[tag_id] ~= nil then
       return false
    end
end


--Convenience function for iterating over an array of data
function iter_array(base, count, size)
    local i = -1
    return function()
        i = i + 1
        if i <= count - 1 then return base + i * size end
    end
end


--Convenience function for iterating over an array pointer.
--Assumes a dword containing the number of elements followed by
--a dword pointer to the start of the data.
function iter_array_ptr(base, size)
    local count = read_dword(base)
    local start = read_dword(base + 0x4)
    local iter = iter_array(start, count, size)
    return function()
        return iter()
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


-- Get the id of a tag given its type and path
function get_tag_id(tag_type, tag_path)
    local tag = lookup_tag(tag_type, tag_path)
    if tag == 0 then return nil end
    return read_dword(tag + 0xC)
end


-- Reads the tag type and path from an address
function resolve_reference(address)
    local type = decode_ascii(read_dword(address))
    local path_address = read_dword(address + 0x4)
    if path_address == 0 then
        return type, nil
    end
    return type, read_string(path_address)
end


-- Return any damage effects the provided tag can cause by recursively
-- exploring referenced tags and returning any "jpt!" tags
-- Only damage tags that have a non-zero damage attribute will be returned
function get_damage_tags(type, path)
    local r = {}

    if type == nil or path == nil then return r end

    local tag = lookup_tag(type, path)
    if tag == 0 then return r end

    local tag_data = read_dword(tag + 0x14)

    --helper function for recursion into referenced tags
    local recurse_tag = function(address)
        local t, p = resolve_reference(address)
        for _, v in ipairs(get_damage_tags(t, p)) do
            r[#r+1] = v
        end
    end

    if type == "weap" then
        -- Player Melee Damage
        recurse_tag(tag_data + 0x394)

        -- Trigger actions (structs of size 0x114)
        for trigger in iter_array_ptr(tag_data + 0x4FC, 0x114) do
            recurse_tag(trigger + 0x94)
        end
    elseif type == "eqip" then
        -- These are just grenades in the stock maps
        -- Creation Effect
        recurse_tag(tag_data + 0xA0)
        -- Item.Detonating Effect
        recurse_tag(tag_data + 0x2E8)
        -- Item.Detonation Effect
        recurse_tag(tag_data + 0x2F8)
    elseif type == "proj" then
        -- Projectile.Super Detonation
        recurse_tag(tag_data + 0x18C)
        -- Detonation.Effect
        recurse_tag(tag_data + 0x1AC)
        -- Physics.Detonation Started
        recurse_tag(tag_data + 0x1F4)
        -- Physics.Attached Detonation Damage
        recurse_tag(tag_data + 0x214)
        -- Physics.Impact Damage
        recurse_tag(tag_data + 0x224)
        -- Miscellaneous.Detonation Effect
        recurse_tag(tag_data + 0x68)
    elseif type == "effe" then
        -- Events (structs of size 0x44)
        for event in iter_array_ptr(tag_data + 0x34, 0x44) do
            -- Event parts (structs of size 0x68)
            for part in iter_array_ptr(event + 0x2C, 0x68) do
                -- Event part type
                recurse_tag(part + 0x18)
            end
        end
    elseif type == "jpt!" then
        -- Only return damage tags that can actually do damage
        local lethal_to_unsuspecting = read_word(tag_data + 0x1C4) == 2
        local max_damage = read_float(tag_data + 0x1D8)
        if lethal_to_unsuspecting or max_damage > 0 then
            r[#r+1] = path
        end
    end
    return r
end