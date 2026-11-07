-- From Polestar's Maps/WorldMap.lua (its data part, as it is): zone level ranges, filled by ZoneLevels.lua.
-- Written by tools/sync_polestar.py: do not edit.

local ADDON, ns = ...
local Maps = ns.Maps or {}
ns.Maps = Maps

local levels = {} -- uiMapID -> { min, max, labelX, labelY }

function Maps.RegisterZoneLevels(tbl)
	if type(tbl) ~= "table" then return end
	for id, v in pairs(tbl) do
		if type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" then levels[id] = v end
	end
end

-- min, max | nil
function Maps.GetZoneLevels(uiMapID)
	local v = uiMapID and levels[uiMapID]
	if not v then return nil end
	return v[1], v[2]
end

-- Every zone with a level range: for uiMapID, min, max in Maps.EachZoneLevels() do ... end
function Maps.EachZoneLevels()
	local id
	return function()
		local v
		id, v = next(levels, id)
		if id ~= nil then return id, v[1], v[2] end
	end
end
