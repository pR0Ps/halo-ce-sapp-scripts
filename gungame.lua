--[[

Gun Game: Players must work their way through the game's arsenal. First to the end wins!

NOTES:
 - Only works with the FFA slayer game type (all other modes will cause the map to skip)
 - Should be played on a map/weapon set that has all of the configured weapons available.
 - Levels will be skipped if the configured weapon can't found or given to a player.

LICENCE: GNU GPL3
]]--

-- == Configuration == --
local CONFIG = {
    default_kills_per_level = 2,
    levels = {
        --[[
        {
            weapon = <weapon tag>
            [ammo = {<loaded>, <unloaded>}/<battery>]
            [kills = <number of kills needed to progress>]
            [skip=true (players will skip the level)]
        }
        ]]
        {
            weapon = "weapons\\pistol\\pistol",
            -- max: 12, 120
            ammo = { 12, 120 }
        },
        {
            weapon = "weapons\\plasma_cannon\\plasma_cannon",
            -- max: 100 (battery)
            ammo = 100,
        },
        {
            weapon = "weapons\\shotgun\\shotgun",
            -- max: 12, 60
            ammo = { 12, 60 }
        },
        {
            weapon = "weapons\\rocket launcher\\rocket launcher",
            -- max: 2, 8
            ammo = { 2, 8 }
        },
        {
            weapon = "weapons\\sniper rifle\\sniper rifle",
            -- max: 4, 24
            ammo = { 4, 24 }
        },
        {
            weapon = "weapons\\flamethrower\\flamethrower",
            -- max: 100, 600
            ammo = { 100, 600 },
        },
        {
            weapon = "weapons\\needler\\mp_needler",
            -- max: 20, 80
            ammo = { 20, 80 }
        },
        {
            weapon = "weapons\\plasma rifle\\plasma rifle",
            -- max: 100 (battery)
            ammo = 100
        },
        {
            weapon = "weapons\\plasma pistol\\plasma pistol",
            -- max: 100 (battery)
            ammo = 100
        },
        {
            weapon = "weapons\\assault rifle\\assault rifle",
            -- max: 60, 600
            ammo = { 60, 600 }
        },
        {
            -- Make them more visible and melee-only
            weapon = "weapons\\flag\\flag",
            kills = 1
        },
    },
}

----------------- Script ------------------

api_version = "1.11.0.0"

-- Store player level, kills, weapon, last damage tag
local player_data = {}

