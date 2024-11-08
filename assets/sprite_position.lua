-- Module to parse messages sent from phoneside app as TxSpritePosition messages
_M = {}

-- Parse the TxSpritePosition message raw data
function _M.parse_sprite_position(data)
	local sprite_position = {}
	sprite_position.sprite_code = string.byte(data, 1)
	sprite_position.x = string.byte(data, 2) << 8 | string.byte(data, 3)
	sprite_position.y = string.byte(data, 4) << 8 | string.byte(data, 5)
	sprite_position.palette_offset = string.byte(data, 6)
	return sprite_position
end

return _M