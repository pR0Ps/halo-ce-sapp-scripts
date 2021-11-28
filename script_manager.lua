--[[

Handle loading/unloading scripts based on the map/game modes.

WARNINGS:
 - Scripts with quotes (") in their filename will not be properly loaded
 - Loaded scripts will always be unloaded at the end of the game (even if they
   were already loaded before this manager loaded them).
 - If this script is unloaded before the end of a game then the scripts
   it loaded will not be unloaded.

LICENCE: GNU GPL3
]]--

-- == Configuration == --

-- Rules will be processed and have their scripts loaded and messages displayed
-- in the order they are defined. When unloading, scripts will be unloaded in
-- reverse from the order they were loaded.
local CONFIG = {
    --[[ Configuration format:
    {
        modes = <mode(s) to require, nil for any mode>
        maps = <map(s) to require, nil for any map>
        scripts = <script(s) to load>
        announce = <text line(s) to send to players when they join the game>
    }
    ]]
    {
        -- Always announce this when starting a game
        announce = "Skip voting enabled - type 'skip' to vote"
    },
    {
        modes = {"fiesta", "team fiesta"},
        scripts = "fiesta",
        announce = "Starting weapons are randomized!"
    },
    {
        modes = {"one in the chamber", "oitc"},
        scripts = "oneinthechamber",
        announce = {
            "Game mode: One in the Chamber",
            "You have 1 bullet. Killing an enemy gives you another."
        }
    },
    {
        modes = "Gun Game",
        maps = nil,
        scripts = "gungame",
        announce = {
            "Game mode: Gun Game",
            "Work your way through the game's arsenal!"
        }
    },
    {
        modes = {"tag n bag", "team tag n bag"},
        maps = nil,
        scripts = "teabag",
        announce = {
            "Game mode: Tag 'em and bag 'em",
            "Teabag your opponents for points!"
        }
    },
}

----------------- Script ------------------

api_version = "1.12.0.0"

local loaded_configs = {}


-- Normalize a table to either nil (nil/empty) or a list of values (1 or more values)
function makelist(tbl)
    if tbl == nil then
        return nil
    end

    -- Single value -> list
    if type(tbl) ~= "table" then
        return { tbl }
    end

    -- Empty list -> nil
    if #tbl == 0 then
        return nil
    end
    return tbl
end


-- Make a set from a table
-- Follows the same rules as making a list
function makeset(tbl)
    local lst = makelist(tbl)

    if lst == nil then
        return nil
    end

    local r = {}
    for _, x in ipairs(lst) do
        r[string.lower(x)] = true
    end
    return r
end


-- Modify CONFIG in-place to make accessing the data easier
for i=#CONFIG, 1, -1 do
    CONFIG[i].modes = makeset(CONFIG[i].modes)
    CONFIG[i].maps = makeset(CONFIG[i].maps)
    CONFIG[i].announce = makelist(CONFIG[i].announce)
    CONFIG[i].scripts = makelist(CONFIG[i].scripts)
end


function OnScriptLoad()
    register_callback(cb["EVENT_GAME_START"], "OnGameStart")
    register_callback(cb["EVENT_GAME_END"], "OnGameEnd")
    register_callback(cb["EVENT_JOIN"], "OnPlayerJoin")

    if (get_var(0, "$gt") ~= "") then
        -- Game has already started
        OnGameStart()
    end
end


function OnScriptUnload()
    -- Unloading scripts when reloading the server causes a crash :(
    --OnGameEnd()
end


function OnGameStart()
    loaded_configs = {}
    local mode = string.lower(get_var(0, "$mode"))
    local map = string.lower(get_var(0, "$map"))

    for c=1, #CONFIG do
        local conf = CONFIG[c]
        -- match map and mode
        if (conf.maps == nil or conf.maps[map] ~= nil) and (conf.modes == nil or conf.modes[mode] ~= nil) then
            -- only mark the conf loaded if there's something to do
            if conf.scripts ~= nil or conf.announce ~= nil then
                if conf.scripts ~= nil then
                    for s=1, #conf.scripts do
                        local script = conf.scripts[s]
                        cprint("[Script Manager] Loading " .. script, 3)
                        execute_command('lua_load ' .. ' "' .. script .. '"')
                    end
                end
                loaded_configs[#loaded_configs + 1] = conf
            end
        end
    end
end


-- Send announce message to the player
function OnPlayerJoin(PlayerIndex)
    for c=1, #loaded_configs do
        local conf = loaded_configs[c]
        if conf.announce ~= nil then
            for _, text in ipairs(conf.announce) do
                say(PlayerIndex, text)
            end
        end
    end
end


-- Unload scripts in reverse order
function OnGameEnd()
    for c=#loaded_configs, 1, -1 do
        local conf = loaded_configs[c]
        if conf.scripts ~= nil then
            for s=#conf.scripts, 1, -1 do
                local script = conf.scripts[s]
                cprint("[Script Manager] Unloading " .. script, 3)
                execute_command('lua_unload ' .. ' "' .. script .. '"')
            end
        end
    end
    loaded_configs = {}
end