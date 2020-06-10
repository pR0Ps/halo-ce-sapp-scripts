--[[

Modified vehicles

Adapted from work by Devieth, giraffe, aLTis

LICENCE: GNU GPL3
]]
-- Features
DRIVE_AS_GUNNER = true
CROUCH_BOOST = true
AUTO_FLIP = true
DISABLE_EJECTION = true -- auto-flipping is basically useless without this enabled

-- TODO: temp shield? (can I make the vehicle/occupants glow with shields?)
-- TODO: flying?
-- TODO: max speed/boost limits
-- TODO: make controlling easier by damping turning

-- only flip the vehicle if it's under this speed (nil for always flip)
FLIP_MAX_SPEED = 0.05

-- Only vehicles in this table will be flipped/boosted/driven from gunner seat
VEHICLE_DATA = {
    -- [      vehicle tag      ] =       {flying?, gunner_seat, boost rate}
    ["vehicles\\warthog\\mp_warthog"] =  {false,   2,           0.03},
    ["vehicles\\rwarthog\\rwarthog"] =   {false,   2,           0.03},
    ["vehicles\\scorpion\\scorpion_mp"] ={false,   0,           0.01},
    ["vehicles\\ghost\\ghost_mp"] =      {true,    0,           0.022},
    ["vehicles\\banshee\\banshee_mp"] =  {true,    0,           0.022},
}

-- Script

api_version = "1.12.0.0"

prev_rider_eject = nil

-- unpack without the bug that stops at nil values
function unpack_(t)
    return unpack(t, 1, table.maxn(t))
end

function find_body_ptr(player)
    local object_table = read_dword(read_dword(sig_scan("8B0D????????8B513425FFFF00008D") + 2))
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

function OnScriptLoad()
    if AUTO_FLIP or CROUCH_BOOST then
        register_callback(cb['EVENT_TICK'], "OnTick")
    end
    if DRIVE_AS_GUNNER then
        -- TODO: OnVehicleExit to assign driver privs to gunner if driver exits
        -- TODO: gunner gets driving privs removed if driver enters
        register_callback(cb['EVENT_VEHICLE_ENTER'], "OnVehicleEnter")
        register_callback(cb['EVENT_VEHICLE_EXIT'], "OnVehicleExit")
    end
    if DISABLE_EJECTION then
        prev_rider_eject = read_byte(0x59A34C)
        write_byte(0x59A34C, 0)
    end

    register_callback(cb['EVENT_OBJECT_SPAWN'], "OnObjectSpawn")
end

function OnObjectSpawn(PlayerIndex, TagID, ParentObjectID, NewObjectID, SappSpawn)
    cprint("SPAWN")
    cprint("" .. PlayerIndex .. " " .. TagID .. " " .. ParentObjectID .. " " .. NewObjectID .. " " .. SappSpawn)
    -- server: 0 3861578935 4294967295 3809607799
    -- script: 0 3797811434 4294967295 3809869937
    cprint("SPAWN")
end


function GetVehicleData(player)
    local id = read_dword(player + 0x11C)
    local vehicle = nil
    local name = nil
    local conf = nil
    if id ~= 0xFFFFFFFF then
        vehicle = get_object_memory(id)
        name = read_string(read_dword(lookup_tag(read_dword(vehicle)) + 0x10))
        conf = VEHICLE_DATA[name]
    end
    return id, name, vehicle, conf
end

