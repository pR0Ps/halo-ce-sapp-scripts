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
	-- [      vehicle tag      ] =       {flying?, gunner seat, boost rate}
	["vehicles\\warthog\\mp_warthog"] =  {false,   2,           0.03},
	["vehicles\\rwarthog\\rwarthog"] =   {false,   2,           0.03},
	["vehicles\\scorpion\\scorpion_mp"] ={false,   nil,         0.01},
	["vehicles\\ghost\\ghost_mp"] =      {true,    nil,         0.022},
	["vehicles\\banshee\\banshee_mp"] =  {true,    nil,         0.022},
}

-- Script

api_version = "1.12.0.0"

prev_rider_eject = nil

-- unpack without the bug that stops at nil values
function unpack_(t)
	return unpack(t, 1, table.maxn(t))
end

function OnScriptLoad()
	if AUTO_FLIP or CROUCH_BOOST then
		register_callback(cb['EVENT_TICK'], "OnTick")
	end
	if DRIVE_AS_GUNNER then
		-- TODO: OnVehicleExit to assign driver privs to gunner if driver exits
		-- TODO: gunner gets driving privs removed if driver enters
		register_callback(cb['EVENT_VEHICLE_ENTER'], "OnVehicleEnter")
	end
	if DISABLE_EJECTION then
		prev_rider_eject = read_byte(0x59A34C)
		write_byte(0x59A34C, 0)
	end
end

function GetVehicleData(player)
    local id = read_dword(player + 0x11C)
	local vehicle = nil
	local name = nil
	local conf = nil
    if id ~= 0xFFFFFFFF then
	    vehicle = get_object_memory(id)
		name = read_string(read_dword(lookup_tag(read_dword(vehicle)) + 0xF))
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
		local on_ground = read_bit(vehicle + 0x10, 1)
		local flipped_over = read_bit(vehicle + 0x8B, 7)
		local x_vel, y_vel, z_vel = read_vector3d(vehicle + 0x68)
		local speed = math.abs(x_vel) + math.abs(y_vel) + math.abs(z_vel)
		
		-- Handle auto-flip
		if AUTO_FLIP and flipped_over == 1 and (on_ground == 1 or flying_vehicle) then
			if (FLIP_MAX_SPEED == nil or speed <= FLIP_MAX_SPEED) then
				write_vector3d(vehicle + 0x80, 0, 0, 1)
			end
		end
		
		-- Handle boosting
		if boost_rate == nil then goto continue end
		
		-- check if the player is driving
		local seat = read_word(player + 0x2F0)
		local is_driving = (seat == 0)
		
		-- special case for when the gunner is driving
		if not is_driving and DRIVE_AS_GUNNER and gunner_seat ~= nil and seat == gunner_seat then
			local driver = read_dword(vehicle + 0x324)
			local gunner = read_dword(vehicle + 0x324 + 2 * gunner_seat)
			is_driving = (driver == gunner)
		end
		
		if not is_driving then goto continue end
		
		local crouch_key = read_bit(vehicle + 0x4CC, 2)
		if crouch_key == 0 then goto continue end
		
		if flying_vehicle or (on_ground == 1 and flipped_over == 0) then
			if x_vel ~= 0 and y_vel ~= 0 then
				local pitch, yaw, roll = read_vector3d(vehicle + 0x74)
				local x, y, z = read_vector3d(vehicle + 0x5C)
				write_float(vehicle + 0x68, x_vel + boost_rate * pitch)
				write_float(vehicle + 0x6C, y_vel + boost_rate * yaw)
				-- teleport player to help with desyncs
				--[[
				TODO:
					try ignoring gravity (write_bit(m_object + 0x10, 2, 0)) to reduce decyncs
					writefloat(m_vehicle + 0x8C, readfloat(m_vehicle, 0x8C)*turn_multiplier) -- reduces pitch velocity for better handling
                    writefloat(m_vehicle + 0x90, readfloat(m_vehicle, 0x90)*turn_multiplier) -- reduces yaw velocity for better handling
                    writefloat(m_vehicle + 0x94, readfloat(m_vehicle, 0x94)*turn_multiplier) -- reduces roll velocity for better handling
				]]
				execute_command("t "..i.." "..x.." "..y.." "..z)
			end
		end
		::continue::
    end
end

function OnVehicleEnter(PlayerIndex, Seat_str)
	local player = get_dynamic_player(PlayerIndex)
	if player == 0 then return end
	
	local vehicle_id, vehicle_name, vehicle, vehicle_conf = GetVehicleData(player)
	if vehicle_conf == nil then return end

	local gunner_seat = vehicle_conf[2]
	if gunner_seat == nil then return end
	
	local driver = read_dword(vehicle + 0x324)
	local seat = tonumber(Seat_str)
	
	if seat == 0 then -- driver seat
		if driver ~= 0xFFFFFFFF then
			exit_vehicle(PlayerIndex)
		end
	elseif seat == gunner_seat then -- gunner seat
		if driver == 0xFFFFFFFF then
			enter_vehicle(vehicle_id, PlayerIndex, 0)
			exit_vehicle(PlayerIndex)
			enter_vehicle(vehicle_id, PlayerIndex, 0)
			enter_vehicle(vehicle_id, PlayerIndex, gunner_seat)
		end
	end	
end

function OnScriptUnload()
	if prev_rider_eject ~= nil then
		write_byte(0x59A34C, prev_rider_eject)
	end
end