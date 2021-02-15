--[[

Teabag detection/game mode script

Depending on the configuration, can be used multiple ways

Ex 1: "Tag 'em and bag 'em" game mode (you must teabag your victims to score points)
 - TEABAG_STEALING = true (allow "claiming" other people's kills)
 - TEAM_TEABAGGING = true (allow "claiming" your teammates's bodies before the enemy does) 
 - TEABAG_SCORE = 1
 - TEAM_TEABAG_SCORE = 0
 - PREVENT_SCORE_ON_KILL = true
 - Set messages to taste (at minimum should give feedback for the baggers)

Ex 2: Discourage and shame teabagging players
 - TEABAG_STEALING = true
 - TEAM_TEABAGGING = true
 - TEABAG_SCORE = -1
 - TEAM_TEABAG_SCORE = -1
 - PREVENT_SCORE_ON_KILL = false
 - TEABAG_MESSAGE = "$bagger was punished for teabagging $baggee"

Ex 3: Normal game with fun messages
 - TEABAG_STEALING = true
 - TEAM_TEABAGGING = true
 - TEABAG_SCORE = 0
 - TEAM_TEABAG_SCORE = 0
 - PREVENT_SCORE_ON_KILL = false
 - Set messages to taste


Want more flexibility? Modify the OnTeabag function to do whatever you want.

LICENCE: GNU GPL3
]]

--== General ==--
-- Teabag radius in meters
TEABAG_RADIUS = 2

-- Does teabagging someone you didn't kill count?
TEABAG_STEALING = true

-- Track team teabagging?
TEAM_TEABAGGING = true

--== Messages ==--
-- Message to announce to all (nil for no annoucement)
TEABAG_MESSAGE = nil -- "$baggee was teabagged by $bagger!"

-- Message to send to the baggee (nil for no message)
TEABAG_BAGGEE_MESSAGE = "You were teabagged by $bagger!"
TEAM_TEABAG_BAGGEE_MESSAGE = "You were teabagged by your teammate $bagger!"

-- Message to send to the bagger (nil for no message)
TEABAG_BAGGER_MESSAGE = "You teabagged $baggee!"
TEAM_TEABAG_BAGGER_MESSAGE = "You teabagged your teammate $baggee!"

--== Scoring ==--
-- Score for teabagging someone (can be negative/positive)
TEABAG_SCORE = 1

-- Score for teabagging a teammate (can be negative/positive)
-- Only has an effect if TEAM_TEABAGGING is enabled
TEAM_TEABAG_SCORE = 0

-- Prevent normal scoring?
-- Note: Negative points from team kills and suicides are not prevented
PREVENT_SCORE_ON_KILL = true

----------------- Script ------------------

api_version = "1.12.0.0"

local object_table = nil

-- {owner, killer, body_pointer, player_id}
local bodies = {}
local num_bodies = 0

-- Holds the scores of players
-- Used to prevent scoring when killing a player
local scores = {}

-- Just using distance for a range check - square the target distance to avoid
-- doing a square root when checking distance
-- Convert meters to world units (1wu = 3m)
local TEABAG_SQUARED_DIST = (TEABAG_RADIUS/3)^2


function OnScriptLoad()
    object_table = read_dword(read_dword(sig_scan("8B0D????????8B513425FFFF00008D") + 2))

    register_callback(cb['EVENT_GAME_START'], "OnGameStart")
    register_callback(cb['EVENT_GAME_END'], "OnGameEnd")

    if (get_var(0, '$gt') ~= "") then
        -- Game has already started
        OnGameStart()
    end
end


function OnScriptUnload()

end


function OnGameStart()
    num_bodies = 0
    bodies = {}
    scores = {}

    register_callback(cb['EVENT_TICK'], "OnTick")
    register_callback(cb['EVENT_DIE'], "OnPlayerDie")
    register_callback(cb['EVENT_LEAVE'], "OnPlayerLeave")
    if PREVENT_SCORE_ON_KILL then
        register_callback(cb['EVENT_DAMAGE_APPLICATION'], "OnDamageApplication")
    end
end

function OnGameEnd()
    unregister_callback(cb['EVENT_TICK'])
    unregister_callback(cb['EVENT_DIE'])
    unregister_callback(cb["EVENT_LEAVE"])
    if PREVENT_SCORE_ON_KILL then
        unregister_callback(cb['EVENT_DAMAGE_APPLICATION'])
    end
end


-- The square of the distance between 2 points
function squared_distance(x1, y1, z1, x2, y2, z2)
    return (x1 - x2)^2 + (y1 - y2)^2 + (z1 - z2)^2
end


-- Maps the function over the bodies and removes the ones where it returns true
-- More optimized than repeated `table.remove`s
function remove_bodies(fcn)
    local player_index = 1
    while player_index <= num_bodies do
        if fcn(bodies[player_index]) then
            -- Remove the element by overwriting it with the last element decrementing the length
            bodies[player_index] = bodies[num_bodies]
            bodies[num_bodies] = nil
            num_bodies = num_bodies - 1
        else
            player_index = player_index + 1
        end
    end
end


function format_message(msg, bagger, baggee)
    return string.gsub(string.gsub(msg, "$baggee", baggee), "$bagger", bagger)
end


-- Set the player and team score
function change_score(player_index, score, set)
    -- {in,de}crement the score by adding a "+" before it
    if not set then
        score = "+" .. score
    end

    if get_var(0, "$ffa") == "0" then
        execute_command("team_score " .. get_var(player_index, "$team") .. " " .. score)
    end
    execute_command("score " .. player_index .. " " .. score)

    if PREVENT_SCORE_ON_KILL then
        scores[player_index] = get_var(player_index, "$score")
    end
end


function same_teams(player1, player2)
    -- Team based game and the player's teams are the same
    return get_var(0, "$ffa") == "0" and get_var(player1, "$team") == get_var(player2, "$team")
end


-- Check if a teabag is valid based on the players involved
function can_teabag(killer_index, bagger_index, baggee_index)

    -- Can't teabag self
    if bagger_index == baggee_index then
        return false
    end

    -- Can only teabag team members when TEAM_TEABAGGING is enabled
    if not TEAM_TEABAGGING and same_teams(bagger_index, baggee_index) then
        return false
    end

    -- Bagger needs to be the killer unless teabag stealing is enabled
    return TEABAG_STEALING or killer_index == bagger_index
end


-- Get a pointer to where the data for the body resides
function find_body_ptr(player)
    local object_count = read_word(object_table + 0x2E)
    local first_object = read_dword(object_table + 0x34)
    for player_index=0, object_count - 1 do
        local address = first_object + player_index * 0xC + 0x8
        if read_dword(address) == player then
            return address
        end
    end
    return nil
end


-- Dereferece a pointer to a player body
-- Checks if the body has already been removed
function get_body(address, player_id)
    local object = read_dword(address)
    if object ~= 0 and object ~= 0xFFFFFFFF then
        if read_dword(object + 0xC0) == player_id then
            return object
        end
    end
    return nil
end


-- Called when a player teabags a body
-- return true if the teabag was accepted, false otherwise
function OnTeabag(bagger_index, baggee_index)
    local bagger = get_var(bagger_index, "$name")
    local baggee = get_var(baggee_index, "$name")

    if TEABAG_MESSAGE ~= nil then
        say_all(format_message(TEABAG_MESSAGE, bagger, baggee))
    end
    if same_teams(bagger_index, baggee_index) then
        if TEAM_TEABAG_BAGGEE_MESSAGE ~= nil then
            say(baggee_index, format_message(TEAM_TEABAG_BAGGEE_MESSAGE, bagger, baggee))
        end
        if TEAM_TEABAG_BAGGER_MESSAGE ~= nil then
            say(bagger_index, format_message(TEAM_TEABAG_BAGGER_MESSAGE, bagger, baggee))
        end
        if TEAM_TEABAG_SCORE ~= 0 then
            change_score(bagger_index, TEAM_TEABAG_SCORE)
        end
    else
        if TEABAG_BAGGEE_MESSAGE ~= nil then
            say(baggee_index, format_message(TEABAG_BAGGEE_MESSAGE, bagger, baggee))
        end
        if TEABAG_BAGGER_MESSAGE ~= nil then
            say(bagger_index, format_message(TEABAG_BAGGER_MESSAGE, bagger, baggee))
        end
        if TEABAG_SCORE ~= 0 then
            change_score(bagger_index, TEABAG_SCORE)
        end
    end

    return true
end


function OnPlayerLeave(player_index)
    -- Remove your bodies
    -- Remove the bodies of your victims if teabag stealing is disabled
    remove_bodies(function (b)
        return (b[1] == player_index) or (not TEABAG_STEALING and b[2] == player_index)
    end)

    scores[player_index] = nil
end


function OnTick()
    for player_index=1, 16 do
        local player = get_dynamic_player(player_index)    
        if player == 0 then goto continue end -- dead/not joined

        local vehicle = read_dword(player + 0x11C)
        if vehicle ~= 0xFFFFFFFF then goto continue end -- in a vehicle

        local on_ground = read_bit(player + 0x10, 1) == 1
        if not on_ground then goto continue end -- in the air

        local crouch = read_bit(player + 0x208, 0) == 1
        if not crouch then goto continue end -- not crouching

        local px, py, pz = read_vector3d(player + 0x5C)
        remove_bodies(function(b)
            -- b = owner, killer, body_pointer, player_id

            -- Get body and remove it if it was despawned by the game
            local object = get_body(b[3], b[4])
            if object == nil then return true end

            if can_teabag(b[2], player_index, b[1]) then
                local bx, by, bz = read_vector3d(object + 0x5C)
                if squared_distance(px, py, pz, bx, by, bz) < TEABAG_SQUARED_DIST then
                    return OnTeabag(player_index, b[1])
                end
            end
            return false
        end)
        ::continue::
    end
end


function OnDamageApplication(player_index, causer_index, ...)
    -- Store the score of the damage causer so we can reset it in OnPlayerDie
    -- to prevent the default kill scoring
    if causer_index < 1 then return end
    scores[causer_index] = get_var(causer_index, "$score")
end


function OnPlayerDie(player_index, killer_index)
    killer_index = tonumber(killer_index)

    -- -1 = falling/unknown, 0 = vehicle or AI
    if killer_index < 1 then return end

    -- suicide
    if player_index == killer_index then return end

    local killer_present = player_present(killer_index)

    -- Reset score of killer for a non-team kill if preventing scoring on kill
    if PREVENT_SCORE_ON_KILL and killer_present and not same_teams(player_index, killer_index) then
        local prev_score = scores[killer_index]
        if prev_score ~= nil then
            change_score(killer_index, tonumber(prev_score), true)
        end
    end

    -- If killer has quit and teabag stealing is disabled don't bother recording the death
    if not killer_present and not TEABAG_STEALING then return end

    -- Add player body to list of teabaggable bodies
    local player = get_dynamic_player(player_index)
    if player == 0 then return end

    local body_ptr = find_body_ptr(player)
    if body_ptr == nil then return end

    -- Need to store the player id so when we dereference the body pointer we
    -- can check if it still points at the correct data
    local player_id = read_dword(player + 0xC0)

    num_bodies = num_bodies + 1
    bodies[num_bodies] = {player_index, killer_index, body_ptr, player_id}
end
