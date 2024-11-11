local data = require('data.min')
local battery = require('battery.min')
local code = require('code.min')
local imu = require('imu.min')
local sprite = require('sprite.min')
local plain_text = require('plain_text.min')
local multi_poi = require('multi_poi')


-- Phone to Frame flags
TEXT_MSG = 0x12
CLEAR_MSG = 0x10
START_IMU_MSG = 0x40
STOP_IMU_MSG = 0x41
FAV_SPRITE = 0x20
BANK_SPRITE = 0x21
LEFT_SPRITE = 0x22
RIGHT_SPRITE = 0x23
MULTI_POI_MSG = 0x50

-- Frame to Phone flags
IMU_DATA_MSG = 0x0A

-- register the message parsers so they are automatically called when matching data comes in
data.parsers[TEXT_MSG] = plain_text.parse_plain_text
data.parsers[CLEAR_MSG] = code.parse_code
data.parsers[START_IMU_MSG] = code.parse_code
data.parsers[STOP_IMU_MSG] = code.parse_code
data.parsers[FAV_SPRITE] = sprite.parse_sprite
data.parsers[BANK_SPRITE] = sprite.parse_sprite
data.parsers[LEFT_SPRITE] = sprite.parse_sprite
data.parsers[RIGHT_SPRITE] = sprite.parse_sprite
data.parsers[MULTI_POI_MSG] = multi_poi.parse_multi_poi


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
			-- Sample the imu pitch to move the POI markers vertically
			-- TODO could sample this on every frame and render on every frame, not just when messages are received
			local pitch = math.floor(frame.imu.direction()['pitch'] * 8)
			if pitch < 0 then
				pitch = 0
			elseif pitch > 240 then
				pitch = 240
			end


			if (data.app_data[TEXT_MSG] ~= nil and data.app_data[TEXT_MSG].string ~= nil) then
				local plain_text = data.app_data[TEXT_MSG]
				local i = 0

				for line in plain_text.string:gmatch("([^\n]*)\n?") do
					if line ~= "" then
						frame.display.text(line, plain_text.x, plain_text.y + i * 60 + pitch, {color = plain_text.color, spacing = plain_text.spacing})
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

			-- position update for all the POIs we're tracking
			if (data.app_data[MULTI_POI_MSG] ~= nil) then
				local poi_list = data.app_data[MULTI_POI_MSG].poi_list
				local larrow = data.app_data[LEFT_SPRITE]
				local rarrow = data.app_data[RIGHT_SPRITE]

				for i,poi in ipairs(poi_list) do
					local spr = data.app_data[poi.sprite_code]
					local half_spr_w = spr.width // 2

					-- draw the POI sprite
					if spr ~= nil then
						if poi.x <= (larrow.width + half_spr_w + 1) then
							frame.display.bitmap(1, 1 + pitch, larrow.width, 2^larrow.bpp, poi.palette_offset, larrow.pixel_data)
							frame.display.bitmap(larrow.width + 1, 1 + pitch, spr.width, 2^spr.bpp, poi.palette_offset, spr.pixel_data)
						elseif poi.x < (640 - half_spr_w - rarrow.width) then
							frame.display.bitmap(poi.x - half_spr_w, 1 + pitch, spr.width, 2^spr.bpp, poi.palette_offset, spr.pixel_data)
						else
							frame.display.bitmap(640 - spr.width - rarrow.width, 1 + pitch, spr.width, 2^spr.bpp, poi.palette_offset, spr.pixel_data)
							frame.display.bitmap(640 - rarrow.width, 1 + pitch, rarrow.width, 2^rarrow.bpp, poi.palette_offset, rarrow.pixel_data)
						end
					end

					-- if there's a label then draw it under the sprite too
					if poi.label ~= nil then
						frame.display.text(poi.label, poi.x - 45, 64 + pitch, {color = 'WHITE', spacing = 4})
					end
				end

				data.app_data[MULTI_POI_MSG] = nil
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