function OnTick()
    for i=1,16 do
        local player = get_dynamic_player(i)
        if player == 0 then goto continue end -- dead/not joined

        local vehicle_id, vehicle_name, vehicle, vehicle_conf = GetVehicleData(player)
        if vehicle_conf == nil then goto continue end

        local flying_vehicle, gunner_seat, boost_rate = unpack_(vehicle_conf)
        local on_ground = read_bit(vehicle + 0x10, 1) == 1
        local flipped_over = read_bit(vehicle + 0x8B, 7) == 1
        local x_vel, y_vel, z_vel = read_vector3d(vehicle + 0x68)
        local speed = math.abs(x_vel) + math.abs(y_vel) + math.abs(z_vel)

        -- Handle auto-flip
        if AUTO_FLIP and flipped_over and (on_ground or flying_vehicle) then
            if (FLIP_MAX_SPEED == nil or speed <= FLIP_MAX_SPEED) then
                write_vector3d(vehicle + 0x80, 0, 0, 1)
            end
        end

        if boost_rate == nil then goto continue end

        -- check crouch key is pressed
        local crouch_key = read_bit(vehicle + 0x4CC, 2) == 1
        if not crouch_key then goto continue end

        -- check if the player is driving
        local seat = read_word(player + 0x2F0)
        local is_driving = (seat == 0)

        -- special case for when the gunner is driving
        if DRIVE_AS_GUNNER and not is_driving and gunner_seat == seat then
            local driver = read_dword(vehicle + 0x324)
            local gunner = read_dword(vehicle + 0x328)
            is_driving = (driver == gunner)
        end

        if not is_driving then goto continue end

        if flying_vehicle or (on_ground and not flipped_over) then
            if x_vel ~= 0 and y_vel ~= 0 then
                local pitch, yaw, roll = read_vector3d(vehicle + 0x74)
                local x, y, z = read_vector3d(vehicle + 0x5C)
                write_float(vehicle + 0x68, x_vel + boost_rate * pitch)
                write_float(vehicle + 0x6C, y_vel + boost_rate * yaw)
                --[[
                TODO:
                    writefloat(m_vehicle + 0x8C, readfloat(m_vehicle, 0x8C)*turn_multiplier) -- reduces pitch velocity for better handling
                    writefloat(m_vehicle + 0x90, readfloat(m_vehicle, 0x90)*turn_multiplier) -- reduces yaw velocity for better handling
                    writefloat(m_vehicle + 0x94, readfloat(m_vehicle, 0x94)*turn_multiplier) -- reduces roll velocity for better handling
                ]]
                -- Set the position of the driver to help with desync jank.
                -- Passengers already just accept their new positions whereas the driver is actually
                -- controlling the vehicle so there's a client/server discrepancy. Forcing the client
                -- to update the driver's position every tick like a passenger does seems to remove
                -- the majority of desycing and glitching.
                execute_command("t " .. i .. " " .. x .. " " .. y .. " " .. z)
            end
        end
        ::continue::
    end
end

function OnVehicleEnter(PlayerIndex, seat)
    cprint("OnEnter: " .. PlayerIndex .. " " .. seat)
    cprint("---------------")

    local player = get_player(PlayerIndex)
    if player == 0 then return end

    local player_obj_id = read_dword(player + 0x34)
    local player_memory = get_object_memory(player_obj_id)
    
    local vehicle_id, vehicle_name, vehicle, vehicle_conf = GetVehicleData(player_memory)
    if vehicle_conf == nil then return end

    cprint("vehicle: " .. vehicle_name)

    local driver = read_dword(vehicle + 0x324)
    local gunner = read_dword(vehicle + 0x328)
    cprint("driver: " .. driver)
    cprint("gunner: " .. gunner)

    -- Only need to customize things if there's a non-driver gunner seat
    local gunner_seat = vehicle_conf[2]
    if gunner_seat == 0 then return end

    if player_obj_id == driver then
        cprint("driving")
    end
    if player_obj_id == gunner then
        cprint("gunning")
    end
    cprint("")

    spawn_object("weap", "weapons\\assault rifle\\assault rifle")

    local seat = tonumber(seat)

    if seat == 0 then -- driver seat
        if player_obj_id == driver then return end

        if driver ~= 0xFFFFFFFF then
            cprint("driving denied")
            exit_vehicle(PlayerIndex)
            return
        end

        -- Deny entry if someone is already driving
        if driver ~= 0xFFFFFFFF then
            --cprint("driving denied")
            --exit_vehicle(PlayerIndex)
        end
    elseif seat == gunner_seat then -- gunner seat
        if driver == 0xFFFFFFFF then
            --exit the gunner seat, then enter the driver then gunner seat
            --enter_vehicle(vehicle_id, PlayerIndex, 1)
            timer(2000, "exit_vehicle", PlayerIndex)
            --enter_vehicle(vehicle_id, PlayerIndex, 0)
            --enter_vehicle(vehicle_id, PlayerIndex, 2)
        end
    end
end

function OnVehicleExit(PlayerIndex)
    cprint("OnVehicleExit")
    cprint("-------")
    local vehicle_id, vehicle_name, vehicle, vehicle_conf = GetVehicleData(get_dynamic_player(PlayerIndex))
    local driver = read_dword(vehicle + 0x324)
    local gunner = read_dword(vehicle + 0x328)
    cprint("driver: " .. driver)
    cprint("gunner: " .. gunner)
    cprint("-------")
    cprint("")
end

function OnScriptUnload()
    if prev_rider_eject ~= nil then
        write_byte(0x59A34C, prev_rider_eject)
    end
end