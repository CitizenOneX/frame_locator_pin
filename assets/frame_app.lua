local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local imu = require('imu.min')
local sprite = require('sprite.min')
local plain_text = require('plain_text.min')
local sprite_position = require('sprite_position.min')


-- Phone to Frame flags
TEXT_MSG = 0x12
CLEAR_MSG = 0x10
START_IMU_MSG = 0x40
STOP_IMU_MSG = 0x41
POSITION_MSG = 0x50
FAV_SPRITE = 0x20
BANK_SPRITE = 0x21
LEFT_SPRITE = 0x22
RIGHT_SPRITE = 0x23

-- Frame to Phone flags
IMU_DATA_MSG = 0x0A

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_MSG] = plain_text.parse_plain_text
data.parsers[CLEAR_MSG] = code.parse_code
data.parsers[START_IMU_MSG] = code.parse_code
data.parsers[STOP_IMU_MSG] = code.parse_code
data.parsers[POSITION_MSG] = sprite_position.parse_sprite_position
data.parsers[FAV_SPRITE] = sprite.parse_sprite
data.parsers[BANK_SPRITE] = sprite.parse_sprite
data.parsers[LEFT_SPRITE] = sprite.parse_sprite
data.parsers[RIGHT_SPRITE] = sprite.parse_sprite


-- Main app loop
function app_loop()
	-- clear the display
	frame.display.text(" ", 1, 1)
	frame.display.show()
    local last_batt_update = 0
	local streaming = false
	local stream_rate = 1

	while true do
		-- process any raw data items, if ready
		local items_ready = data.process_raw_items()

		-- one or more full messages received
		if items_ready > 0 then

			if (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
				local plain_text = data.app_data[TEXT_MSG]
				local i = 0

				for line in plain_text.string:gmatch("([^\n]*)\n?") do
					if line ~= "" then
						frame.display.text(line, plain_text.x, plain_text.y + i * 60, {color = plain_text.color, spacing = plain_text.spacing})
						i = i + 1
					end
				end
			end

			if (data.app_data[CLEAR_MSG] ~= nil) then
				-- clear the display
				frame.display.text(" ", 1, 1)

				data.app_data[CLEAR_MSG] = nil
			end

			if (data.app_data[START_IMU_MSG] ~= nil) then
				streaming = true
				local rate = data.app_data[START_IMU_MSG].value
				if rate > 0 then
					stream_rate = 1 / rate
				end

				data.app_data[START_IMU_MSG] = nil
			end

			if (data.app_data[STOP_IMU_MSG] ~= nil) then
				streaming = false
				-- clear the display
				frame.display.text(" ", 1, 1)

				data.app_data[STOP_IMU_MSG] = nil
			end

			-- a position update for a sprite
			if (data.app_data[POSITION_MSG] ~= nil) then
				local pos = data.app_data[POSITION_MSG]
				local spr = data.app_data[pos.sprite_code]

				if spr ~= nil then
					print('drawing at: ' .. tostring(pos.x))
					if pos.x < 49 then -- larrow.width + 1/2 * spr.width + 1
						local larrow = data.app_data[LEFT_SPRITE]
						frame.display.bitmap(1, 1, larrow.width, 2^larrow.bpp, 0, larrow.pixel_data)
						frame.display.bitmap(larrow.width + 1, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					elseif pos.x < 561 then -- 640 - 1/2 * spr.width - rarrow.width + 1
						frame.display.bitmap(pos.x, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
					else
						local rarrow = data.app_data[RIGHT_SPRITE]
						frame.display.bitmap(561, 1, spr.width, 2^spr.bpp, 0, spr.pixel_data)
						frame.display.bitmap(625, 1, rarrow.width, 2^rarrow.bpp, 0, rarrow.pixel_data)
					end
				end

				data.app_data[POSITION_MSG] = nil
			end

			-- present the updated display
			frame.display.show()

		end

		-- poll and send the raw IMU data (3-axis magnetometer, 3-axis accelerometer)
		-- Streams until STOP_IMU_MSG is sent from phone
		if streaming then
			imu.send_imu_data(IMU_DATA_MSG)
		end

        -- periodic battery level updates, 120s for a camera app
        last_batt_update = battery.send_batt_if_elapsed(last_batt_update, 120)

		if streaming then
			frame.sleep(stream_rate)
		else
			frame.sleep(0.5)
		end
	end
end

-- run the main app loop
app_loop()