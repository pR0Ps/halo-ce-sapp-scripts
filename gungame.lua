--[[

Gun Game: Players must work their way through the game's arsenal. First to the end wins!

NOTES:
 - Only works with the FFA slayer game type (all other modes will cause the map to skip)
 - Should be played with a normal weapon set so all weapons are available.

LICENCE: GNU GPL3
]]--

-- == Configuration == --
local CONFIG = {
    default_kills_per_level = 2,
    levels = {
        --[[
        {
            weapon = <weapon name (see DATA.weapon_names)>
            [ammo = {<loaded>, <unloaded>}/<battery>]
            [kills = <number of kills needed to progress>]
            [skip=true (players will skip the level)]
        }
        ]]
        {
            weapon = "pistol",
            -- max: 12, 120
            ammo = { 12, 120 }
        },
        {
            weapon = "plasma cannon",
            -- max: 100 (battery)
            ammo = 100,
        },
        {
            weapon = "shotgun",
            -- max: 12, 60
            ammo = { 12, 60 }
        },
        {
            weapon = "rocket launcher",
            -- max: 2, 8
            ammo = { 2, 8 }
        },
        {
            weapon = "sniper rifle",
            -- max: 4, 24
            ammo = { 4, 24 }
        },
        {
            weapon = "flamethrower",
            -- max: 100, 600
            ammo = { 100, 600 },
        },
        {
            weapon = "needler",
            -- max: 20, 80
            ammo = { 20, 80 }
        },
        {
            weapon = "plasma rifle",
            -- max: 100 (battery)
            ammo = 100
        },
        {
            weapon = "plasma pistol",
            -- max: 100 (battery)
            ammo = 100
        },
        {
            weapon = "assault rifle",
            -- max: 60, 600
            ammo = { 60, 600 }
        },
        {
            -- Make them more visible and melee-only
            weapon = "flag",
            kills = 1
        },
    },
}

----------------- Script ------------------

api_version = "1.11.0.0"

-- Store player level, kills, weapon, last damage tag
local player_data = {}