-- Generates reference data when the game starts
-- Need to run on game start so the tags are pulled from the current map
local DATA = nil
function GenerateReferenceData()
    -- Get tags for every weapon available in the map
    local weapon_tag_data = get_weapon_tag_data()

    -- Process the data into usable sets/lists
    local damage_map = {}
    local melee_tag_ids = {}
    local weapon_tag_paths = {}
    local weapon_tag_ids = {}

    for _, weapon in ipairs(weapon_tag_data) do
        local weapon_tag_type = weapon[1]
        local weapon_tag_path = weapon[2]
        local damage_tag_paths = weapon[3]
        local weapon_tag_id = get_tag_id(weapon_tag_type, weapon_tag_path)

        weapon_tag_ids[weapon_tag_id] = true
        weapon_tag_paths[#weapon_tag_paths+1] = weapon_tag_path

        -- Uncomment this if you want a list of weapon tags the current map
        -- supports to be printed to the console
        --cprint(string.format(" - %s: %s", weapon_tag_type, weapon_tag_path))

        for _, dmg_tag_path in ipairs(damage_tag_paths) do
            local dmg_tag = lookup_tag("jpt!", dmg_tag_path)
            local dmg_tag_data = read_dword(dmg_tag + 0x14)
            local dmg_tag_id = read_dword(dmg_tag + 0xC)
            -- Damage.Category enum
            local is_melee = read_word(dmg_tag_data + 0x1C6) == 6

            if is_melee then
                melee_tag_ids[dmg_tag_id] = true
            else
                if damage_map[dmg_tag_id] == nil then
                    damage_map[dmg_tag_id] = {}
                end
                damage_map[dmg_tag_id][weapon_tag_path] = true
            end
        end
    end

    DATA = {
        -- A list of weapon tags
        -- Used to disable picking up weapons
        weapon_tag_paths = weapon_tag_paths,

        -- A set of weapon tag ids
        -- Used to the spawning of weapons
        weapon_tag_ids = weapon_tag_ids,

        -- A set of damage tag ids that are considered melee damage
        melee_tag_ids = melee_tag_ids,

        -- Maps damage tag ids to a list of weapon(s) that cause them
        -- Used for verifying playes use the correct weapons
        damage_map = damage_map,

        -- Map damage tags to damage multipliers
        damage_multipliers = tagmap("jpt!", {
            -- 1 hit KO for ball and flag
            ["weapons\\ball\\melee"] = 4,
            ["weapons\\flag\\melee"] = 4,
        })
    }
end


function OnScriptLoad()
    register_callback(cb["EVENT_GAME_START"], "OnGameStart")
    register_callback(cb["EVENT_GAME_END"], "OnGameEnd")

    if (get_var(0, '$gt') ~= "") then
        -- Game has already started
        OnGameStart()
    end
end


function OnScriptUnload()
    OnGameEnd()
end


function OnGameStart()
    -- Setup data
    GenerateReferenceData()

    -- Refuse to work with non-FFA slayer games
    if get_var(0, "$gt") ~= "slayer" or get_var(0, "$ffa") ~= "1" then
        cprint("ERROR: Cannot play gun game mode on a non-FFA slayer mode - skipping map", 4)
        execute_command("sv_map_next")
        return
    end

    register_callback(cb["EVENT_JOIN"], "OnPlayerJoin")
    register_callback(cb["EVENT_SPAWN"], "OnPlayerSpawn")
    register_callback(cb["EVENT_LEAVE"], "OnPlayerLeave")
    register_callback(cb['EVENT_DIE'], 'OnPlayerDie')
    register_callback(cb['EVENT_DAMAGE_APPLICATION'], "OnDamageApplication")
    register_callback(cb['EVENT_WEAPON_DROP'], "OnWeaponDrop")
    register_callback(cb['EVENT_OBJECT_SPAWN'], "OnObjectSpawn")

    -- Disable vehicles, weapons, and grenades
    execute_command("disable_all_vehicles 0 1")
    for tag, _ in pairs(DATA.weapon_tag_paths) do
        execute_command("disable_object '" .. tag .. "'")
    end

    player_data = {}
    execute_command("scorelimit " .. #CONFIG.levels)

    -- Set up any players that have already been joined/spawned
    -- Needed if the script was loaded mid-game
    for i=1,16 do
        if player_present(i) then
            OnPlayerJoin(i)
            OnPlayerSpawn(i)
        end
    end
end

function OnObjectSpawn(player_index, tag_id, parent_id, new_obj_id, sapp_spawned)
    -- block weapons spawned by the server (unless it was from a script)
    if sapp_spawned == 0 and player_index == 0 and DATA.weapon_tag_ids[tag_id] ~= nil then
        return false
    end
end

function OnGameEnd()
    -- Re-enable everything we disabled
    execute_command("disable_all_vehicles 0 0")
    for tag, _ in pairs(DATA.weapon_tag_paths) do
        execute_command("enable_object '" .. tag .. "'")
    end

    -- Unregister callbacks
    unregister_callback(cb["EVENT_JOIN"])
    unregister_callback(cb["EVENT_SPAWN"])
    unregister_callback(cb["EVENT_LEAVE"])
    unregister_callback(cb['EVENT_DIE'])
    unregister_callback(cb['EVENT_DAMAGE_APPLICATION'])
    unregister_callback(cb['EVENT_WEAPON_DROP'])
    unregister_callback(cb['EVENT_OBJECT_SPAWN'])
end


function OnPlayerJoin(player_index)
    player_data[player_index] = {
        level = 1,
        kills = 0,
        weapon_obj = nil,
        last_dmg_tag = nil
    }
end


function OnPlayerSpawn(player_index)
    player_data[player_index].kills = 0
    player_data[player_index].last_dmg_tag = nil

    equip_player(player_index)
    set_score(player_index)
end


function OnPlayerLeave(player_index)
    player_data[player_index] = nil
end


-- Attempt to assign the correct weapon to the player
-- Returns false if the player could not accept the weapon
function assign_weapon_for_level(player_index, level)
    local weapon_tag = CONFIG.levels[level].weapon
    local weapon_obj = spawn_object("weap", weapon_tag)

    -- Try to assign the weapon
    if assign_weapon(weapon_obj, player_index) then
        player_data[player_index].weapon_obj = weapon_obj

        -- Give ammo for weapon
        local weapon_ammo = CONFIG.levels[level].ammo
        if weapon_ammo ~= nil then
            if type(weapon_ammo) ~= "table" then
                weapon_ammo = {weapon_ammo}
            end
            -- Race condition: need to wait 1s before changing ammo or it doesn't take
            execute_command_sequence("w8 1;mag " .. player_index .. " " .. weapon_ammo[1])
            execute_command_sequence("w8 1;battery " .. player_index .. " " .. weapon_ammo[1])
            if #weapon_ammo > 1 then
                execute_command_sequence("w8 1;ammo " .. player_index .. " " .. weapon_ammo[2])
            end
        end
        return true
    end

    -- The player cannot accept the weapon
    -- This can happen if the map doesn't support the weapon
    -- Destroy the spawned weapon and return false
    destroy_object(weapon_obj)
    return false
end


-- If the player has a weapon then remove and delete the object
function remove_weapon(player_index)
    execute_command("wdel " .. player_index)

    local weapon_obj = player_data[player_index].weapon_obj
    if weapon_obj ~= nil then
        destroy_object(weapon_obj)
        player_data[player_index].weapon_obj = nil
    end
end


-- Give the player the correct equipment for their current level
-- Called when they spawn or move up a level
function equip_player(player_index)
    local player = get_dynamic_player(player_index)
    if player == 0 then return end

    -- Remove grenades and weapon
    write_word(player + 0x31E, 0)
    write_word(player + 0x31F, 0)
    remove_weapon(player_index)

    -- Give player the correct weapon
    local level = player_data[player_index].level
    if level > #CONFIG.levels then
        -- They've won - no need for a weapon
        -- (game should be ending at this point due to the scorelimit)
        return
    elseif not assign_weapon_for_level(player_index, level) then
        -- Disable the level and force a re-equip on the new level
        cprint("ERROR: Can't assign the level " .. level .. " weapon to player " .. player_index .. " - removing level", 4)
        CONFIG.levels[level].skip = true
        change_level(player_index, 0, true)
    end
end


-- Get the level to use, skipping all the levels with skip=true
function get_level(current, amount)

    local unit = 1
    if amount < 0 then
        unit = -1
    end

    local result = current + amount
    while CONFIG.levels[result] ~= nil and CONFIG.levels[result].skip do
        result = result + unit
    end
    if result == 0 then
        -- Happens when the first level is skipped - search forward
        return get_level(result, 1)
    end
    return result
end


-- Changes the level of the player and optionaly equips them
function change_level(player_index, amount, equip)
    local level = player_data[player_index].level
    local new_level = get_level(level, amount)

    player_data[player_index].level = new_level
    player_data[player_index].kills = 0

    if equip then
        equip_player(player_index)
    end
end


-- Give a kill to a player and handle incrementing their level if needed
function add_kill(player_index)
    local kills = player_data[player_index].kills + 1
    local level = player_data[player_index].level
    local kills_needed = CONFIG.levels[level].kills or CONFIG.default_kills_per_level

    if kills >= kills_needed then
        change_level(player_index, 1, true)
    else
        player_data[player_index].kills = kills
    end
end


-- Sets a players score based on their current level
function set_score(player_index)
    local score = player_data[player_index].level - 1
    execute_command("score " .. player_index .. " " .. score)
end


-- Store the tag of the weapon that did the damage and apply any multipliers
function OnDamageApplication(player_index, causer_index, damage_tag_id, damage, ...)
    if causer_index < 1 or player_index == causer_index then return end

    player_data[player_index].last_dmg_tag = damage_tag_id

    -- Apply any damage multipliers
    local dmg_multiplier = DATA.damage_multipliers[damage_tag_id]
    if dmg_multiplier ~= nil then
        return true, damage * dmg_multiplier
    end

    return true
end


function OnPlayerDie(player_index, killer_index)

    -- Stops the weapon the player was carrying from dropping on the ground
    remove_weapon(player_index)

    killer_index = tonumber(killer_index)

    -- -1 = falling/unknown, 0 = vehicle or AI
    if killer_index < 1 then return end

    if killer_index == player_index then
        -- Suicide - player levels down
        change_level(player_index, -1)
        return
    end

    -- Check the type of damage that killed the player
    local last_dmg = player_data[player_index].last_dmg_tag
    if DATA.melee_tag_ids[last_dmg] ~= nil then
        -- Melee kill - victim level down
        change_level(player_index, -1)
        add_kill(killer_index)
    else
        -- Verify the correct weapon was used
        -- The prevents multi-kills from skipping levels
        local possible_weapons_used = DATA.damage_map[last_dmg]
        if possible_weapons_used == nil then
            cprint("WARNING: Unknown weapon caused damage - script needs fixing", 4)
        elseif possible_weapons_used[CONFIG.levels[player_data[killer_index].level].weapon] ~= nil then
            -- Note the kill for the killer
            add_kill(killer_index)
        end
    end
    set_score(killer_index)
end


function OnWeaponDrop(player_index)
    -- Give it back (this is so the player can't throw the oddball/flag away)
    local weapon_obj = player_data[player_index].weapon_obj
    if weapon_obj ~= nil then
        assign_weapon(weapon_obj, player_index)
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
            table.insert(r, v)
        end
    end

    if type == "weap" then
        -- Player Melee Damage
        recurse_tag(tag_data + 0x394)

        -- Trigger actions (a struct of size 0x114)
        local trigger_count = read_dword(tag_data + 0x4FC)
        local trigger_base = read_dword(tag_data + 0x4FC + 0x4)
        for i=0, trigger_count - 1 do
            recurse_tag(trigger_base + i * 0x114 + 0x94)
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
        -- Events (a struct of size 0x44)
        local event_count = read_dword(tag_data + 0x34)
        local event_base = read_dword(tag_data + 0x34 + 0x4)
        for i=0, event_count - 1 do
            local event = event_base + i * 0x44

            -- Event parts (a struct of size 0x68)
            local part_count = read_dword(event + 0x2C)
            local part_base = read_dword(event + 0x2C + 0x4)
            for j=0, part_count - 1 do
                -- Event part type
                recurse_tag(part_base + j * 0x68 + 0x18)
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


-- Pull out all weapons and eqipment whos tag starts with "weapons\" 
-- For each tag return a list of:
-- {<tag type>, <tag path>, {<damage effect(s) this can cause>}}
function get_weapon_tag_data()
    local r = {}
    local map_base = 0x40440000
    local tag_base = read_dword(map_base)
    local tag_count = read_dword(map_base + 0xC)

    for i=0, tag_count - 1 do
        local tag = tag_base + i * 0x20
        local tag_type = decode_ascii(read_dword(tag))
        local tag_path = read_string(read_dword(tag + 0x10))
        if (tag_type == "weap" or tag_type == "eqip") and string.find(tag_path, '^weapons\\') ~= nil then
            r[#r+1] = {tag_type, tag_path, get_damage_tags(tag_type, tag_path)}
        end
    end
    return r
end


-- Get the id of a tag given its type and path
function get_tag_id(tag_type, tag_path)
    local tag = lookup_tag(tag_type, tag_path)
    if tag == 0 then return nil end
    return read_dword(tag + 0xC)
end


-- Convert tag path keys of a table to tag ids
-- Drops invalid tags
function tagmap(type, tbl)
    local r = {}
    for k, v in pairs(tbl) do
        local id = get_tag_id(type, k)
        if id ~= nil then
            r[id] = v
        end
    end
    return r
end