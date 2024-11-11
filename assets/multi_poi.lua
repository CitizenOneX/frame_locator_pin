-- Module to parse MultiPoi messages sent from phoneside app as TxMultiPoi messages
local _M = {}

-- Parse a single POI from the raw data starting at the given offset
-- Returns the parsed POI and the number of bytes consumed
function _M.parse_poi(data, offset)
    local poi = {}
    poi.sprite_code = string.byte(data, offset)
    poi.x = string.byte(data, offset + 1) << 8 | string.byte(data, offset + 2)
    poi.palette_offset = string.byte(data, offset + 3) & 0x0F  -- mask to 4 bits

    -- Get string length and extract string
    local strlen = string.byte(data, offset + 4)
    poi.label = string.sub(data, offset + 5, offset + 4 + strlen)

    -- Calculate total bytes consumed: 5 fixed bytes + string length
    local bytes_consumed = 5 + strlen

    return poi, bytes_consumed
end

-- Parse the MultiPoi message raw data
function _M.parse_multi_poi(data)
    local result = {}
    result.msg_code = string.byte(data, 1)
    local num_pois = string.byte(data, 2)
    result.poi_list = {}

    local offset = 3  -- Start after msg_code and num_pois
    for i = 1, num_pois do
        local poi, bytes_consumed = _M.parse_poi(data, offset)
        table.insert(result.poi_list, poi)
        offset = offset + bytes_consumed
    end

    return result
end

return _M