-- Generates reference data when the game starts
-- Need to run on game start so the tag addresses are valid
local DATA = nil
function GenerateReferenceData()
    DATA = {
        -- Weapons names used when defining levels are defined here
        -- All these tags will be disabled from the map
        weapon_names = {
            ["assault rifle"] = "weapons\\assault rifle\\assault rifle",
            ["ball"] = "weapons\\ball\\ball",
            ["flag"] = "weapons\\flag\\flag",
            ["flamethrower"] = "weapons\\flamethrower\\flamethrower",
            ["frag grenade"] = "weapons\\frag grenade\\frag grenade",
            ["needler"] = "weapons\\needler\\mp_needler",
            ["pistol"] = "weapons\\pistol\\pistol",
            ["plasma cannon"] = "weapons\\plasma_cannon\\plasma_cannon",
            ["plasma grenade"] = "weapons\\plasma grenade\\plasma grenade",
            ["plasma pistol"] = "weapons\\plasma pistol\\plasma pistol",
            ["plasma rifle"] = "weapons\\plasma rifle\\plasma rifle",
            ["rocket launcher"] = "weapons\\rocket launcher\\rocket launcher",
            ["shotgun"] = "weapons\\shotgun\\shotgun",
            ["sniper rifle"] = "weapons\\sniper rifle\\sniper rifle",
        },

        -- Map damage tags to the weapons that cause them
        damage_map = tagmap("jpt!", {
            ["weapons\\assault rifle\\bullet"] = "assault rifle",
            ["weapons\\flamethrower\\burning"] = "flamethrower",
            ["weapons\\flamethrower\\explosion"] = "flamethrower",
            ["weapons\\flamethrower\\impact damage"] = "flamethrower",
            --["weapons\\frag grenade\\explosion"] = "frag grenade",
            --["weapons\\frag grenade\\shock wave"] = "frag grenade",
            ["weapons\\needler\\detonation damage"] = "needler",
            ["weapons\\needler\\explosion"] = "needler",
            ["weapons\\needler\\impact damage"] = "needler",
            ["weapons\\needler\\shock wave"] = "needler",
            ["weapons\\pistol\\bullet"] = "pistol",
            --["weapons\\plasma grenade\\attached"] = "plasma grenade",
            --["weapons\\plasma grenade\\explosion"] = "plasma grenade",
            --["weapons\\plasma grenade\\shock wave"] = "plasma grenade",
            ["weapons\\plasma pistol\\bolt"] = "plasma pistol",
            ["weapons\\plasma rifle\\bolt"] = "plasma rifle",
            ["weapons\\plasma rifle\\charged bolt"] = "plasma pistol", --sic
            ["weapons\\plasma_cannon\\effects\\plasma_cannon_explosion"] = "plasma cannon",
            ["weapons\\plasma_cannon\\impact damage"] = "plasma cannon",
            ["weapons\\rocket launcher\\explosion"] = "rocket launcher",
            ["weapons\\shotgun\\pellet"] = "shotgun",
            ["weapons\\sniper rifle\\sniper bullet"] = "sniper rifle",
        }),

        -- These damage tags are considered melee damage
        melee_tags = tagset("jpt!", {
            "weapons\\assault rifle\\melee",
            "weapons\\ball\\melee",
            "weapons\\flag\\melee",
            "weapons\\flamethrower\\melee",
            "weapons\\needler\\melee",
            "weapons\\pistol\\melee",
            "weapons\\plasma pistol\\melee",
            "weapons\\plasma rifle\\melee",
            "weapons\\plasma_cannon\\effects\\plasma_cannon_melee",
            "weapons\\rocket launcher\\melee",
            "weapons\\shotgun\\melee",
            "weapons\\sniper rifle\\melee",
        }),

        -- Map damage tag to multipliers
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

    -- Disable vehicles, weapons, and grenades
    execute_command("disable_all_vehicles 0 1")
    for _, tag in pairs(DATA.weapon_names) do
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


function OnGameEnd()
    -- Re-enable everything we disabled
    execute_command("disable_all_vehicles 0 0")
    for _, tag in pairs(DATA.weapon_names) do
        execute_command("enable_object '" .. tag .. "'")
    end

    -- Unregister callbacks
    unregister_callback(cb["EVENT_JOIN"])
    unregister_callback(cb["EVENT_SPAWN"])
    unregister_callback(cb["EVENT_LEAVE"])
    unregister_callback(cb['EVENT_DIE'])
    unregister_callback(cb['EVENT_DAMAGE_APPLICATION'])
    unregister_callback(cb['EVENT_WEAPON_DROP'])
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
    local weapon_name = CONFIG.levels[level].weapon
    local weapon_obj = spawn_object("weap", DATA.weapon_names[weapon_name])

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

    set_score(player_index)
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
    if DATA.melee_tags[last_dmg] ~= nil then
        -- Melee kill - victim level down
        change_level(player_index, -1)
        return
    end

    -- Verify the correct weapon was used
    -- The prevents multi-kills from skipping levels
    local weapon_used = DATA.damage_map[last_dmg]
    if weapon_used == nil then
        cprint("WARNING: Unknown weapon caused damage - script needs updating", 4)
    elseif CONFIG.levels[player_data[killer_index].level].weapon == weapon_used then
        -- Note the kill for the killer
        add_kill(killer_index)
    end
end


function OnWeaponDrop(player_index)
    -- Give it back (this is so the player can't throw the oddball/flag away)
    local weapon_obj = player_data[player_index].weapon_obj
    if weapon_obj ~= nil then
        assign_weapon(weapon_obj, player_index)
    end
end


-- Get the id of a tag given it's class and name
function get_tag_id(tagclass, tagname)
    local tag = lookup_tag(tagclass, tagname)
    if tag == nil then return nil end
    return read_dword(tag + 0xC)
end


-- Utility functions for making maps/sets of tag ids for easy lookups
function tagset(cls, tbl)
    local r = {}
    for _, d in ipairs(tbl) do
        r[get_tag_id(cls, d)] = true
    end
    return r
end
function tagmap(cls, tbl)
    local r = {}
    for k, v in pairs(tbl) do
        r[get_tag_id(cls, k)] = v
    end
    return r
end